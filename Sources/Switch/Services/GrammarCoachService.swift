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
    
    // High-confidence verified typo lookup
    public let commonTypos: [String: String] = [
        "grammer": "grammar",
        "grammerly": "Grammarly",
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
        "tomorow": "tomorrow",
        "tounge": "tongue",
        "unforseen": "unforeseen",
        "usefull": "useful",
        "vaccum": "vacuum",
        "vehical": "vehicle",
        "visable": "visible",
        "wich": "which",
        "wether": "whether",
        "whould": "would",
        "yesteday": "yesterday",
        "accomodate": "accommodate",
        "computr": "computer",
        "changs": "changes",
        "restaraunt": "restaurant",
        "unfortunatly": "unfortunately",
        "developr": "developer",
        // Contractions with apostrophes
        "dont": "don't",
        "cant": "can't",
        "wont": "won't",
        "didnt": "didn't",
        "doesnt": "doesn't",
        "isnt": "isn't",
        "arent": "aren't",
        "wasnt": "wasn't",
        "werent": "weren't",
        "hasnt": "hasn't",
        "havent": "haven't",
        "hadnt": "hadn't",
        "wouldnt": "wouldn't",
        "shouldnt": "shouldn't",
        "couldnt": "couldn't",
        "mustnt": "mustn't",
        "im": "I'm",
        "ive": "I've",
        "youre": "you're",
        "theyre": "they're",
        "weve": "we've",
        "youve": "you've",
        "theyve": "they've",
        "youll": "you'll",
        "theyll": "they'll",
        "thats": "that's",
        "whats": "what's",
        "theres": "there's",
        "heres": "here's",
        "wheres": "where's",
        "hows": "how's",
        "whos": "who's",
        "itll": "it'll",
        "thatll": "that'll",
        "couldve": "could've",
        "shouldve": "should've",
        "wouldve": "would've",
        "mightve": "might've",
        "mustve": "must've"
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
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
                styleMask: [.titled, .closable, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.minSize = NSSize(width: 620, height: 420)
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
    
    public func preserveCase(original: String, replacement: String) -> String {
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
    
    // MARK: - Grammarly-Grade Issue Scanner
    
    public func scanIssues(in text: String) -> [GrammarIssue] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var issues: [GrammarIssue] = []
        let ns = text as NSString
        let checker = NSSpellChecker.shared
        
        // 1. NSSpellChecker Non-Wrapping Full Scan
        var offset = 0
        var coveredRanges: [NSRange] = []
        
        while offset < ns.length {
            var wordCount = 0
            let range = checker.checkSpelling(
                of: text,
                startingAt: offset,
                language: "en_US",
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: &wordCount
            )
            
            if range.location == NSNotFound || range.location < offset { break }
            
            let misspelled = ns.substring(with: range)
            let lower = misspelled.lowercased()
            
            // Ignore single capital acronyms e.g. API, CPU, RAM, URL, GPU
            if misspelled == misspelled.uppercased() && misspelled.count <= 5 {
                offset = range.location + range.length
                continue
            }
            
            let replacement: String?
            if let direct = commonTypos[lower] {
                replacement = preserveCase(original: misspelled, replacement: direct)
            } else {
                let guesses = checker.guesses(
                    forWordRange: range,
                    in: text,
                    language: "en_US",
                    inSpellDocumentWithTag: 0
                ) ?? []
                replacement = guesses.first.map { preserveCase(original: misspelled, replacement: $0) }
            }
            
            if let best = replacement, best != misspelled {
                issues.append(
                    GrammarIssue(
                        category: .correctness,
                        original: misspelled,
                        replacement: best,
                        reason: "Misspelled word: change to \"\(best)\"",
                        range: range
                    )
                )
                coveredRanges.append(range)
            }
            
            offset = range.location + max(1, range.length)
        }
        
        // 2. Grammar & Syntax Rules
        let grammarRules: [(pattern: String, replacement: String, reason: String)] = [
            // Modal verbs
            ("\\b(could|should|would|might|must)\\s+of\\b", "$1 have", "Modal verb agreement: use \"have\" instead of \"of\""),
            // Past participles
            ("\\bsuppose\\s+to\\b", "supposed to", "Use past participle: \"supposed to\""),
            ("\\buse\\s+to\\s+be\\b", "used to be", "Habitual expression: \"used to be\""),
            // Homophones
            ("\\btheir\\s+(is|are|was|were)\\b", "there $1", "Use \"there\" to indicate existence"),
            ("\\byour\\s+(welcome|right|wrong|the best)\\b", "you're $1", "Contraction: use \"you're\" (you are)"),
            ("\\bits\\s+(good|bad|fine|ok|okay|working|broken|great|nice|cool|important|ready|done|hard|easy|possible)\\b", "it's $1", "Contraction: use \"it's\" (it is)"),
            ("\\b(better|worse|more|less|rather|easier|harder|bigger|smaller)\\s+then\\b", "$1 than", "Comparison: use \"than\" instead of \"then\""),
            // Subject-Verb Agreement
            ("\\bI\\s+(is|are)\\b", "I am", "Subject-verb agreement: use \"am\" with \"I\""),
            ("\\b(he|she|it)\\s+dont\\b", "$1 doesn't", "Subject-verb agreement: use \"doesn't\" with singular third-person"),
            ("\\b(he|she|it)\\s+do\\s+not\\b", "$1 does not", "Subject-verb agreement: use \"does not\""),
            ("\\b(they|we|you)\\s+has\\b", "$1 have", "Subject-verb agreement: use \"have\" with plural subjects"),
            // Articles
            ("\\ba\\s+([aeiouAEIOU][a-zA-Z]+)\\b", "an $1", "Indefinite article: use \"an\" before vowel sounds"),
            ("\\ban\\s+([bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ][a-zA-Z]+)\\b", "a $1", "Indefinite article: use \"a\" before consonant sounds"),
            // Pronoun Capitalization
            ("\\bi\\b", "I", "Capitalization: capitalize the pronoun \"I\"")
        ]
        
        for rule in grammarRules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
                for m in matches {
                    // Check overlap
                    if coveredRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
                        continue
                    }
                    let original = ns.substring(with: m.range)
                    let rep = regex.stringByReplacingMatches(in: original, range: NSRange(location: 0, length: (original as NSString).length), withTemplate: rule.replacement)
                    if rep != original {
                        issues.append(
                            GrammarIssue(
                                category: .correctness,
                                original: original,
                                replacement: rep,
                                reason: rule.reason,
                                range: m.range
                            )
                        )
                        coveredRanges.append(m.range)
                    }
                }
            }
        }
        
        // 3. Clarity & Conciseness Rules
        let clarityRules: [(pattern: String, replacement: String, reason: String)] = [
            ("\\bin order to\\b", "to", "Clarity: simplify wordy phrase to \"to\""),
            ("\\bdue to the fact that\\b", "because", "Clarity: simplify wordy phrase to \"because\""),
            ("\\bat this point in time\\b", "now", "Clarity: simplify wordy phrase to \"now\""),
            ("\\bin the event that\\b", "if", "Clarity: simplify wordy phrase to \"if\""),
            ("\\bfor the purpose of\\b", "for", "Clarity: simplify wordy phrase to \"for\""),
            ("\\beach and every\\b", "every", "Clarity: eliminate redundant pairing (\"each and every\")"),
            ("\\bfirst and foremost\\b", "first", "Clarity: eliminate redundant pairing (\"first and foremost\")"),
            ("\\bas a matter of fact\\b", "actually", "Clarity: simplify filler to \"actually\"")
        ]
        
        for rule in clarityRules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
                for m in matches {
                    if coveredRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
                        continue
                    }
                    let original = ns.substring(with: m.range)
                    issues.append(
                        GrammarIssue(
                            category: .clarity,
                            original: original,
                            replacement: rule.replacement,
                            reason: rule.reason,
                            range: m.range
                        )
                    )
                    coveredRanges.append(m.range)
                }
            }
        }
        
        // 4. Engagement & Vocabulary Rules
        let engagementRules: [(pattern: String, replacement: String, reason: String)] = [
            ("\\bvery good\\b", "excellent", "Engagement: strengthen weak intensifier with \"excellent\""),
            ("\\bvery bad\\b", "substandard", "Engagement: strengthen weak intensifier with \"substandard\""),
            ("\\bvery big\\b", "substantial", "Engagement: strengthen weak intensifier with \"substantial\""),
            ("\\bvery important\\b", "critical", "Engagement: strengthen weak intensifier with \"critical\""),
            ("\\bvery hard\\b", "challenging", "Engagement: strengthen weak intensifier with \"challenging\""),
            ("\\bvery easy\\b", "effortless", "Engagement: strengthen weak intensifier with \"effortless\"")
        ]
        
        for rule in engagementRules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
                for m in matches {
                    if coveredRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
                        continue
                    }
                    let original = ns.substring(with: m.range)
                    issues.append(
                        GrammarIssue(
                            category: .engagement,
                            original: original,
                            replacement: rule.replacement,
                            reason: rule.reason,
                            range: m.range
                        )
                    )
                    coveredRanges.append(m.range)
                }
            }
        }
        
        return issues.sorted { $0.range.location < $1.range.location }
    }
    
    // MARK: - Issue Application
    
    public func applyIssue(_ issue: GrammarIssue, to text: String) -> String {
        let ns = text as NSString
        guard issue.range.location + issue.range.length <= ns.length else {
            return text.replacingOccurrences(of: issue.original, with: issue.replacement)
        }
        let currentSub = ns.substring(with: issue.range)
        if currentSub.caseInsensitiveCompare(issue.original) == .orderedSame {
            return ns.replacingCharacters(in: issue.range, with: issue.replacement)
        } else {
            return text.replacingOccurrences(of: issue.original, with: issue.replacement)
        }
    }
    
    public func applyAllIssues(_ issues: [GrammarIssue], to text: String) -> String {
        var working = text
        let sorted = issues.filter { !$0.isDismissed }.sorted { $0.range.location > $1.range.location }
        
        for issue in sorted {
            let ns = working as NSString
            if issue.range.location + issue.range.length <= ns.length {
                let sub = ns.substring(with: issue.range)
                if sub.caseInsensitiveCompare(issue.original) == .orderedSame {
                    working = ns.replacingCharacters(in: issue.range, with: issue.replacement)
                    continue
                }
            }
            working = working.replacingOccurrences(of: issue.original, with: issue.replacement)
        }
        
        // Punctuation clean-up
        if let spaceBeforePunct = try? NSRegularExpression(pattern: "\\s+([,.:;?!])", options: []) {
            working = spaceBeforePunct.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: "$1")
        }
        if let doublePunct = try? NSRegularExpression(pattern: "([,.:;?!])\\1+", options: []) {
            working = doublePunct.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: "$1")
        }
        
        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public func calculateScore(text: String, issues: [GrammarIssue]) -> Int {
        let activeIssues = issues.filter { !$0.isDismissed && !$0.isApplied }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 100 }
        if activeIssues.isEmpty { return 100 }
        
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        var penalty = 0
        for issue in activeIssues {
            switch issue.category {
            case .correctness: penalty += 12
            case .clarity: penalty += 6
            case .engagement: penalty += 4
            case .delivery: penalty += 4
            }
        }
        
        let base = max(20, 100 - Int(Double(penalty) / max(1.0, Double(words) / 15.0)))
        return min(100, max(15, base))
    }
    
    // MARK: - Native Linguistic Polish Engine
    
    public func polishTextWithAI(_ text: String, style: WritingStyle, completion: @escaping (String, Int, [String]) -> Void) {
        GrammarAIService.shared.polishWithAI(text: text, style: style) { polished, changes in
            completion(polished, changes.count, changes)
        }
    }
    
    public func polishText(_ text: String, style: WritingStyle) -> (polished: String, correctionsCount: Int, changes: [String]) {
        return polishNative(text, style: style)
    }
    
    // MARK: - Advanced Comma & Punctuation Auto-Correction
    
    public func correctPunctuationAndCommas(in text: String) -> (result: String, fixes: [String]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (text, [])
        }
        
        var working = text
        var fixes: [String] = []
        
        // 1. Spacing around punctuation:
        // Remove space before punctuation: "word , word" -> "word, word", "word ." -> "word."
        if let spaceBefore = try? NSRegularExpression(pattern: "\\s+([,.:;?!])", options: []) {
            let ns = working as NSString
            let matches = spaceBefore.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = spaceBefore.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
                fixes.append("Removed space before punctuation")
            }
        }
        
        // Add space after comma: "apple,banana" -> "apple, banana" (protecting numbers like 1,000)
        if let commaAfter = try? NSRegularExpression(pattern: "(?<=[a-zA-Z0-9]),(?=[a-zA-Z])", options: []) {
            let ns = working as NSString
            let matches = commaAfter.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = commaAfter.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: ", ")
                fixes.append("Added space after comma")
            }
        }
        
        // Add space after terminal punctuation (period, question mark, exclamation mark) before letters, protecting web domains (e.g. google.com):
        let domainExtensions = "com|org|net|edu|gov|io|co|ai|app|dev|html|css|js|ts|swift|py|json|md|pdf|png|jpg|jpeg"
        let punctAfterPattern = "(?<=[a-zA-Z0-9])([?!])(?=[a-zA-Z])|(?<=[a-zA-Z0-9])(\\.)(?!(?:\(domainExtensions))\\b)(?=[a-zA-Z])"
        if let terminalAfter = try? NSRegularExpression(pattern: punctAfterPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = terminalAfter.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = terminalAfter.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "$1$2 ")
                fixes.append("Added space after sentence punctuation")
            }
        }
        
        // Add space after colon and semicolon before letter: "Note:this" -> "Note: this"
        if let colonAfter = try? NSRegularExpression(pattern: "(?<=[a-zA-Z0-9])([:;])(?=[a-zA-Z])", options: []) {
            let ns = working as NSString
            let matches = colonAfter.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = colonAfter.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "$1 ")
                fixes.append("Added space after colon/semicolon")
            }
        }
        
        // Parentheses spacing: "word(" -> "word (", "( word )" -> "(word)"
        if let parenBefore = try? NSRegularExpression(pattern: "(?<=[a-zA-Z0-9])\\(", options: []) {
            working = parenBefore.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: " (")
        }
        if let parenInsideL = try? NSRegularExpression(pattern: "\\(\\s+", options: []) {
            working = parenInsideL.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: "(")
        }
        if let parenInsideR = try? NSRegularExpression(pattern: "\\s+\\)", options: []) {
            working = parenInsideR.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: ")")
        }
        
        // 2. Duplicate / Repeated Punctuation Normalization:
        // Multiple commas: ",," -> ","
        if let doubleComma = try? NSRegularExpression(pattern: ",{2,}|,\\s*,", options: []) {
            let ns = working as NSString
            if !doubleComma.matches(in: working, range: NSRange(location: 0, length: ns.length)).isEmpty {
                working = doubleComma.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: ",")
                fixes.append("Removed repeated comma")
            }
        }
        // Double period: ".." -> "."
        if let doublePeriod = try? NSRegularExpression(pattern: "(?<!\\.)\\.\\.(?!\\.)", options: []) {
            let ns = working as NSString
            if !doublePeriod.matches(in: working, range: NSRange(location: 0, length: ns.length)).isEmpty {
                working = doublePeriod.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: ".")
                fixes.append("Fixed double period")
            }
        }
        // 4+ periods -> standard ellipsis "..."
        if let longEllipsis = try? NSRegularExpression(pattern: "\\.{4,}", options: []) {
            working = longEllipsis.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: "...")
        }
        // Repeated question marks: "??" -> "?"
        if let multiQ = try? NSRegularExpression(pattern: "\\?{2,}", options: []) {
            let ns = working as NSString
            if !multiQ.matches(in: working, range: NSRange(location: 0, length: ns.length)).isEmpty {
                working = multiQ.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "?")
                fixes.append("Simplified multiple question marks")
            }
        }
        // Repeated exclamation marks: "!!" -> "!"
        if let multiEx = try? NSRegularExpression(pattern: "!{2,}", options: []) {
            let ns = working as NSString
            if !multiEx.matches(in: working, range: NSRange(location: 0, length: ns.length)).isEmpty {
                working = multiEx.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "!")
                fixes.append("Simplified multiple exclamation marks")
            }
        }
        
        // 3. Introductory Transition Words & Adverbs Missing Comma:
        let introWords = [
            "However", "Therefore", "Furthermore", "Moreover", "In fact", "In addition",
            "Additionally", "Meanwhile", "Nevertheless", "Nonetheless", "Consequently",
            "Subsequently", "Finally", "For example", "For instance", "As a result",
            "Of course", "Obviously", "Naturally", "Clearly", "Frankly", "Honestly",
            "Actually", "Unfortunately", "Fortunately", "Luckily", "Generally",
            "Specifically", "Ideally", "Essentially", "Basically", "In conclusion",
            "To begin with", "On the other hand", "By the way", "In summary", "In short",
            "To be honest", "Needless to say", "Most importantly", "All in all",
            "Above all", "At the same time", "After all", "At last", "In general", "In particular"
        ]
        
        let introPattern = "(^|[.?!;\\n]\\s*)(" + introWords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\s+([a-zA-Z])"
        if let introRegex = try? NSRegularExpression(pattern: introPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = introRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = introRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "$1$2, $3")
                fixes.append("Added comma after introductory phrase")
            }
        }
        
        // Ordinal list transitions: "First we need", "Secondly you should"
        let ordinalPattern = "(^|[.?!;\\n]\\s*)(First|Firstly|Second|Secondly|Third|Thirdly|Lastly)\\s+(we|I|you|he|she|it|they|let|to|check|open|click|do|make|run|start|go|install|take|ensure|note)\\b"
        if let ordRegex = try? NSRegularExpression(pattern: ordinalPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = ordRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = ordRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "$1$2, $3")
                fixes.append("Added comma after introductory transition")
            }
        }
        
        // Interjections: "Yes I will", "No I can't", "Sure we can"
        let interjectionPattern = "(^|[.?!;\\n]\\s*)(Yes|No|Sure)\\s+([a-zA-Z])"
        if let intRegex = try? NSRegularExpression(pattern: interjectionPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = intRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = intRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "$1$2, $3")
                fixes.append("Added comma after introductory response")
            }
        }
        
        // 4. Coordinating Conjunctions (FANBOYS: but, so, yet) connecting independent clauses:
        // "I wanted to go but I was tired" -> "I wanted to go, but I was tired"
        // Avoid "so that" or "so as"
        let conjunctionPattern = "(?<!not only )(?<!so that )(?<!so as )(?<![,;:.?!])\\s+(but|so|yet)\\s+(I|you|he|she|it|we|they)\\b"
        if let conjRegex = try? NSRegularExpression(pattern: conjunctionPattern, options: []) {
            let ns = working as NSString
            let matches = conjRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = conjRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: ", $1 $2")
                fixes.append("Added comma before coordinating conjunction")
            }
        }
        
        // 5. Tag Questions & Polite Closers:
        // "You received the file right?" -> "You received the file, right?"
        let tagPattern = "(?<![,;:.?!])\\s+(right|isnt it|isn't it|arent you|aren't you|dont you|don't you|didnt you|didn't you|wont you|won't you|cant you|can't you)\\?"
        if let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = tagRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = tagRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: ", $1?")
                fixes.append("Added comma before question tag")
            }
        }
        
        // Polite closers: "Help me please." -> "Help me, please."
        let pleasePattern = "(?<![,;:.?!])\\s+(please)([.!])"
        if let pleaseRegex = try? NSRegularExpression(pattern: pleasePattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = pleaseRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = pleaseRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: ", $1$2")
                fixes.append("Added comma before closing polite expression")
            }
        }
        
        // Direct address in gratitude: "Thanks John" -> "Thanks, John"
        let thanksPattern = "\\b(thanks|thank you)\\s+([A-Z][a-z]+)\\b"
        if let thanksRegex = try? NSRegularExpression(pattern: thanksPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = thanksRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = thanksRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "$1, $2")
                fixes.append("Added comma for direct address")
            }
        }
        
        // 6. Dates: "October 4 2026" -> "October 4, 2026"
        let datePattern = "\\b(January|February|March|April|May|June|July|August|September|October|November|December)\\s+(\\d{1,2})\\s+(\\d{4})\\b"
        if let dateRegex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = dateRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = dateRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "$1 $2, $3")
                fixes.append("Added comma in date")
            }
        }
        
        // 7. Contraction Apostrophes in special contexts:
        // "its good" -> "it's good"
        let itsPattern = "\\bits\\s+(a|an|the|not|been|going|important|ready|done|hard|easy|possible|cool|great|working|broken|fine|ok|okay|nice|super|really|too|very|so)\\b"
        if let itsRegex = try? NSRegularExpression(pattern: itsPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = itsRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = itsRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "it's $1")
                fixes.append("Added apostrophe to \"it's\"")
            }
        }
        // "lets go" -> "let's go"
        let letsPattern = "\\blets\\s+(go|do|see|try|make|check|start|build|work|take|get|have|talk|discuss|meet|proceed|continue)\\b"
        if let letsRegex = try? NSRegularExpression(pattern: letsPattern, options: .caseInsensitive) {
            let ns = working as NSString
            let matches = letsRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = letsRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "let's $1")
                fixes.append("Added apostrophe to \"let's\"")
            }
        }
        
        // 8. Sentence Capitalization:
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
        working = capitalizedResult
        
        // Standalone pronoun "i" -> "I"
        if let iRegex = try? NSRegularExpression(pattern: "\\bi\\b", options: []) {
            let ns = working as NSString
            let matches = iRegex.matches(in: working, range: NSRange(location: 0, length: ns.length))
            if !matches.isEmpty {
                working = iRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: ns.length), withTemplate: "I")
                fixes.append("Capitalized pronoun \"I\"")
            }
        }
        
        // Capitalize days and months
        let properNouns = [
            "monday": "Monday", "tuesday": "Tuesday", "wednesday": "Wednesday",
            "thursday": "Thursday", "friday": "Friday", "saturday": "Saturday", "sunday": "Sunday",
            "january": "January", "february": "February", "march": "March", "april": "April",
            "june": "June", "july": "July", "august": "August", "september": "September",
            "october": "October", "november": "November", "december": "December"
        ]
        for (lower, proper) in properNouns {
            if let pRegex = try? NSRegularExpression(pattern: "\\b" + lower + "\\b", options: []) {
                working = pRegex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: proper)
            }
        }
        
        // 9. Terminal Punctuation:
        // If text ends with an alphanumeric character and has at least 2 words, append a period "."
        let trimmed = working.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split { $0.isWhitespace || $0.isNewline }
        if words.count >= 2, let lastChar = trimmed.last, lastChar.isLetter || lastChar.isNumber {
            working = trimmed + "."
            fixes.append("Added terminal period")
        }
        
        return (working.trimmingCharacters(in: .whitespacesAndNewlines), fixes)
    }
    
    // MARK: - Direct Instant Auto-Correction Pipeline
    
    public func autoCorrectText(_ text: String, style: WritingStyle = .fixOnly) -> (corrected: String, fixes: [String]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (text, []) }
        
        var working = trimmed
        var allFixes: [String] = []
        
        // Step 1: Punctuation and comma correction pass
        let punctPass1 = correctPunctuationAndCommas(in: working)
        working = punctPass1.result
        allFixes.append(contentsOf: punctPass1.fixes)
        
        // Step 2: Spell check and grammar scanner pass
        let issues = scanIssues(in: working)
        let relevantIssues: [GrammarIssue]
        switch style {
        case .fixOnly:
            relevantIssues = issues.filter { $0.category == .correctness }
        case .formal, .casual, .elevate:
            relevantIssues = issues
        case .concise:
            relevantIssues = issues.filter { $0.category == .correctness || $0.category == .clarity }
        }
        
        if !relevantIssues.isEmpty {
            working = applyAllIssues(relevantIssues, to: working)
            for issue in relevantIssues {
                allFixes.append("\"\(issue.original)\" → \"\(issue.replacement)\"")
            }
        }
        
        // Step 3: Style expansions / contractions
        if style == .formal {
            for (contraction, expansion) in formalExpansions {
                let pat = "\\b" + NSRegularExpression.escapedPattern(for: contraction) + "\\b"
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                    let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                    if !matches.isEmpty {
                        working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: expansion)
                        allFixes.append("\(contraction) → \(expansion)")
                    }
                }
            }
        } else if style == .casual {
            for (expansion, contraction) in casualContractions {
                let pat = "\\b" + NSRegularExpression.escapedPattern(for: expansion) + "\\b"
                if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                    let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                    if !matches.isEmpty {
                        working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: contraction)
                        allFixes.append("\(expansion) → \(contraction)")
                    }
                }
            }
        }
        
        // Step 4: Final Punctuation, comma, and capitalization pass
        let punctPass2 = correctPunctuationAndCommas(in: working)
        working = punctPass2.result
        for fix in punctPass2.fixes where !allFixes.contains(fix) {
            allFixes.append(fix)
        }
        
        return (working, allFixes)
    }
    
    public func polishNative(_ text: String, style: WritingStyle) -> (polished: String, correctionsCount: Int, changes: [String]) {
        let (corrected, fixes) = autoCorrectText(text, style: style)
        return (corrected, fixes.count, fixes)
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
