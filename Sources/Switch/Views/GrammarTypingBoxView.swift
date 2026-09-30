import SwiftUI
import AppKit

final class GrammarTypingBoxState: ObservableObject {
    @Published var inputText: String = "" {
        didSet {
            handleInputChanged(oldValue: oldValue, newValue: inputText)
        }
    }
    @Published var polishedText: String = ""
    @Published var selectedStyle: WritingStyle = .formal {
        didSet {
            triggerAIPolish()
        }
    }
    @Published var isAILoading: Bool = false
    @Published var copiedConfirmation: Bool = false
    @Published var apiKeyInput: String = ""
    @Published var isShowingApiKeyDialog: Bool = false
    @Published var correctionsCount: Int = 0
    @Published var changes: [String] = []
    
    private var aiDebounceWorkItem: DispatchWorkItem?
    private var isSelfUpdating: Bool = false
    
    init() {
        self.selectedStyle = GrammarCoachService.shared.currentStyle
    }
    
    private func handleInputChanged(oldValue: String, newValue: String) {
        guard !isSelfUpdating else { return }
        
        // 1. Live inline word auto-correction inside input box on delimiter
        if newValue.count > oldValue.count, let lastChar = newValue.last,
           lastChar == " " || lastChar == "\n" || lastChar == "." || lastChar == "," {
            let prefix = String(newValue.dropLast())
            if let lastWord = prefix.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).last,
               !lastWord.isEmpty,
               let correction = GrammarCoachService.shared.getCorrection(for: lastWord),
               correction != lastWord {
                if let range = prefix.range(of: lastWord, options: .backwards) {
                    var updated = prefix
                    updated.replaceSubrange(range, with: correction)
                    updated.append(lastChar)
                    isSelfUpdating = true
                    DispatchQueue.main.async {
                        self.inputText = updated
                        self.isSelfUpdating = false
                    }
                    return
                }
            }
        }
        
        // 2. Fast instant local polish
        let fastResult = GrammarCoachService.shared.polishText(newValue, style: selectedStyle)
        self.polishedText = fastResult.polished
        self.correctionsCount = fastResult.correctionsCount
        self.changes = fastResult.changes
        
        // 3. Debounced AI polish (LanguageTool Neural / Gemini AI)
        triggerAIPolish()
    }
    
    public func triggerAIPolish() {
        aiDebounceWorkItem?.cancel()
        let textToPolish = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToPolish.isEmpty else {
            polishedText = ""
            correctionsCount = 0
            changes = []
            isAILoading = false
            return
        }
        
        let style = selectedStyle
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async { self.isAILoading = true }
            GrammarCoachService.shared.polishTextWithAI(textToPolish, style: style) { [weak self] polished, count, changes in
                DispatchQueue.main.async {
                    guard let self = self,
                          self.inputText.trimmingCharacters(in: .whitespacesAndNewlines) == textToPolish else { return }
                    self.polishedText = polished
                    self.correctionsCount = max(count, changes.count)
                    self.changes = changes
                    self.isAILoading = false
                }
            }
        }
        aiDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }
    
    public func fixAllInInput() {
        let fixed = GrammarCoachService.shared.polishText(inputText, style: selectedStyle).polished
        isSelfUpdating = true
        inputText = fixed
        isSelfUpdating = false
        triggerAIPolish()
    }
}

public struct GrammarTypingBoxView: View {
    @ObservedObject private var coach = GrammarCoachService.shared
    @ObservedObject private var aiService = GrammarAIService.shared
    @StateObject private var state = GrammarTypingBoxState()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header Bar
            HStack(spacing: 10) {
                // Glowing Coach Badge
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: state.selectedStyle == .formal
                                    ? [Color(red: 0.25, green: 0.65, blue: 0.95), Color(red: 0.15, green: 0.45, blue: 0.85)]
                                    : [Color(red: 0.95, green: 0.65, blue: 0.25), Color(red: 0.90, green: 0.45, blue: 0.20)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                        .shadow(
                            color: (state.selectedStyle == .formal ? Color.blue : Color.orange).opacity(0.4),
                            radius: 6,
                            x: 0,
                            y: 2
                        )
                    
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("English Grammar Coach")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(aiService.hasGeminiKey ? "✨ Gemini AI" : "🤖 Neural AI")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(aiService.hasGeminiKey ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color(red: 0.28, green: 0.76, blue: 0.52))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill((aiService.hasGeminiKey ? Color.blue : Color.green).opacity(0.18))
                            )
                    }
                    
