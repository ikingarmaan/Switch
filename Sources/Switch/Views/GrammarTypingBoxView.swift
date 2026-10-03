import SwiftUI
import AppKit

final class GrammarTypingBoxState: ObservableObject {
    @Published var inputText: String = "" {
        didSet {
            handleInputChanged()
        }
    }
    @Published var selectedStyle: WritingStyle = .fixOnly
    @Published var selectedFilter: GrammarCategory? = nil
    @Published var issues: [GrammarIssue] = []
    @Published var overallScore: Int = 100
    @Published var isAILoading: Bool = false
    @Published var copiedConfirmation: Bool = false
    @Published var isShowingSettings: Bool = false
    
    // API Key inputs for settings
    @Published var geminiKeyInput: String = ""
    @Published var groqKeyInput: String = ""
    @Published var openAIKeyInput: String = ""
    @Published var ollamaEndpointInput: String = ""
    @Published var ollamaModelInput: String = ""
    
    private var scanDebounceWorkItem: DispatchWorkItem?
    
    init() {
        self.selectedStyle = GrammarCoachService.shared.currentStyle
        self.geminiKeyInput = GrammarAIService.shared.geminiApiKey
        self.groqKeyInput = GrammarAIService.shared.groqApiKey
        self.openAIKeyInput = GrammarAIService.shared.openaiApiKey
        self.ollamaEndpointInput = GrammarAIService.shared.ollamaEndpoint
        self.ollamaModelInput = GrammarAIService.shared.ollamaModel
    }
    
    public var activeIssues: [GrammarIssue] {
        issues.filter { !$0.isDismissed && !$0.isApplied }
    }
    
    public var filteredIssues: [GrammarIssue] {
        if let cat = selectedFilter {
            return activeIssues.filter { $0.category == cat }
        }
        return activeIssues
    }
    
    public var correctnessCount: Int {
        activeIssues.filter { $0.category == .correctness }.count
    }
    
    public var clarityCount: Int {
        activeIssues.filter { $0.category == .clarity }.count
    }
    
    public var engagementCount: Int {
        activeIssues.filter { $0.category == .engagement }.count
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
        scanDebounceWorkItem?.cancel()
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            issues = []
            overallScore = 100
            isAILoading = false
            return
        }
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let text = self.inputText
            let scanned = GrammarCoachService.shared.scanIssues(in: text)
            let score = GrammarCoachService.shared.calculateScore(text: text, issues: scanned)
            
