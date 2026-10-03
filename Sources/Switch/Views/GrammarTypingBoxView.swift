import SwiftUI
import AppKit

final class GrammarTypingBoxState: ObservableObject {
    @Published var inputText: String = "" {
        didSet {
            handleInputChanged()
        }
    }
    @Published var originalText: String = ""
    @Published var selectedStyle: WritingStyle = .fixOnly
    @Published var autoCorrectAsYouType: Bool = true
    @Published var appliedFixes: [String] = []
    @Published var lastFixCount: Int = 0
    @Published var isAILoading: Bool = false
    @Published var copiedConfirmation: Bool = false
    @Published var isShowingSettings: Bool = false
    
    // API Key inputs for settings
    @Published var geminiKeyInput: String = ""
    @Published var groqKeyInput: String = ""
    @Published var openAIKeyInput: String = ""
    @Published var ollamaEndpointInput: String = ""
    @Published var ollamaModelInput: String = ""
    
    private var autoCorrectDebounceWorkItem: DispatchWorkItem?
    private var isProgrammaticUpdate: Bool = false
    
    init() {
        self.selectedStyle = GrammarCoachService.shared.currentStyle
        self.geminiKeyInput = GrammarAIService.shared.geminiApiKey
        self.groqKeyInput = GrammarAIService.shared.groqApiKey
        self.openAIKeyInput = GrammarAIService.shared.openaiApiKey
        self.ollamaEndpointInput = GrammarAIService.shared.ollamaEndpoint
        self.ollamaModelInput = GrammarAIService.shared.ollamaModel
    }
    
    public var wordCount: Int {
        inputText.split { $0.isWhitespace || $0.isNewline }.count
    }
    
    public var charCount: Int {
        inputText.count
    }
    
    public var readingTimeFormatted: String {
        let mins = max(0.1, Double(wordCount) / 200.0)
        return String(format: "%.1f min", mins)
    }
    
    private func handleInputChanged() {
        guard !isProgrammaticUpdate else { return }
        
        autoCorrectDebounceWorkItem?.cancel()
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            appliedFixes = []
            lastFixCount = 0
            isAILoading = false
            return
        }
        
        if originalText.isEmpty && !trimmed.isEmpty {
            originalText = inputText
        }
        
        guard autoCorrectAsYouType else { return }
        
        // Trigger auto-correct if terminal punctuation was entered or upon pause (750ms)
        let lastChar = inputText.last
        let isAtSentenceEnd = lastChar == "\n" || (inputText.count >= 2 && inputText.suffix(2) == ". ")
        let delay: Double = isAtSentenceEnd ? 0.2 : 0.8
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.executeAutoCorrect(notifyUser: false)
        }
        autoCorrectDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    public func executeAutoCorrect(notifyUser: Bool = true) {
        let textToCorrect = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToCorrect.isEmpty else { return }
        
        if originalText.isEmpty {
            originalText = textToCorrect
        }
        
        let (corrected, fixes) = GrammarCoachService.shared.autoCorrectText(textToCorrect, style: selectedStyle)
        
        if corrected != textToCorrect {
            isProgrammaticUpdate = true
            inputText = corrected
            isProgrammaticUpdate = false
            
            appliedFixes = fixes
            lastFixCount = fixes.count
            
            if notifyUser {
                NSSound(named: "Tink")?.play()
            }
        } else if notifyUser {
            appliedFixes = []
            lastFixCount = 0
        }
    }
    
    public func pasteAndCorrect() {
        if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
            originalText = str
            let (corrected, fixes) = GrammarCoachService.shared.autoCorrectText(str, style: selectedStyle)
            isProgrammaticUpdate = true
            inputText = corrected
            isProgrammaticUpdate = false
            appliedFixes = fixes
            lastFixCount = fixes.count
            NSSound(named: "Tink")?.play()
        }
    }
    
    public func revertToOriginal() {
        guard !originalText.isEmpty else { return }
        isProgrammaticUpdate = true
        inputText = originalText
        isProgrammaticUpdate = false
        appliedFixes = []
        lastFixCount = 0
    }
    
    public func triggerAIPolish(style: WritingStyle) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        if originalText.isEmpty {
            originalText = text
        }
        
        self.selectedStyle = style
        self.isAILoading = true
        
        GrammarCoachService.shared.polishTextWithAI(text, style: style) { [weak self] polished, _, changes in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAILoading = false
                self.isProgrammaticUpdate = true
                self.inputText = polished
                self.isProgrammaticUpdate = false
                self.appliedFixes = changes
                self.lastFixCount = changes.count
                NSSound(named: "Tink")?.play()
            }
        }
    }
    
    public func copyToClipboard() {
        guard !inputText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(inputText, forType: .string)
        
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation {
                self.copiedConfirmation = false
            }
        }
    }
    
    public func saveSettings() {
        let ai = GrammarAIService.shared
        ai.geminiApiKey = geminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.groqApiKey = groqKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.openaiApiKey = openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.ollamaEndpoint = ollamaEndpointInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ai.ollamaModel = ollamaModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isShowingSettings = false
    }
}

public struct GrammarTypingBoxView: View {
    @ObservedObject private var coach = GrammarCoachService.shared
    @ObservedObject private var aiService = GrammarAIService.shared
    @StateObject private var state = GrammarTypingBoxState()
    
    public init() {}
    