                    Text("Auto-corrects words as you type · AI Sentence Rewriting & Tone")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.65))
                }
                
                Spacer()
                
                // AI Settings Button
                Button(action: {
                    state.apiKeyInput = aiService.geminiApiKey
                    state.isShowingApiKeyDialog.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text(aiService.hasGeminiKey ? "AI Key Configured" : "Add AI Key")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(aiService.hasGeminiKey ? Color(red: 0.38, green: 0.75, blue: 0.98) : .white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $state.isShowingApiKeyDialog) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(Color(red: 0.38, green: 0.75, blue: 0.98))
                            Text("Google Gemini AI Key")
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                        }
                        
                        Text("Enter a free Gemini API key for deep LLM sentence rewriting. If left blank, the built-in Neural Grammar Engine is used.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        SecureField("AIzaSy...", text: $state.apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Button("Get Free Key") {
                                if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.system(size: 11))
                            
                            Spacer()
                            
                            if !aiService.geminiApiKey.isEmpty {
                                Button("Remove") {
                                    aiService.geminiApiKey = ""
                                    state.apiKeyInput = ""
                                    state.isShowingApiKeyDialog = false
                                }
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                            }
                            
                            Button("Save Key") {
                                aiService.geminiApiKey = state.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                state.isShowingApiKeyDialog = false
                                state.triggerAIPolish()
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14)
                    .frame(width: 320)
                }
                
                // Close Button
                Button(action: {
                    coach.hideTypingBox()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            
            // Accessibility Warning Banner (If permission not yet granted)
            if !coach.isAccessibilityGranted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    
                    Text("Accessibility permission is needed for live auto-correction in other apps.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                    
                    Spacer()
                    
                    Button("Grant in Settings") {
                        coach.openAccessibilitySettings()
                    }
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.2)))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }
            
            // Writing Style Toggle Pill
            HStack(spacing: 8) {
                ForEach(WritingStyle.allCases) { style in
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            state.selectedStyle = style
                            coach.currentStyle = style
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: style.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(style == .formal ? "Formal Writing" : "Casual Writing")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundColor(state.selectedStyle == style ? .white : .white.opacity(0.65))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            ZStack {
                                if state.selectedStyle == style {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            style == .formal
                                                ? Color(red: 0.20, green: 0.50, blue: 0.85)
                                                : Color(red: 0.85, green: 0.50, blue: 0.18)
                                        )
                                        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.06))
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Text(state.selectedStyle.description)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            
            // Input Text Box
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Original Typing")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    // Auto-fix Input Button
                    if !state.inputText.isEmpty {
                        Button(action: {
                            state.fixAllInInput()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 10))
                                Text("Fix Words")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color(red: 0.38, green: 0.75, blue: 0.98))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .help("Auto-correct words in input box")
                    }
                    
                    // Paste Button
                    Button(action: {
                        if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                            state.inputText = pasted
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 10))
                            Text("Paste")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Paste from clipboard (⌘V)")
                    
                    if !state.inputText.isEmpty {
                        Button("Clear") {
                            state.inputText = ""
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .buttonStyle(.plain)
                    }
                }
                
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                    
                    if state.inputText.isEmpty {
                        Text("Type or paste any English text here...\n(Words auto-correct on space · Full sentences polish with AI)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $state.inputText)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 85, maxHeight: 110)
                }
            }
            
            // Live Polished Box
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(state.selectedStyle == .formal ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color(red: 0.95, green: 0.65, blue: 0.25))
                        Text("Polished for \(state.selectedStyle.rawValue) Communication")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    if state.isAILoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                        Text("AI Polishing...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    if state.correctionsCount > 0 {
                        Text("✨ \(state.correctionsCount) improvements")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.28, green: 0.76, blue: 0.52).opacity(0.15)))
                    }
                    
                    if !state.polishedText.isEmpty && !state.inputText.isEmpty {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.declareTypes([.string], owner: nil)
                            NSPasteboard.general.setString(state.polishedText, forType: .string)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.copiedConfirmation = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation {
                                    state.copiedConfirmation = false
                                }
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: state.copiedConfirmation ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                Text(state.copiedConfirmation ? "Copied" : "Copy")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .help("Copy polished text (⌘C)")
                    }
                }
                
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            state.selectedStyle == .formal
                                ? Color(red: 0.10, green: 0.16, blue: 0.26).opacity(0.7)
                                : Color(red: 0.20, green: 0.16, blue: 0.10).opacity(0.7)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    state.selectedStyle == .formal
                                        ? Color(red: 0.25, green: 0.65, blue: 0.95).opacity(0.3)
                                        : Color(red: 0.95, green: 0.65, blue: 0.25).opacity(0.3),
                                    lineWidth: 0.8
                                )
                        )
                    
                    ScrollView {
                        Text(state.inputText.isEmpty ? "Your polished text will automatically appear here with perfect AI grammar, spelling, and phrasing..." : (state.polishedText.isEmpty ? state.inputText : state.polishedText))
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(state.inputText.isEmpty ? .white.opacity(0.3) : .white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(minHeight: 85, maxHeight: 110)
                }
            }
            
            // Footer Action Bar
            HStack(spacing: 12) {
                // Copy Polished Button
                Button(action: {
                    let textToCopy = state.polishedText.isEmpty ? state.inputText : state.polishedText
                    guard !textToCopy.isEmpty else { return }
                    
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.declareTypes([.string], owner: nil)
                    NSPasteboard.general.setString(textToCopy, forType: .string)
                    
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.copiedConfirmation = true
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation {
                            state.copiedConfirmation = false
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: state.copiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.system(size: 12))
                        Text(state.copiedConfirmation ? "Copied to Clipboard!" : "Copy Polished Text")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(
                                state.copiedConfirmation
                                    ? Color(red: 0.28, green: 0.76, blue: 0.52)
                                    : (state.selectedStyle == .formal
                                        ? Color(red: 0.20, green: 0.50, blue: 0.85)
                                        : Color(red: 0.85, green: 0.50, blue: 0.18))
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(state.inputText.isEmpty)
                .opacity(state.inputText.isEmpty ? 0.5 : 1.0)
                
                // Replace in Previous App
                Button(action: {
                    let textToInsert = state.polishedText.isEmpty ? state.inputText : state.polishedText
                    coach.pasteIntoPreviousApp(text: textToInsert)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.forward.circle.fill")
                            .font(.system(size: 12))
                        Text("Paste in App")
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .disabled(state.inputText.isEmpty)
                .opacity(state.inputText.isEmpty ? 0.5 : 1.0)
                .help("Copies and automatically pastes into your active app")
            }
        }
        .padding(18)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                )
        )
        .frame(width: 550, height: 465)
    }
}
