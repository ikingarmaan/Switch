import SwiftUI
import AppKit

final class GrammarTypingBoxState: ObservableObject {
    @Published var inputText: String = "" {
        didSet {
            handleInputChanged()
        }
    }
    @Published var polishedText: String = ""
    @Published var selectedStyle: WritingStyle = .fixOnly {
        didSet {
            triggerAIPolish()
        }
    }
    @Published var isAILoading: Bool = false
    @Published var copiedConfirmation: Bool = false
    @Published var isShowingSettings: Bool = false
    @Published var correctionsCount: Int = 0
    @Published var changes: [String] = []
    @Published var showDiff: Bool = false
    @Published var isSideBySide: Bool = true
    
    // API Key inputs for settings
    @Published var geminiKeyInput: String = ""
    @Published var groqKeyInput: String = ""
    @Published var openAIKeyInput: String = ""
    @Published var ollamaEndpointInput: String = ""
    @Published var ollamaModelInput: String = ""
    
    private var aiDebounceWorkItem: DispatchWorkItem?
    
    init() {
        self.selectedStyle = GrammarCoachService.shared.currentStyle
        self.geminiKeyInput = GrammarAIService.shared.geminiApiKey
        self.groqKeyInput = GrammarAIService.shared.groqApiKey
        self.openAIKeyInput = GrammarAIService.shared.openaiApiKey
        self.ollamaEndpointInput = GrammarAIService.shared.ollamaEndpoint
        self.ollamaModelInput = GrammarAIService.shared.ollamaModel
    }
    
    private func handleInputChanged() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            polishedText = ""
            correctionsCount = 0
            changes = []
            isAILoading = false
            aiDebounceWorkItem?.cancel()
            return
        }
        
        // Fast instant local preview using native engine
        let fast = GrammarCoachService.shared.polishNative(inputText, style: selectedStyle)
        self.polishedText = fast.polished
        self.correctionsCount = fast.correctionsCount
        self.changes = fast.changes
        
        // Debounce LLM query (400ms)
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
    
    public func saveSettings() {
        let ai = GrammarAIService.shared
        ai.geminiApiKey = geminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.groqApiKey = groqKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.openaiApiKey = openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.ollamaEndpoint = ollamaEndpointInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.ollamaModel = ollamaModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isShowingSettings = false
        triggerAIPolish()
    }
    
    public func copyToClipboard() {
        let text = polishedText.isEmpty ? inputText : polishedText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(text, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation {
                self.copiedConfirmation = false
            }
        }
    }
    
    public func replaceInputWithPolished() {
        guard !polishedText.isEmpty else { return }
        inputText = polishedText
    }
}

public struct GrammarTypingBoxView: View {
    @ObservedObject private var coach = GrammarCoachService.shared
    @ObservedObject private var aiService = GrammarAIService.shared
    @StateObject private var state = GrammarTypingBoxState()
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Dark glassmorphic background
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                // Header Bar
                headerView
                
                // Style Selector Tabs
                styleTabsView
                
                // Main Comparison Editor
                editorComparisonView
                
