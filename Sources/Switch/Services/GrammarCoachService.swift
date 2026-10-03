import Foundation
import Cocoa
import Carbon
import SwiftUI

public extension Notification.Name {
    static let grammarCoachStateDidChange = Notification.Name("SwitchGrammarCoachStateDidChange")
    static let grammarCoachStyleDidChange = Notification.Name("SwitchGrammarCoachStyleDidChange")
}

public enum WritingStyle: String, CaseIterable, Identifiable, Sendable {
    case fixOnly = "Fix Errors"
    case formal = "Professional"
    case casual = "Friendly"
    case concise = "Concise"
    case elevate = "Elevate"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .fixOnly: return "checkmark.shield.fill"
        case .formal: return "briefcase.fill"
        case .casual: return "bubble.left.and.bubble.right.fill"
        case .concise: return "scissors"
        case .elevate: return "sparkles"
        }
    }
    
    public var badge: String {
        switch self {
        case .fixOnly: return "⚡️ Fix Errors"
        case .formal: return "👔 Professional"
        case .casual: return "💬 Friendly"
        case .concise: return "✂️ Concise"
        case .elevate: return "✨ Elevate"
        }
    }
    
    public var description: String {
        switch self {
        case .fixOnly: return "Fixes typos, spelling, and grammar without altering your original words"
        case .formal: return "Polished, clear, and professional business English"
        case .casual: return "Warm, natural, and friendly conversational tone"
        case .concise: return "Direct and punchy — removes unnecessary filler and fluff"
        case .elevate: return "Articulate, expressive phrasing with rich vocabulary"
        }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

public final class GrammarCoachService: ObservableObject, @unchecked Sendable {
    public static let shared = GrammarCoachService()
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public var currentStyle: WritingStyle = .fixOnly {
        didSet {
            NotificationCenter.default.post(name: .grammarCoachStyleDidChange, object: currentStyle)
        }
    }
    @Published public private(set) var totalCorrectionsCount: Int = 0
    @Published public private(set) var lastCorrectionMessage: String? = nil
    
    // Typing Box Floating Window
    private var typingBoxPanel: NSPanel?
    private var toastPanel: NSPanel?
    private var toastDismissWorkItem: DispatchWorkItem?
    private var previousActiveApp: NSRunningApplication?
    
    // Background keystroke monitor
    private var globalEventMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentWordBuffer: String = ""
    private var isSimulatingKeystrokes: Bool = false
    private var accessibilityPollTimer: Timer?
    
    public var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
    
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // High-confidence typo lookup
    private let commonTypos: [String: String] = [
        "grammer": "grammar",
        "writting": "writing",
        "coatch": "coach",
        "lpng": "long",
        "jot": "not",
        "blutooth": "bluetooth",
        "teh": "the",
        "adn": "and",
        "becuase": "because",
        "recieve": "receive",
        "recieved": "received",
        "seperate": "separate",
        "definately": "definitely",
        "untill": "until",
        "wierd": "weird",
        "alot": "a lot",
        "noone": "no one",
        "thier": "their",
        "truely": "truly",
        "beleive": "believe",
        "occured": "occurred",
        "neccessary": "necessary",
        "conveinent": "convenient",
        "oppurtunity": "opportunity",
        "experiance": "experience",
        "freind": "friend",
        "peice": "piece",
        "calender": "calendar",
        "succesful": "successful",
        "accross": "across",
        "agains": "against",
        "allmost": "almost",
        "amoung": "among",
        "anually": "annually",
        "aparent": "apparent",
        "appearence": "appearance",
        "arguement": "argument",
        "basicly": "basically",
        "begining": "beginning",
        "buisness": "business",
        "collegue": "colleague",
        "comming": "coming",
        "completly": "completely",
        "concious": "conscious",
        "curiousity": "curiosity",
        "dissapear": "disappear",
        "dissappoint": "disappoint",
        "embarass": "embarrass",
        "enviroment": "environment",
        "existance": "existence",
        "familar": "familiar",
        "finaly": "finally",
        "goverment": "government",
        "guarentee": "guarantee",
        "happend": "happened",
        "harrass": "harass",
        "heigt": "height",
        "immediatly": "immediately",
        "independant": "independent",
        "knowlege": "knowledge",
        "liase": "liaise",
        "millenium": "millennium",
        "neice": "niece",
        "noticable": "noticeable",
        "ocassion": "occasion",
        "occurance": "occurrence",
        "posession": "possession",
        "prefered": "preferred",
        "propably": "probably",
        "publically": "publicly",
        "realy": "really",
        "refered": "referred",
        "religous": "religious",
        "rember": "remember",
        "resistence": "resistance",
        "sence": "sense",
        "sieze": "seize",
        "similer": "similar",
        "suprise": "surprise",
        "tendancy": "tendency",
        "tommorrow": "tomorrow",
        "tounge": "tongue",
        "unforseen": "unforeseen",
        "usefull": "useful",
        "vaccum": "vacuum",
        "vehical": "vehicle",
        "visable": "visible",
        "wich": "which",
        "wether": "whether",
        "whould": "would",
        "yesteday": "yesterday"
    ]
    
    // Contractions mapping
    private let formalExpansions: [String: String] = [
        "dont": "do not", "don't": "do not",
        "cant": "cannot", "can't": "cannot",
        "wont": "will not", "won't": "will not",
        "didnt": "did not", "didn't": "did not",
        "isnt": "is not", "isn't": "is not",
        "arent": "are not", "aren't": "are not",
        "wasnt": "was not", "wasn't": "was not",
        "werent": "were not", "weren't": "were not",
        "hasnt": "has not", "hasn't": "has not",
        "havent": "have not", "haven't": "have not",
        "hadnt": "had not", "hadnd't": "had not",
        "wouldnt": "would not", "wouldn't": "would not",
        "shouldnt": "should not", "shouldn't": "should not",
        "couldnt": "could not", "couldn't": "could not",
        "im": "I am", "i'm": "I am",
        "ive": "I have", "i've": "I have",
        "id": "I would", "i'd": "I would",
        "ill": "I will", "i'll": "I will",
        "thats": "that is", "that's": "that is",
        "whats": "what is", "what's": "what is",
        "theres": "there is", "there's": "there is",
        "heres": "here is", "here's": "here is",
        "youre": "you are", "you're": "you are",
        "theyre": "they are", "they're": "they are",
        "weve": "we have", "we've": "we have",
        "youve": "you have", "you've": "you have",
        "doesnt": "does not", "doesn't": "does not"
    ]
    
    private let casualContractions: [String: String] = [
        "do not": "don't",
        "cannot": "can't",
        "will not": "won't",
        "did not": "didn't",
        "is not": "isn't",
        "are not": "aren't",
        "was not": "wasn't",
        "were not": "weren't",
        "has not": "hasn't",
        "have not": "haven't",
        "had not": "hadn't",
        "would not": "wouldn't",
        "should not": "shouldn't",
        "could not": "couldn't",
        "that is": "that's",
        "what is": "what's",
        "there is": "there's",
        "here is": "here's",
        "you are": "you're",
        "they are": "they're",
        "we have": "we've",
        "you have": "you've",
        "i am": "I'm",
        "i have": "I've",
        "i would": "I'd",
        "i will": "I'll",
        "does not": "doesn't"
    ]
    
    private init() {
        setupDistributedNotifications()
    }
    
    private func setupDistributedNotifications() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.armank.switch.grammarCoach.toggle"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggle()
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.armank.switch.grammarCoach.showTypingBox"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showTypingBox()
        }
    }
    
    // MARK: - State Control
    
    public func toggle() {
        setEnabled(!isEnabled)
    }
    
    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        
        if enabled {
            startMonitoring()
            playTickSound()
            showCorrectionToast(title: "Grammar Coach Active", detail: "\(currentStyle.rawValue) Mode")
        } else {
            stopMonitoring()
            hideTypingBox()
        }
        
        NotificationCenter.default.post(name: .grammarCoachStateDidChange, object: enabled)
    }
    
    public func setStyle(_ style: WritingStyle) {
        currentStyle = style
        playTickSound()
        showCorrectionToast(title: "Style: \(style.rawValue)", detail: style.description)
    }
    
    // MARK: - Typing Box Window
    
    public func showTypingBox() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.showTypingBox()
            }
            return
        }
        
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousActiveApp = front
        }
        
        if typingBoxPanel == nil {
            let panel = KeyPanel(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 530),
                styleMask: [.titled, .closable, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.minSize = NSSize(width: 580, height: 460)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: GrammarTypingBoxView())
            self.typingBoxPanel = panel
        }
        
        guard let panel = typingBoxPanel else { return }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func hideTypingBox() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.hideTypingBox()
            }
            return
        }
        typingBoxPanel?.orderOut(nil)
    }
    
    public func toggleTypingBox() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.toggleTypingBox()
            }
            return
        }
        if let panel = typingBoxPanel, panel.isVisible {
            hideTypingBox()
        } else {
            showTypingBox()
        }
    }
    
    public func pasteIntoPreviousApp(text: String) {
        guard !text.isEmpty else { return }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(text, forType: .string)
        
        hideTypingBox()
        
        let appToActivate = previousActiveApp ?? NSWorkspace.shared.runningApplications.first(where: {
            $0.isActive == false && $0.activationPolicy == .regular
        })
        
        if let app = appToActivate {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Live Keyboard Monitoring (Inline Auto-Correct)
    
    private func startMonitoring() {
        currentWordBuffer = ""
        if AXIsProcessTrusted() {
            setupEventTap()
        } else {
            let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
            let options = [checkOptPrompt: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self.accessibilityPollTimer = nil
                    self.setupEventTap()
                    DispatchQueue.main.async {
                        self.playTickSound()
                        self.showCorrectionToast(title: "Live Auto-Correct Connected", detail: "Accessibility granted. Real-time typing active!")
                        self.objectWillChange.send()
                    }
                }
            }
        }
        
        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handleGlobalKeyDown(event)
            }
        }
    }
    
    private func stopMonitoring() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        currentWordBuffer = ""
    }
    
    private func setupEventTap() {
        guard eventTap == nil else { return }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let service = Unmanaged<GrammarCoachService>.fromOpaque(refcon).takeUnretainedValue()
                return service.filterEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func filterEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if isSimulatingKeystrokes {
            return Unmanaged.passRetained(event)
        }
        
        guard isEnabled else {
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        if keyCode == 51 { // Delete
            if !currentWordBuffer.isEmpty {
                currentWordBuffer.removeLast()
            }
            return Unmanaged.passRetained(event)
        }
        
        var length: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        
        guard length > 0, let scalar = UnicodeScalar(chars[0]) else {
            return Unmanaged.passRetained(event)
        }
        
        let ch = Character(scalar)
        let isDelimiter = ch == " " || ch == "\n" || ch == "\r" || ch == "\t" || ch == "." || ch == "," || ch == "!" || ch == "?" || ch == ";" || ch == ":"
        
        if isDelimiter {
            let wordToEvaluate = currentWordBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            currentWordBuffer = ""
            
            if !wordToEvaluate.isEmpty {
                if let correction = getCorrection(for: wordToEvaluate), correction != wordToEvaluate {
                    replaceWordInline(original: wordToEvaluate, replacement: correction, delimiter: ch)
                    return nil
                }
            }
        } else if ch.isLetter || ch == "'" || ch == "-" {
            currentWordBuffer.append(ch)
            if currentWordBuffer.count > 45 {
                currentWordBuffer.removeFirst()
            }
        } else {
            currentWordBuffer = ""
        }
        
        return Unmanaged.passRetained(event)
    }
    
    private func handleGlobalKeyDown(_ event: NSEvent) {
        guard eventTap == nil, isEnabled else { return }
        
        if event.keyCode == 51 {
            if !currentWordBuffer.isEmpty { currentWordBuffer.removeLast() }
            return
        }
        
        guard let chars = event.characters, let ch = chars.first else { return }
        let isDelimiter = ch == " " || ch == "\r" || ch == "\n" || ch == "." || ch == "," || ch == "!" || ch == "?"
        
        if isDelimiter {
            let word = currentWordBuffer
            currentWordBuffer = ""
            if let correction = getCorrection(for: word), correction != word {
                totalCorrectionsCount += 1
                lastCorrectionMessage = "\(word) → \(correction)"
                showCorrectionToast(title: "Auto-Corrected", detail: "\"\(word)\" → \"\(correction)\"")
            }
        } else if ch.isLetter || ch == "'" {
            currentWordBuffer.append(ch)
        } else {
            currentWordBuffer = ""
        }
    }
    
    public func getCorrection(for word: String) -> String? {
        let clean = word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        guard !clean.isEmpty else { return nil }
        let lower = clean.lowercased()
        
        if clean == "i" {
            return "I"
        }
        
        if let corrected = commonTypos[lower] {
            return preserveCase(original: clean, replacement: corrected)
        }
        
        if currentStyle == .formal {
            if let formal = formalExpansions[lower] {
                return preserveCase(original: clean, replacement: formal)
            }
        } else if currentStyle == .casual {
            if let casual = casualContractions[lower] {
                return preserveCase(original: clean, replacement: casual)
            }
        }
        
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: clean, startingAt: 0)
        if range.location != NSNotFound {
            let guesses = checker.guesses(forWordRange: NSRange(location: 0, length: (clean as NSString).length), in: clean, language: "en_US", inSpellDocumentWithTag: 0) ?? []
            if let first = guesses.first, first.lowercased() != lower {
                return preserveCase(original: clean, replacement: first)
            }
        }
        
        return nil
    }
    
    private func preserveCase(original: String, replacement: String) -> String {
        guard let firstOriginal = original.first, let firstRep = replacement.first else {
            return replacement
        }
        
        if original == original.uppercased() && original.count > 1 {
            return replacement.uppercased()
        }
        
        if firstOriginal.isUppercase {
            return String(firstRep.uppercased()) + replacement.dropFirst()
        }
        
        return replacement
    }
    
    private func replaceWordInline(original: String, replacement: String, delimiter: Character) {
        guard AXIsProcessTrusted() else { return }
        
        isSimulatingKeystrokes = true
        totalCorrectionsCount += 1
        lastCorrectionMessage = "\(original) → \(replacement)"
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            let backspaceCount = original.count
            let source = CGEventSource(stateID: .combinedSessionState)
            
            for _ in 0..<backspaceCount {
                let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
                usleep(4000)
            }
            
            usleep(8000)
            
            let textToInsert = replacement + String(delimiter)
            var utf16Chars = Array(textToInsert.utf16)
            
            let downEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            downEvent?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)
            let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            
            downEvent?.post(tap: .cghidEventTap)
            upEvent?.post(tap: .cghidEventTap)
            
            usleep(8000)
            self.isSimulatingKeystrokes = false
            
            DispatchQueue.main.async {
                self.playTickSound()
                self.showCorrectionToast(title: "Auto-Corrected", detail: "\"\(original)\" → \"\(replacement)\"")
            }
        }
    }
    
    // MARK: - Native Linguistic Grammar Engine
    
    public func polishTextWithAI(_ text: String, style: WritingStyle, completion: @escaping (String, Int, [String]) -> Void) {
        GrammarAIService.shared.polishWithAI(text: text, style: style) { polished, changes in
            completion(polished, changes.count, changes)
        }
    }
    
    public func polishText(_ text: String, style: WritingStyle) -> (polished: String, correctionsCount: Int, changes: [String]) {
        return polishNative(text, style: style)
    }
    
    public func polishNative(_ text: String, style: WritingStyle) -> (polished: String, correctionsCount: Int, changes: [String]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (text, 0, [])
        }
        
        var working = text
        var changes: [String] = []
        var count = 0
        
        // 1. Standalone 'i' -> 'I'
        if let regexI = try? NSRegularExpression(pattern: "\\bi\\b", options: []) {
            let matches = regexI.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
            if !matches.isEmpty {
                working = regexI.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: "I")
                changes.append("Capitalized 'i' → 'I'")
                count += matches.count
            }
        }
        
        // 2. High-Frequency Grammar Fixes
        let grammarRules: [(pattern: String, replacement: String, name: String)] = [
            // could of -> could have
            ("\\b(could|should|would|might|must)\\s+of\\b", "$1 have", "Modal verb agreement (could of → could have)"),
            // suppose to -> supposed to
            ("\\bsuppose\\s+to\\b", "supposed to", "Past participle (suppose to → supposed to)"),
            ("\\buse\\s+to\\s+be\\b", "used to be", "Habitual expression (use to be → used to be)"),
            // better then -> better than
            ("\\b(better|worse|more|less|rather|easier|harder|bigger|smaller)\\s+then\\b", "$1 than", "Comparison (then → than)"),
            // their is -> there is
            ("\\btheir\\s+(is|are|was|were)\\b", "there $1", "Existential phrase (their → there)"),
            // subject-verb fixes
            ("\\bI\\s+(is|are)\\b", "I am", "Subject-verb agreement (I am)"),
            ("\\b(he|she|it)\\s+dont\\b", "$1 doesn't", "Subject-verb contraction (doesn't)"),
            ("\\b(he|she|it)\\s+do\\s+not\\b", "$1 does not", "Subject-verb agreement (does not)"),
            ("\\b(they|we|you)\\s+has\\b", "$1 have", "Subject-verb agreement (have)"),
            // articles
            ("\\ba\\s+([aeiouAEIOU][a-zA-Z]+)\\b", "an $1", "Indefinite article (a → an)"),
            ("\\ban\\s+([bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ][a-zA-Z]+)\\b", "a $1", "Indefinite article (an → a)")
        ]
        
        for rule in grammarRules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                if !matches.isEmpty {
                    working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: rule.replacement)
                    changes.append(rule.name)
                    count += matches.count
                }
            }
        }
        
        // 3. Known typos replacement
        for (typo, correction) in commonTypos {
            let pat = "\\b" + NSRegularExpression.escapedPattern(for: typo) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                if !matches.isEmpty {
                    working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: correction)
                    changes.append("Spelling: \(typo) → \(correction)")
                    count += matches.count
                }
            }
        }
        
        // 4. Style-Specific Adjustments
        if style == .formal {
            // Expand contractions
            for (contraction, expansion) in formalExpansions {
                let pat = "\\b" + NSRegularExpression.escapedPattern(for: contraction) + "\\b"
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                    let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                    if !matches.isEmpty {
                        working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: expansion)
                        changes.append("Formal expansion: \(contraction) → \(expansion)")
                        count += matches.count
                    }
                }
            }
        } else if style == .casual {
            // Natural contractions
            for (expansion, contraction) in casualContractions {
                let pat = "\\b" + NSRegularExpression.escapedPattern(for: expansion) + "\\b"
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                    let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                    if !matches.isEmpty {
                        working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: contraction)
                        changes.append("Conversational: \(expansion) → \(contraction)")
                        count += matches.count
                    }
                }
            }
        } else if style == .concise {
            // Trim conversational wordiness
            let wordyPairs = [
                ("in order to", "to"),
                ("at this point in time", "now"),
                ("due to the fact that", "because"),
                ("for the purpose of", "for"),
                ("in the event that", "if")
            ]
            for (wordy, concise) in wordyPairs {
                let pat = "\\b" + NSRegularExpression.escapedPattern(for: wordy) + "\\b"
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                    let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                    if !matches.isEmpty {
                        working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: concise)
                        changes.append("Conciseness: \"\(wordy)\" → \"\(concise)\"")
                        count += matches.count
                    }
                }
            }
        }
        
        // 5. Clean punctuation spacing
        if let spaceBeforePunct = try? NSRegularExpression(pattern: "\\s+([,.:;?!])", options: []) {
            working = spaceBeforePunct.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: "$1")
        }
        if let doublePunct = try? NSRegularExpression(pattern: "([,.:;?!])\\1+", options: []) {
            working = doublePunct.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: "$1")
        }
        
        // 6. Sentence capitalization
        var capitalizedResult = ""
        var capitalizeNext = true
        for char in working {
            if capitalizeNext && char.isLetter {
                capitalizedResult.append(char.uppercased())
                capitalizeNext = false
            } else {
                capitalizedResult.append(char)
                if char == "." || char == "!" || char == "?" || char == "\n" {
                    capitalizeNext = true
                }
            }
        }
        
        let trimmed = capitalizedResult.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed, count, changes)
    }
    
    // MARK: - Mini Floating Toast
    
    private func showCorrectionToast(title: String, detail: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.showCorrectionToast(title: title, detail: detail)
            }
            return
        }
        
        toastDismissWorkItem?.cancel()
        
        if toastPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 50),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            self.toastPanel = panel
        }
        
        guard let panel = toastPanel else { return }
        
        panel.contentView = NSHostingView(
            rootView: GrammarToastView(title: title, detail: detail, style: currentStyle)
        )
        
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 300
            let y = screen.visibleFrame.maxY - 70
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.orderFront(nil)
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.toastPanel?.orderOut(nil)
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }
    
    private func playTickSound() {
        if AppSettings.shared.playSound {
            NSSound(named: "Tink")?.play()
        }
    }
}

// MARK: - Mini Floating Toast View

struct GrammarToastView: View {
    let title: String
    let detail: String
    let style: WritingStyle
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Color(red: 0.38, green: 0.75, blue: 0.98))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
    }
}