            DispatchQueue.main.async {
                guard self.inputText == text else { return }
                self.issues = scanned
                self.overallScore = score
            }
        }
        scanDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
    
    // MARK: - Actions
    
    public func acceptIssue(_ issue: GrammarIssue) {
        let updated = GrammarCoachService.shared.applyIssue(issue, to: inputText)
        inputText = updated
    }
    
    public func dismissIssue(_ issue: GrammarIssue) {
        if let idx = issues.firstIndex(where: { $0.id == issue.id }) {
            issues[idx].isDismissed = true
            overallScore = GrammarCoachService.shared.calculateScore(text: inputText, issues: activeIssues)
        }
    }
    
    public func acceptAllIssues() {
        guard !activeIssues.isEmpty else { return }
        let updated = GrammarCoachService.shared.applyAllIssues(activeIssues, to: inputText)
        inputText = updated
    }
    
    public func triggerAIPolish(style: WritingStyle) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        self.selectedStyle = style
        self.isAILoading = true
        
        GrammarCoachService.shared.polishTextWithAI(text, style: style) { [weak self] polished, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAILoading = false
                self.inputText = polished
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
            
            HStack(spacing: 0) {
                // Left Column: Main Editor & GrammarlyGO Actions
                VStack(spacing: 12) {
                    headerBar
                    grammarlyGoActionBar
                    editorArea
                    footerBar
                }
                .padding(16)
                
                // Vertical Divider
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
                    .ignoresSafeArea()
                
                // Right Column: Grammarly Suggestion Cards Deck
                sidebarCardsDeck
                    .frame(width: 290)
            }
        }
        .frame(minWidth: 840, minHeight: 540)
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
                    .frame(width: 32, height: 32)
                    .shadow(color: Color.green.opacity(0.3), radius: 5, x: 0, y: 2)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Grammarly Writing Assistant")
                        .font(.system(size: 14.5, weight: .bold, design: .rounded))
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
                
                Text("Real-time grammar, spelling, clarity & AI rewrites")
                    .font(.system(size: 11, weight: .regular))
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
    
    // MARK: - GrammarlyGO Actions Bar
    
    private var grammarlyGoActionBar: some View {
        HStack(spacing: 6) {
            ForEach(WritingStyle.allCases) { style in
                Button(action: {
                    state.triggerAIPolish(style: style)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: style.icon)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(style.badge)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(state.selectedStyle == style ? .white : .white.opacity(0.75))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
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
                .disabled(state.inputText.isEmpty || state.isAILoading)
            }
            Spacer()
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
                    Text("Type or paste your text here...\n\nSwitch checks your grammar in real-time, highlights spelling errors, wordy phrases, and suggests 1-click improvements just like Grammarly.")
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
                
                // Paste Button
                Button(action: {
                    if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
                        state.inputText = str
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                        Text("Paste")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                
                // Clear Button
                if !state.inputText.isEmpty {
                    Button("Clear") {
                        state.inputText = ""
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
            } else if state.activeIssues.isEmpty && !state.inputText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.green)
                        .font(.system(size: 11))
                    Text("Flawless! No issues found")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.green.opacity(0.9))
                }
            } else if !state.activeIssues.isEmpty {
                Text("\(state.activeIssues.count) suggestions ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Accept All Button
            if !state.activeIssues.isEmpty {
                Button(action: {
                    state.acceptAllIssues()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Accept All (\(state.activeIssues.count))")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.18, green: 0.76, blue: 0.52), Color(red: 0.10, green: 0.55, blue: 0.38)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .shadow(color: Color.green.opacity(0.25), radius: 4, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Copy Button
            Button(action: {
                state.copyToClipboard()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: state.copiedConfirmation ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(.system(size: 11))
                    Text(state.copiedConfirmation ? "Copied!" : "Copy")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.12)))
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
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(state.inputText.isEmpty)
            .help("Paste directly into your active document or chat")
        }
    }
    
    // MARK: - Sidebar Cards Deck
    
    private var sidebarCardsDeck: some View {
        VStack(spacing: 12) {
            // Overall Score Card
            scoreHeaderCard
            
            // Category Filter Pills
            categoryFilterPills
            
            // Cards List
            cardsScrollView
        }
        .padding(14)
        .background(Color.black.opacity(0.25))
    }
    
    // MARK: - Score Header Card
    
    private var scoreHeaderCard: some View {
        HStack(spacing: 12) {
            // Circular Score Gauge
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 4)
                    .frame(width: 44, height: 44)
                
                Circle()
                    .trim(from: 0, to: CGFloat(state.overallScore) / 100.0)
                    .stroke(
                        state.overallScore >= 90
                            ? Color(red: 0.28, green: 0.76, blue: 0.52)
                            : (state.overallScore >= 70 ? Color(red: 0.95, green: 0.72, blue: 0.20) : Color(red: 0.95, green: 0.35, blue: 0.35)),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                
                Text("\(state.overallScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    state.overallScore >= 95
                        ? "Flawless Quality"
                        : (state.overallScore >= 80 ? "Good Quality" : "Needs Review")
                )
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                
                Text(
                    state.activeIssues.isEmpty
                        ? (state.inputText.isEmpty ? "Enter text to check" : "Zero errors detected")
                        : "\(state.activeIssues.count) suggestions found"
                )
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Category Filter Pills
    
    private var categoryFilterPills: some View {
        HStack(spacing: 5) {
            // All Pill
            Button(action: {
                state.selectedFilter = nil
            }) {
                Text("All (\(state.activeIssues.count))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(state.selectedFilter == nil ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(state.selectedFilter == nil ? Color.blue.opacity(0.3) : Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            
            if state.correctnessCount > 0 {
                Button(action: {
                    state.selectedFilter = .correctness
                }) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(GrammarCategory.correctness.color)
                            .frame(width: 6, height: 6)
                        Text("\(state.correctnessCount)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(state.selectedFilter == .correctness ? .white : .white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(state.selectedFilter == .correctness ? GrammarCategory.correctness.color.opacity(0.3) : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            
            if state.clarityCount > 0 {
                Button(action: {
                    state.selectedFilter = .clarity
                }) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(GrammarCategory.clarity.color)
                            .frame(width: 6, height: 6)
                        Text("\(state.clarityCount)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(state.selectedFilter == .clarity ? .white : .white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(state.selectedFilter == .clarity ? GrammarCategory.clarity.color.opacity(0.3) : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Cards ScrollView
    
    private var cardsScrollView: some View {
        ScrollView {
            VStack(spacing: 10) {
                if state.filteredIssues.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                            .padding(.top, 40)
                        
                        Text(state.inputText.isEmpty ? "No text entered" : "All Clear!")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(state.inputText.isEmpty ? "Start typing to receive real-time grammar and clarity suggestions." : "Your writing is clear, polished, and error-free.")
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(state.filteredIssues) { issue in
                        issueCard(issue)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Single Issue Card
    
    private func issueCard(_ issue: GrammarIssue) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: issue.category.icon)
                        .font(.system(size: 9.5))
                        .foregroundColor(issue.category.color)
                    Text(issue.category.rawValue)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(issue.category.color)
                }
                
                Spacer()
                
                // Dismiss Button
                Button(action: {
                    state.dismissIssue(issue)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Dismiss suggestion")
            }
            
            // Correction Comparison
            HStack(spacing: 6) {
                Text(issue.original)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(Color.red.opacity(0.85))
                    .strikethrough(true, color: Color.red.opacity(0.85))
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.4))
                
                Text(issue.replacement)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.28, green: 0.85, blue: 0.52))
            }
            
            // Reason
            Text(issue.reason)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(2)
            
            // Accept Button
            Button(action: {
                state.acceptIssue(issue)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Accept: \"\(issue.replacement)\"")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(issue.category.color.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(issue.category.color.opacity(0.6), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                )
        )
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
