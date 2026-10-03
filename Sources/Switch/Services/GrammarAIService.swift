import Foundation
import Cocoa

public enum AIEngine: String, CaseIterable, Identifiable, Sendable {
    case appleNative = "appleNative"
    case gemini = "gemini"
    case groq = "groq"
    case openai = "openai"
    case ollama = "ollama"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .appleNative: return "Apple Native Engine (Offline & Fast)"
        case .gemini: return "Google Gemini 2.5 Flash"
        case .groq: return "Groq Llama 3.3 70B (Ultra-Fast)"
        case .openai: return "OpenAI GPT-4o-mini"
        case .ollama: return "Ollama Local (Offline LLM)"
        }
    }
    
    public var shortName: String {
        switch self {
        case .appleNative: return "🍏 Apple Native"
        case .gemini: return "✨ Gemini 2.5"
        case .groq: return "⚡️ Groq Llama"
        case .openai: return "🧠 GPT-4o-mini"
        case .ollama: return "🦙 Ollama"
        }
    }
    
    public var icon: String {
        switch self {
        case .appleNative: return "apple.logo"
        case .gemini: return "sparkles"
        case .groq: return "bolt.fill"
        case .openai: return "cpu"
        case .ollama: return "desktopcomputer"
        }
    }
    
    public var isOffline: Bool {
        switch self {
        case .appleNative, .ollama: return true
        default: return false
        }
    }
}

public final class GrammarAIService: ObservableObject, @unchecked Sendable {
    public static let shared = GrammarAIService()
    
    private let keyEngine = "Switch_Selected_AIEngine"
    private let keyGemini = "Switch_Gemini_API_Key"
    private let keyGroq = "Switch_Groq_API_Key"
    private let keyOpenAI = "Switch_OpenAI_API_Key"
    private let keyOllamaEndpoint = "Switch_Ollama_Endpoint"
    private let keyOllamaModel = "Switch_Ollama_Model"
    
    @Published public var selectedEngine: AIEngine {
        didSet {
            UserDefaults.standard.set(selectedEngine.rawValue, forKey: keyEngine)
        }
    }
    
    @Published public var geminiApiKey: String {
        didSet {
            UserDefaults.standard.set(geminiApiKey, forKey: keyGemini)
        }
    }
    
    @Published public var groqApiKey: String {
        didSet {
            UserDefaults.standard.set(groqApiKey, forKey: keyGroq)
        }
    }
    
    @Published public var openaiApiKey: String {
        didSet {
            UserDefaults.standard.set(openaiApiKey, forKey: keyOpenAI)
        }
    }
    
    @Published public var ollamaEndpoint: String {
        didSet {
            UserDefaults.standard.set(ollamaEndpoint, forKey: keyOllamaEndpoint)
        }
    }
    
    @Published public var ollamaModel: String {
        didSet {
            UserDefaults.standard.set(ollamaModel, forKey: keyOllamaModel)
        }
    }
    
    @Published public private(set) var isAIQuerying: Bool = false
    @Published public private(set) var lastEngineUsed: String = "Apple Native"
    @Published public private(set) var lastQueryDurationMs: Int = 0
    
    private var cache: [String: (result: String, changes: [String])] = [:]
    
    private init() {
        let savedEngine = UserDefaults.standard.string(forKey: keyEngine) ?? AIEngine.appleNative.rawValue
        self.selectedEngine = AIEngine(rawValue: savedEngine) ?? .appleNative
        self.geminiApiKey = UserDefaults.standard.string(forKey: keyGemini) ?? ""
        self.groqApiKey = UserDefaults.standard.string(forKey: keyGroq) ?? ""
        self.openaiApiKey = UserDefaults.standard.string(forKey: keyOpenAI) ?? ""
        self.ollamaEndpoint = UserDefaults.standard.string(forKey: keyOllamaEndpoint) ?? "http://localhost:11434"
        self.ollamaModel = UserDefaults.standard.string(forKey: keyOllamaModel) ?? "llama3"
    }
    
