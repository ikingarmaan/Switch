import Foundation
import Cocoa

public final class GrammarAIService: ObservableObject, @unchecked Sendable {
    public static let shared = GrammarAIService()
    
    private let userDefaultsKey = "Switch_Gemini_API_Key"
    
    @Published public var geminiApiKey: String {
        didSet {
            UserDefaults.standard.set(geminiApiKey, forKey: userDefaultsKey)
        }
    }
    
    @Published public private(set) var isAIQuerying: Bool = false
    @Published public private(set) var lastEngineUsed: String = "LanguageTool AI"
    
    private var cache: [String: String] = [:]
    
    private init() {
        self.geminiApiKey = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
    }
    
    public var hasGeminiKey: Bool {
        !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - LanguageTool Models
    
    struct LTResponse: Codable {
        struct Match: Codable {
            struct Replacement: Codable {
                let value: String
            }
            let message: String?
            let offset: Int
            let length: Int
            let replacements: [Replacement]
        }
        let matches: [Match]
    }
    
    // MARK: - Gemini Models
    
    struct GeminiResponse: Codable {
        struct Candidate: Codable {
            struct Content: Codable {
                struct Part: Codable {
                    let text: String?
                }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }
    
    // MARK: - Main AI Polish Pipeline
    
    public func polishWithAI(text: String, style: WritingStyle, completion: @escaping (String, [String]) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(text, [])
            return
        }
        
        let cacheKey = "\(style.rawValue):\(trimmed)"
        if let cached = cache[cacheKey] {
            completion(cached, ["Restored from AI cache"])
            return
        }
        
        DispatchQueue.main.async {
            self.isAIQuerying = true
        }
        
        // 1. Try Gemini API if key is present
        if hasGeminiKey {
            callGeminiAPI(text: trimmed, style: style, apiKey: geminiApiKey) { [weak self] geminiOutput in
                guard let self = self else { return }
                if let output = geminiOutput, !output.isEmpty {
                    self.cache[cacheKey] = output
                    DispatchQueue.main.async {
                        self.isAIQuerying = false
                        self.lastEngineUsed = "Gemini 2.5 Flash"
                    }
                    completion(output, ["AI Rewriting via Google Gemini 2.5 Flash", "Tone: \(style.rawValue) Business Precision"])
                    return
                }
                
                // Fallback to LanguageTool AI
                self.fallbackToLanguageTool(text: trimmed, style: style, cacheKey: cacheKey, completion: completion)
            }
        } else {
            // 2. Free LanguageTool Neural AI + Tone Engine
            fallbackToLanguageTool(text: trimmed, style: style, cacheKey: cacheKey, completion: completion)
        }
    }
    
    private func fallbackToLanguageTool(text: String, style: WritingStyle, cacheKey: String, completion: @escaping (String, [String]) -> Void) {
        callLanguageToolAPI(text: text) { [weak self] ltCorrected in
            guard let self = self else { return }
            
            // Pipe LanguageTool corrections through Tone & Phrasing Engine
            let toneResult = GrammarCoachService.shared.polishText(ltCorrected, style: style)
            let finalOutput = toneResult.polished
            
            self.cache[cacheKey] = finalOutput
            DispatchQueue.main.async {
                self.isAIQuerying = false
                self.lastEngineUsed = "LanguageTool Neural AI"
            }
            
            var changes = toneResult.changes
            changes.insert("Grammar & Spell Corrections via LanguageTool AI", at: 0)
            completion(finalOutput, changes)
        }
    }
    
    // MARK: - Gemini API Call
    
    private func callGeminiAPI(text: String, style: WritingStyle, apiKey: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 7.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let promptText: String
        if style == .formal {
            promptText = "You are an elite business editor. Rewrite the following English text into elegant, flawless, highly professional business English. Fix all grammar errors, misspelled words, and informal phrasing. Maintain the exact original intent. Output ONLY the rewritten text, without quotes or additional commentary.\n\nInput: \(text)"
        } else {
            promptText = "You are a friendly communication coach. Rewrite the following English text into warm, natural, friendly everyday conversational English. Fix all grammar errors, typos, and awkward phrasing while keeping an approachable modern tone. Maintain the exact original intent. Output ONLY the rewritten text, without quotes or additional commentary.\n\nInput: \(text)"
        }
        
        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": promptText]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.25
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(nil)
            return
        }
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let decoded = try? JSONDecoder().decode(GeminiResponse.self, from: data),
                  let firstCandidate = decoded.candidates?.first,
                  let part = firstCandidate.content?.parts?.first,
                  let output = part.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                completion(nil)
                return
            }
            completion(output)
        }.resume()
    }
    
    // MARK: - LanguageTool API Call
    
    private func callLanguageToolAPI(text: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "https://api.languagetool.org/v2/check") else {
            completion(text)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4.0
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "text=" + (text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") + "&language=en-US"
        request.httpBody = bodyString.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let decoded = try? JSONDecoder().decode(LTResponse.self, from: data) else {
                completion(text)
                return
            }
            
            var result = text
            let sortedMatches = decoded.matches.sorted { $0.offset > $1.offset }
            for match in sortedMatches {
                if let bestRep = match.replacements.first?.value {
                    let nsString = result as NSString
                    if match.offset + match.length <= nsString.length {
                        let range = NSRange(location: match.offset, length: match.length)
                        result = nsString.replacingCharacters(in: range, with: bestRep)
                    }
                }
            }
            completion(result)
        }.resume()
    }
}