    public var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                headerBar
                toolbarModeBar
                editorArea
                footerBar
            }
            .padding(16)
        }
        .frame(minWidth: 640, minHeight: 440)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.isShowingSettings) {
            aiSettingsSheet
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.18, green: 0.76, blue: 0.52), Color(red: 0.10, green: 0.55, blue: 0.38)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .shadow(color: Color.green.opacity(0.3), radius: 5, x: 0, y: 2)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Grammar Coach & Auto-Corrector")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // Engine Picker Menu
                    Menu {
                        Section("Active AI / Grammar Engine") {
                            ForEach(AIEngine.allCases) { engine in
                                Button(action: {
                                    aiService.selectedEngine = engine
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
                                .font(.system(size: 9.5))
                            Text(aiService.selectedEngine.shortName)
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7.5))
                                .opacity(0.7)
                        }
                        .foregroundColor(Color(red: 0.38, green: 0.75, blue: 0.98))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.blue.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 0.8)
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                
                Text("Direct auto-correction: typos, punctuation, commas & style without manual acceptance")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
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
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
    }
    
    // MARK: - Toolbar Mode Bar
    
    private var toolbarModeBar: some View {
        HStack(spacing: 6) {
            ForEach(WritingStyle.allCases) { style in
                Button(action: {
                    state.selectedStyle = style
                    state.triggerAIPolish(style: style)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: style.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(style.badge)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(state.selectedStyle == style ? .white : .white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(state.selectedStyle == style ? Color.blue.opacity(0.35) : Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(state.selectedStyle == style ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(state.isAILoading)
            }
            
            Spacer()
            
            // Auto-Correct As You Type Switch
            Toggle(isOn: $state.autoCorrectAsYouType) {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(state.autoCorrectAsYouType ? Color.yellow : .secondary)
                    Text("Auto-Correct As You Type")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(state.autoCorrectAsYouType ? .white : .white.opacity(0.5))
                }
            }
            .toggleStyle(.switch)
            .scaleEffect(0.8)
        }
    }
    
    // MARK: - Main Editor Area
    
    private var editorArea: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                
                if state.inputText.isEmpty {
                    Text("Type or paste your text here...\n\nSwitch automatically corrects spelling mistakes, missing commas, punctuation marks, contractions, and capitalization directly in place — no manual accepting needed.")
                        .font(.system(size: 13.5, weight: .regular))
                        .foregroundColor(.white.opacity(0.28))
                        .padding(14)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $state.inputText)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Text Editor Metadata Bar
            HStack(spacing: 12) {
                if state.charCount > 0 {
                    Text("\(state.wordCount) words")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Text("·")
                        .foregroundColor(.white.opacity(0.3))
                    Text("\(state.charCount) characters")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Text("·")
                        .foregroundColor(.white.opacity(0.3))
                    Text("\(state.readingTimeFormatted) read")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // Paste & Correct Button
                Button(action: {
                    state.pasteAndCorrect()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                        Text("Paste & Correct")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.09)))
                }
                .buttonStyle(.plain)
                
                // Clear Button
                if !state.inputText.isEmpty {
                    Button("Clear") {
                        state.inputText = ""
                        state.originalText = ""
                        state.appliedFixes = []
                        state.lastFixCount = 0
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Footer Bar
    
    private var footerBar: some View {
        HStack(spacing: 10) {
            // Live Status Pill
            if state.isAILoading {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                    Text("Refining with \(aiService.selectedEngine.shortName)...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            } else if state.lastFixCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(Color.green)
                        .font(.system(size: 11.5))
                    Text("Auto-corrected \(state.lastFixCount) issues (spelling, commas, punctuation)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.green.opacity(0.95))
                    
                    if !state.originalText.isEmpty && state.originalText != state.inputText {
                        Button(action: {
                            state.revertToOriginal()
                        }) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 9))
                                Text("Revert")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .help("Restore your original unedited text")
                    }
                }
            } else if !state.inputText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.green)
                        .font(.system(size: 11))
                    Text("All clear! Flawless grammar and punctuation")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.green.opacity(0.85))
                }
            }
            
            Spacer()
            
            // Auto-Correct Now Button (Manual trigger or Cmd+Return)
            Button(action: {
                state.executeAutoCorrect(notifyUser: true)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Auto-Correct Now")
                        .font(.system(size: 11.5, weight: .bold))
                    Text("⌘⏎")
                        .font(.system(size: 9.5, weight: .regular))
                        .opacity(0.7)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.18, green: 0.76, blue: 0.52), Color(red: 0.10, green: 0.55, blue: 0.38)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: Color.green.opacity(0.25), radius: 3, x: 0, y: 1)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(state.inputText.isEmpty || state.isAILoading)
            .help("Immediately fix all spelling, commas, and punctuation marks (⌘⏎)")
            
            // Copy Button
            Button(action: {
                state.copyToClipboard()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: state.copiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(.system(size: 11))
                    Text(state.copiedConfirmation ? "Copied!" : "Copy")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(state.inputText.isEmpty)
            
            // Paste in App Button
            Button(action: {
                coach.pasteIntoPreviousApp(text: state.inputText)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                        .font(.system(size: 11))
                    Text("Paste in App")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(state.inputText.isEmpty)
            .help("Paste directly into your active document or chat")
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
                VStack(alignment: .leading, spacing: 14) {
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
                        Text("Free API keys from Google AI Studio. Excellent reasoning and natural tone rewriting.")
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
                        Text("World's fastest inference platform with open-source Llama 3.3.")
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
                        Text("Runs on your Mac GPU with zero network requests.")
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