                // Footer Bar
                footerActionBar
            }
            .padding(16)
        }
        .frame(minWidth: 620, minHeight: 480)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.isShowingSettings) {
            aiSettingsSheet
        }
    }
    
    // MARK: - Header Bar
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Icon Badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.60, blue: 1.0), Color(red: 0.10, green: 0.35, blue: 0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .shadow(color: Color.blue.opacity(0.35), radius: 6, x: 0, y: 2)
                
                Image(systemName: "character.cursor.ibeam")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Grammar & Writing Coach")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // Engine Picker Menu
                    Menu {
                        Section("Active AI / Grammar Engine") {
                            ForEach(AIEngine.allCases) { engine in
                                Button(action: {
                                    aiService.selectedEngine = engine
                                    state.triggerAIPolish()
                                }) {
                                    HStack {
                                        Text(engine.title)
                                        if aiService.selectedEngine == engine {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            state.isShowingSettings = true
                        }) {
                            HStack {
                                Text("Configure API Keys & Models...")
                                Image(systemName: "gearshape")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: aiService.selectedEngine.icon)
                                .font(.system(size: 10))
                            Text(aiService.selectedEngine.shortName)
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .opacity(0.7)
                        }
                        .foregroundColor(Color(red: 0.38, green: 0.75, blue: 0.98))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 0.8)
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                
                Text(state.selectedStyle.description)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
            }
            
            Spacer()
            
            // View Mode Toggle (Side-by-Side vs Stacked)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.isSideBySide.toggle()
                }
            }) {
                Image(systemName: state.isSideBySide ? "rectangle.split.2x1" : "rectangle.split.1x2")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(state.isSideBySide ? "Switch to Stacked View" : "Switch to Side-by-Side View")
            
            // Settings Button
            Button(action: {
                state.isShowingSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Configure AI Models & Keys")
            
            // Close Button
            Button(action: {
                coach.hideTypingBox()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
    }
    
    // MARK: - Style Selector Tabs
    
    private var styleTabsView: some View {
        HStack(spacing: 6) {
            ForEach(WritingStyle.allCases) { style in
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        state.selectedStyle = style
                        coach.currentStyle = style
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: style.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(style.badge)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(state.selectedStyle == style ? .white : .white.opacity(0.65))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            if state.selectedStyle == style {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.25, green: 0.55, blue: 0.95), Color(red: 0.15, green: 0.40, blue: 0.85)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 1)
                            } else {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color.white.opacity(0.06))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
    
    // MARK: - Editor Comparison View
    
    private var editorComparisonView: some View {
        Group {
            if state.isSideBySide {
                HStack(spacing: 12) {
                    inputBoxView
                    outputBoxView
                }
            } else {
                VStack(spacing: 12) {
                    inputBoxView
                    outputBoxView
                }
            }
        }
    }
    
    // MARK: - Input Box View
    
    private var inputBoxView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Original Text")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                let wordCount = state.inputText.split { $0.isWhitespace || $0.isNewline }.count
                let charCount = state.inputText.count
                if charCount > 0 {
                    Text("\(wordCount) words · \(charCount) chars")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                // Paste
                Button(action: {
                    if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
                        state.inputText = str
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                        Text("Paste")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                // Clear
                if !state.inputText.isEmpty {
                    Button("Clear") {
                        state.inputText = ""
                    }
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.5))
                    .buttonStyle(.plain)
                }
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.black.opacity(0.32))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                
                if state.inputText.isEmpty {
                    Text("Type or paste any English text here...\n\nSwitch will automatically detect and fix spelling, punctuation, grammar, and phrasing using \(aiService.selectedEngine.title).")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.28))
                        .padding(12)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $state.inputText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Output Box View
    
    private var outputBoxView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.38, green: 0.75, blue: 0.98))
                    Text("Improved (\(state.selectedStyle.badge))")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                if state.isAILoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                    Text("AI Polishing...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                } else if state.correctionsCount > 0 {
                    Text("✨ \(state.correctionsCount) improvements")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.15)))
                }
                
                Spacer()
                
                if !state.polishedText.isEmpty {
                    // Diff toggle
                    Button(action: {
                        state.showDiff.toggle()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: state.showDiff ? "eye.fill" : "eye")
                                .font(.system(size: 10))
                            Text(state.showDiff ? "Text" : "Diff")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(state.showDiff ? Color.blue : .white.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    
                    // Copy
                    Button(action: {
                        state.copyToClipboard()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: state.copiedConfirmation ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(state.copiedConfirmation ? "Copied" : "Copy")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundColor(state.copiedConfirmation ? Color.green : .white.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(red: 0.10, green: 0.14, blue: 0.22).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(
                                state.isAILoading
                                    ? Color(red: 0.38, green: 0.75, blue: 0.98).opacity(0.5)
                                    : Color(red: 0.20, green: 0.35, blue: 0.55).opacity(0.35),
                                lineWidth: 0.8
                            )
                    )
                
                if state.inputText.isEmpty {
                    Text("Your improved text will appear here automatically...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.25))
                        .padding(12)
                        .allowsHitTesting(false)
                } else if state.showDiff && !state.polishedText.isEmpty {
                    diffHighlightView
                        .padding(10)
                } else {
                    ScrollView {
                        Text(state.polishedText.isEmpty ? state.inputText : state.polishedText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Diff Highlighter
    
    private var diffHighlightView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Changes made:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                
                if state.changes.isEmpty {
                    Text("No errors found. Your text is already grammatically flawless!")
                        .font(.system(size: 12))
                        .foregroundColor(Color.green)
                } else {
                    ForEach(state.changes.prefix(8), id: \.self) { change in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color.green.opacity(0.8))
                                .padding(.top, 2)
                            Text(change)
                                .font(.system(size: 11.5, weight: .regular))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                Text(state.polishedText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Footer Action Bar
    
    private var footerActionBar: some View {
        HStack(spacing: 10) {
            // Engine Status Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(aiService.isAIQuerying ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(aiService.lastEngineUsed)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                if aiService.lastQueryDurationMs > 0 {
                    Text("(\(aiService.lastQueryDurationMs)ms)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            
            Spacer()
            
            // Re-polish Button
            Button(action: {
                state.triggerAIPolish()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                    Text("Polish with AI")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.20, green: 0.50, blue: 0.95), Color(red: 0.12, green: 0.38, blue: 0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(state.inputText.isEmpty || state.isAILoading)
            
            // Copy Polished Text
            Button(action: {
                state.copyToClipboard()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: state.copiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(.system(size: 11))
                    Text(state.copiedConfirmation ? "Copied!" : "Copy Text")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(state.inputText.isEmpty)
            
            // Paste into Previous App
            Button(action: {
                let text = state.polishedText.isEmpty ? state.inputText : state.polishedText
                coach.pasteIntoPreviousApp(text: text)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                        .font(.system(size: 11))
                    Text("Paste in App")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(state.inputText.isEmpty)
            .help("Pasting directly into the active comment box or document")
        }
    }
    
    // MARK: - AI Settings Sheet
    
    private var aiSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(Color.blue)
                Text("AI Engine & Model Settings")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Done") {
                    state.saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            
            Divider().background(Color.white.opacity(0.15))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Google Gemini
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("✨ Google Gemini (Gemini 2.5 / 1.5 Flash)")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button("Get Free Key ↗") {
                                if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.system(size: 11))
                        }
                        Text("Google AI Studio offers 100% free API keys with fast response times and elite grammar reasoning.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        SecureField("AIzaSy...", text: $state.geminiKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    
                    // Groq
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("⚡️ Groq Cloud (Llama 3.3 70B Ultra-Fast)")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button("Get Free Key ↗") {
                                if let url = URL(string: "https://console.groq.com/keys") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.system(size: 11))
                        }
                        Text("World's fastest inference engine. Free tier offers near-instant rewriting with open-source Llama 3.3.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        SecureField("gsk_...", text: $state.groqKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    
                    // OpenAI
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("🧠 OpenAI (GPT-4o-mini)")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button("Get Key ↗") {
                                if let url = URL(string: "https://platform.openai.com/api-keys") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .font(.system(size: 11))
                        }
                        SecureField("sk-...", text: $state.openAIKeyInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    
                    // Ollama
                    VStack(alignment: .leading, spacing: 6) {
                        Text("🦙 Ollama Local (100% Offline & Private)")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Run models directly on your Mac GPU with zero cloud requests.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField("Endpoint", text: $state.ollamaEndpointInput)
                                .textFieldStyle(.roundedBorder)
                            TextField("Model (e.g. llama3)", text: $state.ollamaModelInput)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                }
            }
            .frame(maxHeight: 380)
        }
        .padding(20)
        .frame(width: 520, height: 480)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