    public var hasGeminiKey: Bool {
        !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var hasGroqKey: Bool {
        !groqApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var hasOpenAIKey: Bool {
        !openaiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    public var isCurrentEngineConfigured: Bool {
        switch selectedEngine {
        case .appleNative:
            return true
        case .gemini:
            return hasGeminiKey
        case .groq:
            return hasGroqKey
        case .openai:
            return hasOpenAIKey
        case .ollama:
            return true
        }
    }
    
    // MARK: - Main AI Polish Pipeline
    
    public func polishWithAI(text: String, style: WritingStyle, completion: @escaping (String, [String]) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(text, [])
            return
        }
        
        let engine = selectedEngine
        let cacheKey = "\(engine.rawValue):\(style.rawValue):\(trimmed)"
        if let cached = cache[cacheKey] {
            completion(cached.result, cached.changes)
            return
        }
        
        let startTime = DispatchTime.now()
        
        DispatchQueue.main.async {
            self.isAIQuerying = true
        }
        
        let finish = { [weak self] (polished: String, engineName: String, changes: [String]) in
            guard let self = self else { return }
            let durationNanos = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
            let durationMs = Int(durationNanos / 1_000_000)
            
            self.cache[cacheKey] = (polished, changes)
            
            DispatchQueue.main.async {
                self.isAIQuerying = false
                self.lastEngineUsed = engineName
                self.lastQueryDurationMs = durationMs
            }
            completion(polished, changes)
        }
        
        switch engine {
        case .gemini:
            if hasGeminiKey {
                callGeminiAPI(text: trimmed, style: style, apiKey: geminiApiKey) { [weak self] output in
                    guard self != nil else { return }
                    if let output = output, !output.isEmpty {
                        finish(output, "Gemini 2.5 Flash", ["AI Rewriting via Google Gemini 2.5 Flash", "Style: \(style.badge)"])
                    } else {
                        // Fallback to Native
                        let native = GrammarCoachService.shared.polishNative(trimmed, style: style)
                        finish(native.polished, "Apple Native (Gemini Fallback)", native.changes)
                    }
                }
            } else {
                let native = GrammarCoachService.shared.polishNative(trimmed, style: style)
                var ch = native.changes
                ch.insert("Using Apple Native Engine (Add Gemini API Key in Settings for LLM Mode)", at: 0)
                finish(native.polished, "Apple Native", ch)
            }
            
        case .groq:
            if hasGroqKey {
                callOpenAICompatibleAPI(
                    endpoint: "https://api.groq.com/openai/v1/chat/completions",
                    model: "llama-3.3-70b-versatile",
                    apiKey: groqApiKey,
                    text: trimmed,
                    style: style
                ) { [weak self] output in
                    guard self != nil else { return }
                    if let output = output, !output.isEmpty {
                        finish(output, "Groq Llama 3.3 70B", ["AI Rewriting via Groq Cloud (Llama 3.3 70B)", "Style: \(style.badge)"])
                    } else {
                        let native = GrammarCoachService.shared.polishNative(trimmed, style: style)
                        finish(native.polished, "Apple Native (Groq Fallback)", native.changes)
                    }
                }
            } else {
                let native = GrammarCoachService.shared.polishNative(trimmed, style: style)
                var ch = native.changes
                ch.insert("Using Apple Native Engine (Add Groq API Key in Settings for Llama 3.3)", at: 0)
                finish(native.polished, "Apple Native", ch)
            }
            
        case .openai:
            if hasOpenAIKey {
                callOpenAICompatibleAPI(
                    endpoint: "https://api.openai.com/v1/chat/completions",
                    model: "gpt-4o-mini",
                    apiKey: openaiApiKey,
                    text: trimmed,
                    style: style
                ) { [weak self] output in
                    guard self != nil else { return }
                    if let output = output, !output.isEmpty {
                        finish(output, "GPT-4o-mini", ["AI Rewriting via OpenAI GPT-4o-mini", "Style: \(style.badge)"])
                    } else {
                        let native = GrammarCoachService.shared.polishNative(trimmed, style: style)
                        finish(native.polished, "Apple Native (OpenAI Fallback)", native.changes)
                    }
                }
            } else {
                let native = GrammarCoachService.shared.polishNative(trimmed, style: style)
                var ch = native.changes
                ch.insert("Using Apple Native Engine (Add OpenAI API Key in Settings for GPT-4o)", at: 0)
                finish(native.polished, "Apple Native", ch)
            }
            
        case .ollama:
            callOllamaAPI(text: trimmed, style: style) { [weak self] output in
                guard let self = self else { return }
                if let output = output, !output.isEmpty {
                    finish(output, "Ollama (\(self.ollamaModel))", ["Offline LLM Rewriting via Ollama (\(self.ollamaModel))", "Style: \(style.badge)"])
                } else {
                    let native = GrammarCoachService.shared.polishNative(trimmed, style: style)
                    var ch = native.changes
                    ch.insert("Ollama unreachable on \(self.ollamaEndpoint). Used Apple Native Engine.", at: 0)
                    finish(native.polished, "Apple Native (Ollama Offline)", ch)
                }
            }
            
        case .appleNative:
            let native = GrammarCoachService.shared.polishNative(trimmed, style: style)
            finish(native.polished, "Apple Native Engine", native.changes)
        }
    }
    
    // MARK: - Prompt Builder
    
    private func buildPrompt(text: String, style: WritingStyle) -> String {
        switch style {
        case .fixOnly:
            return """
            You are a precision English editor.
            TASK: Correct all spelling errors, grammatical mistakes, typos, punctuation, and capitalization in the text below.
            CRITICAL RULES:
            1. Keep the author's original words, vocabulary, sentence structure, and personal voice intact.
            2. Do NOT paraphrase, do NOT add new ideas, and do NOT replace informal words with fancy words unless they are grammatically wrong.
            3. Output ONLY the corrected text. Do NOT add quotes, markdown headers, or explanations.
            
            Text:
            \(text)
            """
        case .formal:
            return """
            You are an expert executive communication coach.
            TASK: Rewrite the following text into elegant, flawless, highly professional English suitable for business emails and workplace communication.
            CRITICAL RULES:
            1. Maintain the exact original facts, points, and intent.
            2. Sound natural, confident, and polite. Avoid sounding archaic, stiff, or overly robotic.
            3. Output ONLY the improved text. Do NOT add quotes, markdown headers, or explanations.
            
            Text:
            \(text)
            """
        case .casual:
            return """
            You are a friendly writing coach.
            TASK: Rewrite the following text into warm, natural, friendly, everyday conversational English.
            CRITICAL RULES:
            1. Maintain the exact original meaning and intent.
            2. Use natural contractions and approachable phrasing for chat and casual messages.
            3. Output ONLY the improved text. Do NOT add quotes, markdown headers, or explanations.
            
            Text:
            \(text)
            """
        case .concise:
            return """
            You are a high-efficiency communications editor.
            TASK: Make the following text concise, punchy, and clear.
            CRITICAL RULES:
            1. Cut wordiness, filler phrases, and redundancy while preserving all key information.
            2. Keep it direct and easy to read.
            3. Output ONLY the improved text. Do NOT add quotes, markdown headers, or explanations.
            
            Text:
            \(text)
            """
        case .elevate:
            return """
            You are an articulate literary editor.
            TASK: Elevate the following text with expressive, compelling vocabulary, elegant phrasing, and fluid sentence transitions.
            CRITICAL RULES:
            1. Preserve the author's core message faithfully.
            2. Output ONLY the improved text. Do NOT add quotes, markdown headers, or explanations.
            
            Text:
            \(text)
            """
        }
    }
    
    // MARK: - Google Gemini API
    
    private func callGeminiAPI(text: String, style: WritingStyle, apiKey: String, completion: @escaping (String?) -> Void) {
        // Try gemini-2.5-flash first, fallback to gemini-1.5-flash
        let prompt = buildPrompt(text: text, style: style)
        
        func tryEndpoint(model: String, onFail: @escaping () -> Void) {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
                onFail()
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 8.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload: [String: Any] = [
                "contents": [
                    [
                        "parts": [
                            ["text": prompt]
                        ]
                    ]
                ],
                "generationConfig": [
                    "temperature": 0.2
                ]
            ]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
                onFail()
                return
            }
            request.httpBody = jsonData
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    onFail()
                    return
                }
                
                guard let data = data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let outputText = firstPart["text"] as? String else {
                    onFail()
                    return
                }
                
                let cleaned = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    completion(cleaned)
                } else {
                    onFail()
                }
            }.resume()
        }
        
        tryEndpoint(model: "gemini-2.5-flash") {
            tryEndpoint(model: "gemini-1.5-flash") {
                completion(nil)
            }
        }
    }
    
    // MARK: - OpenAI Compatible (Groq / OpenAI)
    
    private func callOpenAICompatibleAPI(
        endpoint: String,
        model: String,
        apiKey: String,
        text: String,
        style: WritingStyle,
        completion: @escaping (String?) -> Void
    ) {
        guard let url = URL(string: endpoint) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 9.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let prompt = buildPrompt(text: text, style: style)
        
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a world-class English grammar and writing coach. Output ONLY the improved text without quotes, markdown headers, or explanations. Preserve the original meaning accurately."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.2
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(nil)
            return
        }
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(nil)
                return
            }
            
            let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(cleaned.isEmpty ? nil : cleaned)
        }.resume()
    }
    
    // MARK: - Ollama Local API
    
    private func callOllamaAPI(text: String, style: WritingStyle, completion: @escaping (String?) -> Void) {
        let base = ollamaEndpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(base)/api/chat") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 6.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = buildPrompt(text: text, style: style)
        
        let payload: [String: Any] = [
            "model": ollamaModel,
            "messages": [
                [
                    "role": "system",
                    "content": "You are a world-class English grammar coach. Output ONLY the improved text without commentary or quotes."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "stream": false
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(nil)
            return
        }
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(nil)
                return
            }
            
            let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(cleaned.isEmpty ? nil : cleaned)
        }.resume()
    }
}
