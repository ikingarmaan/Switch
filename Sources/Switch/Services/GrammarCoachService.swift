import Foundation
import Cocoa
import Carbon
import SwiftUI

public extension Notification.Name {
    static let grammarCoachStateDidChange = Notification.Name("SwitchGrammarCoachStateDidChange")
    static let grammarCoachStyleDidChange = Notification.Name("SwitchGrammarCoachStyleDidChange")
}

public enum WritingStyle: String, CaseIterable, Identifiable, Sendable {
    case formal = "Formal"
    case casual = "Casual"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .formal: return "briefcase.fill"
        case .casual: return "sparkles"
        }
    }
    
    public var badge: String {
        switch self {
        case .formal: return "👔 Formal"
        case .casual: return "☕ Casual"
        }
    }
    
    public var description: String {
        switch self {
        case .formal: return "Professional, polite, polished, and grammatically precise"
        case .casual: return "Friendly, warm, conversational, natural, and expressive"
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
    @Published public var currentStyle: WritingStyle = .formal {
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
    
    // Common typo & contraction lookup maps
    private let commonTypos: [String: String] = [
        // User's recent prompts & frequent English errors
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
    
    // Casual contractions (used in Casual mode & auto-corrector)
    private let casualContractions: [String: String] = [
        "dont": "don't",
        "cant": "can't",
        "wont": "won't",
        "didnt": "didn't",
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
        "thats": "that's",
        "whats": "what's",
        "theres": "there's",
        "heres": "here's",
        "lets": "let's",
        "youre": "you're",
        "theyre": "they're",
        "weve": "we've",
        "youve": "you've",
        "im": "I'm",
        "ive": "I've",
        "id": "I'd",
        "ill": "I'll",
        "itll": "it'll",
        "whois": "who's",
        "hows": "how's",
        "wheres": "where's",
        "doesnt": "doesn't"
    ]
    
    // Formal expansions (used in Formal mode)
    private let formalExpansions: [String: String] = [
        "dont": "do not",
        "don't": "do not",
        "cant": "cannot",
        "can't": "cannot",
        "wont": "will not",
        "won't": "will not",
        "didnt": "did not",
        "didn't": "did not",
        "isnt": "is not",
        "isn't": "is not",
        "arent": "are not",
        "aren't": "are not",
        "wasnt": "was not",
        "wasn't": "was not",
        "im": "I am",
        "i'm": "I am",
        "ive": "I have",
        "i've": "I have",
        "id": "I would",
        "i'd": "I would",
        "ill": "I will",
        "i'll": "I will",
        "thats": "that is",
        "that's": "that is",
        "whats": "what is",
        "what's": "what is",
        "theres": "there is",
        "there's": "there is",
        "gonna": "going to",
        "wanna": "would like to",
        "gotta": "must",
        "kinda": "rather",
        "sorta": "somewhat",
        "pls": "please",
        "plz": "please",
        "thx": "thank you",
        "tnx": "thank you",
        "asap": "as soon as possible",
        "fyi": "for your information",
        "u": "you",
        "ur": "your",
        "r": "are",
        "dunno": "do not know",
        "yep": "yes",
        "yeah": "yes",
        "nope": "no"
    ]
    
    // Tech proper nouns map for inline typing
    private let techProperNounsMap: [String: String] = [
        "macbook": "MacBook",
        "imac": "iMac",
        "macos": "macOS",
        "ios": "iOS",
        "ipados": "iPadOS",
        "watchos": "watchOS",
        "iphone": "iPhone",
        "ipad": "iPad",
        "airpods": "AirPods",
        "finder": "Finder",
        "safari": "Safari",
        "chrome": "Chrome",
        "github": "GitHub",
        "xcode": "Xcode",
        "bluetooth": "Bluetooth",
        "english": "English"
    ]
    
    // Slang and shorthands for inline typing
    private let singleWordSlang: [String: (formal: String, casual: String)] = [
        "u": ("you", "you"),
        "ur": ("your", "your"),
        "r": ("are", "are"),
        "coz": ("because", "because"),
        "cuz": ("because", "because"),
        "cause": ("because", "because"),
        "plz": ("please", "please"),
        "pls": ("please", "please"),
        "thx": ("thank you", "thanks"),
        "ty": ("thank you", "thanks"),
        "tnx": ("thank you", "thanks"),
        "idk": ("I do not know", "I don't know"),
        "tbh": ("to be honest", "to be honest"),
        "imo": ("from my perspective", "in my opinion"),
        "rn": ("currently", "right now"),
        "asap": ("at your earliest convenience", "as soon as possible"),
        "fyi": ("for your information", "just so you know"),
        "btw": ("incidentally", "by the way"),
        "wanna": ("would like to", "want to"),
        "gonna": ("going to", "gonna"),
        "gotta": ("must", "got to"),
        "lemme": ("please allow me to", "let me"),
        "dunno": ("do not know", "don't know"),
        "yep": ("yes", "yeah"),
        "yeah": ("yes", "yeah"),
        "nope": ("no", "nope")
    ]
    
    // Multi-word tech proper nouns
    private let techProperNounsList: [(pattern: String, replacement: String)] = [
        ("\\bmacbook pro\\b", "MacBook Pro"),
        ("\\bmacbook air\\b", "MacBook Air"),
        ("\\bmacbook\\b", "MacBook"),
        ("\\bimac\\b", "iMac"),
        ("\\bmacos\\b", "macOS"),
        ("\\bios\\b", "iOS"),
        ("\\bipados\\b", "iPadOS"),
        ("\\bwatchos\\b", "watchOS"),
        ("\\biphone\\b", "iPhone"),
        ("\\bipad\\b", "iPad"),
        ("\\bairpods\\b", "AirPods"),
        ("\\bapple watch\\b", "Apple Watch"),
        ("\\bapple store\\b", "Apple Store"),
        ("\\bapple silicon\\b", "Apple Silicon"),
        ("\\bapple id\\b", "Apple ID"),
        ("\\bfinder\\b", "Finder"),
        ("\\bsafari\\b", "Safari"),
        ("\\bchrome\\b", "Chrome"),
        ("\\bgithub\\b", "GitHub"),
        ("\\bxcode\\b", "Xcode"),
        ("\\bbluetooth\\b", "Bluetooth"),
        ("\\bwi-?fi\\b", "Wi-Fi"),
        ("\\benglish\\b", "English"),
        ("\\bmonday\\b", "Monday"),
        ("\\btuesday\\b", "Tuesday"),
        ("\\bwednesday\\b", "Wednesday"),
        ("\\bthursday\\b", "Thursday"),
        ("\\bfriday\\b", "Friday"),
        ("\\bsaturday\\b", "Saturday"),
        ("\\bsunday\\b", "Sunday")
    ]
    
    // Multi-word slang and internet phrases
    private let multiWordSlangList: [(pattern: String, formal: String, casual: String)] = [
        ("can u please", "Could you please", "could you please"),
        ("can u", "could you", "can you"),
        ("u r", "you are", "you're"),
        ("ur", "your", "your"),
        ("\\bu\\b", "you", "you"),
        ("\\br\\b", "are", "are"),
        ("\\bplz\\b", "please", "please"),
        ("\\bpls\\b", "please", "please"),
        ("\\bthx\\b", "thank you", "thanks"),
        ("\\bty\\b", "thank you", "thanks"),
        ("\\bcoz\\b", "because", "because"),
        ("\\bcuz\\b", "because", "because"),
        ("\\bcause\\b", "because", "because"),
        ("\\bidk\\b", "I do not know", "I don't know"),
        ("\\btbh\\b", "to be honest", "to be honest"),
        ("\\bimo\\b", "from my perspective", "in my opinion"),
        ("\\brn\\b", "currently", "right now"),
        ("\\basap\\b", "at your earliest convenience", "as soon as possible"),
        ("\\bfyi\\b", "for your information", "just so you know"),
        ("\\bbtw\\b", "incidentally", "by the way"),
        ("\\bwanna\\b", "would like to", "want to"),
        ("\\bgonna\\b", "going to", "gonna"),
        ("\\bgotta\\b", "must", "got to"),
        ("\\blemme\\b", "please allow me to", "let me"),
        ("\\bdunno\\b", "do not know", "don't know"),
        ("\\byep\\b", "yes", "yeah"),
        ("\\bnope\\b", "no", "nope")
    ]
    
    // Grammar rules & common confusion
    private let fullGrammarRules: [(pattern: String, replacement: String)] = [
        // its vs it's
        ("\\bits (good|bad|fine|ok|okay|working|broken|great|nice|cool|important|ready|done|hard|easy|possible)\\b", "it's $1"),
        ("\\bif its\\b", "if it's"),
        ("\\bthat its\\b", "that it's"),
        
        // your vs you're
        ("\\byour (welcome|right|wrong|going|doing|coming|the best)\\b", "you're $1"),
        
        // there vs their
        ("\\btheir is\\b", "there is"),
        ("\\btheir are\\b", "there are"),
        
        // could of -> could have
        ("\\bcould of\\b", "could have"),
        ("\\bshould of\\b", "should have"),
        ("\\bwould of\\b", "would have"),
        ("\\bmight of\\b", "might have"),
        ("\\bmust of\\b", "must have"),
        
        // suppose to -> supposed to
        ("\\bsuppose to\\b", "supposed to"),
        ("\\buse to be\\b", "used to be"),
        
        // comparisons then vs than
        ("\\bbetter then\\b", "better than"),
        ("\\bmore then\\b", "more than"),
        ("\\bless then\\b", "less than"),
        ("\\brather then\\b", "rather than"),
        ("\\beasier then\\b", "easier than"),
        
        // Subject-verb agreement
        ("\\bI is\\b", "I am"),
        ("\\bI are\\b", "I am"),
        ("\\bI has\\b", "I have"),
        ("\\bhe have\\b", "he has"),
        ("\\bshe have\\b", "she has"),
        ("\\bit have\\b", "it has"),
        ("\\bthey has\\b", "they have"),
        ("\\bwe has\\b", "we have"),
        ("\\byou has\\b", "you have"),
        ("\\bhe do not has\\b", "he does not have"),
        ("\\bshe do not has\\b", "she does not have"),
        ("\\bit do not has\\b", "it does not have"),
        ("\\bhe do not have\\b", "he does not have"),
        ("\\bshe do not have\\b", "she does not have"),
        ("\\bhe dont\\b", "he doesn't"),
        ("\\bshe dont\\b", "she doesn't"),
        ("\\bit dont\\b", "it doesn't"),
        
        // Articles
        ("\\ba apple\\b", "an apple"),
        ("\\ba hour\\b", "an hour"),
        ("\\ba honor\\b", "an honor"),
        ("\\ba honest\\b", "an honest"),
        ("\\ban car\\b", "a car"),
        ("\\ban book\\b", "a book"),
        ("\\ban university\\b", "a university")
    ]
    
    // Formal Phrase Bank
    private let fullFormalPhrases: [(String, String)] = [
        ("can you please check", "Could you please review"),
        ("can you check", "Could you please review"),
        ("check this", "review this"),
        ("let me know", "Kindly advise at your convenience"),
        ("let u know", "I will inform you"),
        ("i want to know", "I would like to inquire regarding"),
        ("i wanna know", "I would like to inquire regarding"),
        ("i want to request", "I would like to request"),
        ("i want", "I would like to request"),
        ("i need help with", "I would greatly appreciate your assistance with"),
        ("i need", "I require"),
        ("sorry for late reply", "Thank you for your patience; apologies for the delayed response"),
        ("sorry for the late reply", "Thank you for your patience; apologies for the delayed response"),
        ("sorry for the delay", "Thank you for your patience; apologies for the delay"),
        ("thanks a lot", "Thank you very much"),
        ("thanks for your help", "Thank you very much for your assistance"),
        ("talk to you later", "I look forward to our next correspondence"),
        ("make sure", "ensure"),
        ("look into", "investigate"),
        ("find out", "ascertain"),
        ("deal with", "address"),
        ("get back to you", "follow up with you"),
        ("lots of", "a substantial number of"),
        ("a lot of", "a substantial number of"),
        ("ask for", "request"),
        ("set up", "configure"),
        ("good job", "exceptional work"),
        ("by the way", "incidentally"),
        ("in my opinion", "from my perspective"),
        ("i think that", "it appears that")
    ]
    
    // Casual Phrase Bank
    private let fullCasualPhrases: [(String, String)] = [
        ("I am writing to inquire regarding", "Just wanted to ask about"),
        ("I would be grateful if you could", "Could you please"),
        ("Do not hesitate to contact me", "Feel free to reach out anytime"),
        ("At your earliest convenience", "Whenever you get a chance"),
        ("Please be advised that", "Just letting you know,"),
        ("Thank you very much for your assistance", "Thanks a ton for your help!"),
        ("Thank you for your assistance", "Thanks for your help!"),
        ("Thank you for your patience", "Thanks for waiting!"),
        ("Apologies for the delayed response", "Sorry for the late reply!"),
        ("sorry for (the )?late reply", "Sorry for the late reply,"),
        ("Apologies for the delay", "Sorry for the wait!"),
        ("Kindly advise at your convenience", "Let me know whenever!"),
        ("Kindly advise", "Let me know"),
        ("Utilize", "Use"),
        ("Commence", "Start"),
        ("Terminate", "Wrap up"),
        ("Assist", "Help"),
        ("Inform", "Tell"),
        ("Ascertain", "Find out"),
        ("Therefore,", "So,"),
        ("However,", "Though,"),
        ("Cordially,", "Best,"),
        ("Sincerely,", "Cheers,")
    ]
    
    // Formal Contractions
    private let fullContractionsFormal: [(String, String)] = [
        ("don't", "do not"), ("dont", "do not"),
        ("can't", "cannot"), ("cant", "cannot"),
        ("won't", "will not"), ("wont", "will not"),
        ("didn't", "did not"), ("didnt", "did not"),
        ("isn't", "is not"), ("isnt", "is not"),
        ("aren't", "are not"), ("arent", "are not"),
        ("wasn't", "was not"), ("wasnt", "was not"),
        ("weren't", "were not"), ("werent", "were not"),
        ("hasn't", "has not"), ("hasnt", "has not"),
        ("haven't", "have not"), ("havent", "have not"),
        ("hadn't", "had not"), ("hadnt", "had not"),
        ("wouldn't", "would not"), ("wouldnt", "would not"),
        ("shouldn't", "should not"), ("shouldnt", "should not"),
        ("couldn't", "could not"), ("couldnt", "could not"),
        ("that's", "that is"), ("thats", "that is"),
        ("what's", "what is"), ("whats", "what is"),
        ("there's", "there is"), ("theres", "there is"),
        ("here's", "here is"), ("heres", "here is"),
        ("you're", "you are"), ("youre", "you are"),
        ("they're", "they are"), ("theyre", "they are"),
        ("we've", "we have"), ("weve", "we have"),
        ("you've", "you have"), ("youve", "you have"),
        ("I'm", "I am"), ("im", "I am"),
        ("I've", "I have"), ("ive", "I have"),
        ("I'd", "I would"),
        ("I'll", "I will"),
        ("it'll", "it will"),
        ("it's", "it is"),
        ("doesn't", "does not"), ("doesnt", "does not")
    ]
    
    // Casual Contractions
    private let fullContractionsCasual: [(String, String)] = [
        ("do not", "don't"),
        ("cannot", "can't"),
        ("will not", "won't"),
        ("did not", "didn't"),
        ("is not", "isn't"),
        ("are not", "aren't"),
        ("was not", "wasn't"),
        ("were not", "weren't"),
        ("has not", "hasn't"),
        ("have not", "haven't"),
        ("had not", "hadn't"),
        ("would not", "wouldn't"),
        ("should not", "shouldn't"),
        ("could not", "couldn't"),
        ("that is", "that's"),
        ("what is", "what's"),
        ("there is", "there's"),
        ("here is", "here's"),
        ("you are", "you're"),
        ("they are", "they're"),
        ("we have", "we've"),
        ("you have", "you've"),
        ("I am", "I'm"),
        ("I have", "I've"),
        ("I would", "I'd"),
        ("I will", "I'll"),
        ("it will", "it'll"),
        ("does not", "doesn't"),
        ("dont", "don't"),
        ("cant", "can't"),
        ("wont", "won't"),
        ("im", "I'm"),
        ("ive", "I've"),
        ("youre", "you're"),
        ("theyre", "they're")
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
            showCorrectionToast(title: "Grammar Coach Active", detail: "\(currentStyle.rawValue) Mode · Auto-correct enabled")
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
        
        // Remember frontmost app before showing typing box so we can paste back into it
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousActiveApp = front
        }
        
        if typingBoxPanel == nil {
            let panel = KeyPanel(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
                styleMask: [.titled, .closable, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
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
        
        // 1. Declare types and set string in general pasteboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(text, forType: .string)
        
        // 2. Hide typing box
        hideTypingBox()
        
        // 3. Re-activate previous application
        let appToActivate = previousActiveApp ?? NSWorkspace.shared.runningApplications.first(where: {
            $0.isActive == false && $0.activationPolicy == .regular
        })
        
        if let app = appToActivate {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        
        // 4. Synthesize Command+V to paste directly into the destination app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let source = CGEventSource(stateID: .combinedSessionState)
            // Virtual keycode 9 is 'v'
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Keyboard Monitoring & Realtime Inline Auto-Correction
    
    private func startMonitoring() {
        currentWordBuffer = ""
        
        // 1. Accessibility Event Tap (for active keystroke replacement inline)
        if AXIsProcessTrusted() {
            setupEventTap()
        } else {
            // Check & prompt for Accessibility
            let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
            let options = [checkOptPrompt: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            
            // Background poll: automatically attach as soon as user grants permission in System Settings
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
        
        // 2. Global Event Monitor as lightweight fallback
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
            NSLog("[GrammarCoachService] Failed to create CGEventTap")
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[GrammarCoachService] CGEventTap installed successfully for inline auto-correct")
    }
    
    private func filterEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if isSimulatingKeystrokes {
            return Unmanaged.passRetained(event)
        }
        
        guard isEnabled else {
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        
        // Backspace: drop last char from buffer
        if keyCode == 51 { // kVK_Delete
            if !currentWordBuffer.isEmpty {
                currentWordBuffer.removeLast()
            }
            return Unmanaged.passRetained(event)
        }
        
        // Extract Unicode characters typed
        var length: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        
        guard length > 0, let scalar = UnicodeScalar(chars[0]) else {
            return Unmanaged.passRetained(event)
        }
        
        let ch = Character(scalar)
        
        // Check if delimiter (Space, Return, punctuation)
        let isDelimiter = ch == " " || ch == "\n" || ch == "\r" || ch == "\t" || ch == "." || ch == "," || ch == "!" || ch == "?" || ch == ";" || ch == ":"
        
        if isDelimiter {
            let wordToEvaluate = currentWordBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            currentWordBuffer = ""
            
            if !wordToEvaluate.isEmpty {
                if let correction = getCorrection(for: wordToEvaluate) {
                    // We found a correction! Replace word in place
                    replaceWordInline(original: wordToEvaluate, replacement: correction, delimiter: ch)
                    // Consume this event because we will re-emit the replacement + delimiter
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
        // Fallback for character tracking if EventTap is inactive
        guard eventTap == nil, isEnabled else { return }
        
        if event.keyCode == 51 { // Backspace
            if !currentWordBuffer.isEmpty { currentWordBuffer.removeLast() }
            return
        }
        
        guard let chars = event.characters, let ch = chars.first else { return }
        let isDelimiter = ch == " " || ch == "\r" || ch == "\n" || ch == "." || ch == "," || ch == "!" || ch == "?"
        
        if isDelimiter {
            let word = currentWordBuffer
            currentWordBuffer = ""
            if let correction = getCorrection(for: word) {
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
    
    // MARK: - Auto-Correction Resolution
    
    public func getCorrection(for word: String) -> String? {
        let clean = word.trimmingCharacters(in: CharacterSet.punctuationCharacters)
        guard !clean.isEmpty else { return nil }
        let lower = clean.lowercased()
        
        // 1. Single letter 'i' -> 'I'
        if clean == "i" {
            return "I"
        }
        
        // 2. Tech brands & proper nouns
        if let proper = techProperNounsMap[lower] {
            return proper
        }
        
        // 3. Style-specific slang & shorthands
        if let slang = singleWordSlang[lower] {
            let target = currentStyle == .formal ? slang.formal : slang.casual
            return preserveCase(original: clean, replacement: target)
        }
        
        // 4. Style-specific contraction expansion or contraction creation
        if currentStyle == .formal {
            if let formal = formalExpansions[lower] {
                return preserveCase(original: clean, replacement: formal)
            }
        } else {
            if let casual = casualContractions[lower] {
                return preserveCase(original: clean, replacement: casual)
            }
        }
        
        // 5. Known frequent typos & misspellings
        if let corrected = commonTypos[lower] {
            return preserveCase(original: clean, replacement: corrected)
        }
        
        // 6. NSSpellChecker verification for misspelled words
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: clean, startingAt: 0)
        if range.location != NSNotFound {
            let guesses = checker.guesses(forWordRange: NSRange(location: 0, length: (clean as NSString).length), in: clean, language: "en_US", inSpellDocumentWithTag: 0) ?? []
            for guess in guesses {
                if guess.lowercased() != lower {
                    return preserveCase(original: clean, replacement: guess)
                }
            }
        }
        
        return nil
    }
    
    private func preserveCase(original: String, replacement: String) -> String {
        guard let firstOriginal = original.first, let firstRep = replacement.first else {
            return replacement
        }
        
        // All uppercase
        if original == original.uppercased() && original.count > 1 {
            return replacement.uppercased()
        }
        
        // Capitalized
        if firstOriginal.isUppercase {
            return String(firstRep.uppercased()) + replacement.dropFirst()
        }
        
        return replacement
    }
    
    // MARK: - In-Place Keystroke Replacement
    
    private func replaceWordInline(original: String, replacement: String, delimiter: Character) {
        guard AXIsProcessTrusted() else { return }
        
        isSimulatingKeystrokes = true
        totalCorrectionsCount += 1
        lastCorrectionMessage = "\(original) → \(replacement)"
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            let backspaceCount = original.count
            let source = CGEventSource(stateID: .combinedSessionState)
            
            // 1. Send backspaces to delete the misspelled word
            for _ in 0..<backspaceCount {
                let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
                usleep(5000)
            }
            
            usleep(10000)
            
            // 2. Type replacement word string
            let textToInsert = replacement + String(delimiter)
            var utf16Chars = Array(textToInsert.utf16)
            
            let downEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            downEvent?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: &utf16Chars)
            let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            
            downEvent?.post(tap: .cghidEventTap)
            upEvent?.post(tap: .cghidEventTap)
            
            usleep(10000)
            self.isSimulatingKeystrokes = false
            
            // Play feedback & show cool mini notification
            DispatchQueue.main.async {
                self.playTickSound()
                self.showCorrectionToast(title: "Auto-Corrected", detail: "\"\(original)\" → \"\(replacement)\"")
            }
        }
    }
    
    // MARK: - Paragraph / Text Box Polish Engine
    
    public func polishTextWithAI(_ text: String, style: WritingStyle, completion: @escaping (String, Int, [String]) -> Void) {
        GrammarAIService.shared.polishWithAI(text: text, style: style) { polished, changes in
            completion(polished, changes.count, changes)
        }
    }
    
    public func polishText(_ text: String, style: WritingStyle) -> (polished: String, correctionsCount: Int, changes: [String]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (text, 0, [])
        }
        
        var working = text
        var changes: [String] = []
        var count = 0
        
        // 1. Fragment & Search Query Restructuring
        let restructured = restructureFragments(working, style: style)
        if restructured != working {
            changes.append("Restructured: \"\(working)\" → \"\(restructured)\"")
            count += 1
            working = restructured
        }
        
        // 2. Greeting commas (e.g. "Hey can you..." -> "Hey, can you...")
        let greetingRegex = try? NSRegularExpression(pattern: "^(Hey|Hi|Hello)\\s+([a-zA-Z])", options: .caseInsensitive)
        if let gMatch = greetingRegex?.firstMatch(in: working, range: NSRange(location: 0, length: (working as NSString).length)) {
            let matchedStr = (working as NSString).substring(with: gMatch.range)
            let greetingWord = (working as NSString).substring(with: gMatch.range(at: 1))
            let nextChar = (working as NSString).substring(with: gMatch.range(at: 2))
            let rep = "\(greetingWord.capitalized), \(nextChar.lowercased())"
            working = (working as NSString).replacingCharacters(in: gMatch.range, with: rep)
            changes.append("Greeting: \"\(matchedStr)\" → \"\(rep)\"")
            count += 1
        }
        
        // 3. Multi-word Slang & Shorthands
        for (pattern, formal, casual) in multiWordSlangList {
            let rep = style == .formal ? formal : casual
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                if !matches.isEmpty {
                    working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: rep)
                    changes.append("Normalized: \"\(pattern)\" → \"\(rep)\"")
                    count += matches.count
                }
            }
        }
        
        // 4. Standalone 'i' -> 'I'
        if let regexI = try? NSRegularExpression(pattern: "\\bi\\b", options: []) {
            let matches = regexI.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
            if !matches.isEmpty {
                working = regexI.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: "I")
                changes.append("Capitalized 'i' → 'I'")
                count += matches.count
            }
        }
        
        // 5. Common Typos & Spelling
        for (typo, correction) in commonTypos {
            let pat = "\\b" + NSRegularExpression.escapedPattern(for: typo) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                if !matches.isEmpty {
                    working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: correction)
                    changes.append("Spelling: \"\(typo)\" → \"\(correction)\"")
                    count += matches.count
                }
            }
        }
        
        // 6. Style-specific Phrase Bank
        let phrases = style == .formal ? fullFormalPhrases : fullCasualPhrases
        for (p, rep) in phrases {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: p) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                if !matches.isEmpty {
                    working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: rep)
                    changes.append("\(style.rawValue): \"\(p)\" → \"\(rep)\"")
                    count += matches.count
                }
            }
        }
        
        // 7. Grammar Rules & Subject-Verb Agreement
        for (pattern, rep) in fullGrammarRules {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                if !matches.isEmpty {
                    working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: rep)
                    changes.append("Grammar: \"\(pattern)\" → \"\(rep)\"")
                    count += matches.count
                }
            }
        }
        
        // 8. Style-specific Contractions (Formal expands, Casual contracts)
        let contractions = style == .formal ? fullContractionsFormal : fullContractionsCasual
        for (pattern, rep) in contractions {
            let pat = "\\b" + NSRegularExpression.escapedPattern(for: pattern) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                if !matches.isEmpty {
                    working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: rep)
                    changes.append("Tone: \"\(pattern)\" → \"\(rep)\"")
                    count += matches.count
                }
            }
        }
        
        // 9. Tech Brand & Proper Noun Capitalization
        for (pattern, proper) in techProperNounsList {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: working, range: NSRange(location: 0, length: (working as NSString).length))
                if !matches.isEmpty {
                    working = regex.stringByReplacingMatches(in: working, range: NSRange(location: 0, length: (working as NSString).length), withTemplate: proper)
                    changes.append("Brand: \"\(proper)\"")
                    count += matches.count
                }
            }
        }
        
        // 10. Sentence Capitalization & Smart Punctuation
        working = finalizePunctuation(working, style: style)
        
        return (working, count, changes)
    }
    
    private func restructureFragments(_ text: String, style: WritingStyle) -> String {
        var res = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = res.lowercased()
        
        if style == .formal {
            if lower.hasPrefix("where to find ") {
                let rest = String(res.dropFirst("where to find ".count))
                res = "Where can one locate \(rest)?"
            } else if lower.hasPrefix("where to get ") {
                let rest = String(res.dropFirst("where to get ".count))
                res = "Could you please advise where to obtain \(rest)?"
            } else if lower.hasPrefix("where to download ") {
                let rest = String(res.dropFirst("where to download ".count))
                res = "Could you please advise where to download \(rest)?"
            } else if lower.hasPrefix("how to find ") {
                let rest = String(res.dropFirst("how to find ".count))
                res = "Could you please explain how to locate \(rest)?"
            } else if lower.hasPrefix("how to do ") {
                let rest = String(res.dropFirst("how to do ".count))
                res = "Could you please advise on how to proceed with \(rest)?"
            } else if lower.hasPrefix("how to get ") {
                let rest = String(res.dropFirst("how to get ".count))
                res = "Could you please advise how to acquire \(rest)?"
            } else if lower.hasPrefix("how to ") {
                let rest = String(res.dropFirst("how to ".count))
                res = "Could you please explain how to \(rest)?"
            } else if lower.hasPrefix("tell me when ") {
                let rest = String(res.dropFirst("tell me when ".count))
                res = "Please inform me once \(rest)"
            } else if lower.hasPrefix("tell me ") {
                let rest = String(res.dropFirst("tell me ".count))
                res = "Please advise \(rest)"
            } else if lower.hasPrefix("give me ") {
                let rest = String(res.dropFirst("give me ".count))
                res = "Could you please provide me with \(rest)"
            }
        } else {
            if lower.hasPrefix("where to find ") {
                let rest = String(res.dropFirst("where to find ".count))
                res = "Where can I find \(rest)?"
            } else if lower.hasPrefix("where to get ") {
                let rest = String(res.dropFirst("where to get ".count))
                res = "Where can I grab \(rest)?"
            } else if lower.hasPrefix("where to download ") {
                let rest = String(res.dropFirst("where to download ".count))
                res = "Where can I download \(rest)?"
            } else if lower.hasPrefix("how to find ") {
                let rest = String(res.dropFirst("how to find ".count))
                res = "How do I find \(rest)?"
            } else if lower.hasPrefix("how to do ") {
                let rest = String(res.dropFirst("how to do ".count))
                res = "How do I do \(rest)?"
            } else if lower.hasPrefix("how to get ") {
                let rest = String(res.dropFirst("how to get ".count))
                res = "How can I get \(rest)?"
            } else if lower.hasPrefix("how to ") {
                let rest = String(res.dropFirst("how to ".count))
                res = "How do I \(rest)?"
            } else if lower.hasPrefix("tell me when ") {
                let rest = String(res.dropFirst("tell me when ".count))
                res = "Let me know when \(rest)"
            } else if lower.hasPrefix("tell me ") {
                let rest = String(res.dropFirst("tell me ".count))
                res = "Let me know \(rest)"
            } else if lower.hasPrefix("give me ") {
                let rest = String(res.dropFirst("give me ".count))
                res = "Could you send me \(rest)"
            }
        }
        return res
    }
    
    private func finalizePunctuation(_ text: String, style: WritingStyle) -> String {
        var res = ""
        var capitalizeNext = true
        
        for char in text {
            if capitalizeNext && char.isLetter {
                res.append(char.uppercased())
                capitalizeNext = false
            } else {
                res.append(char)
                if char == "." || char == "!" || char == "?" || char == "\n" {
                    capitalizeNext = true
                }
            }
        }
        
        let trimmed = res.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return res }
        
        let lastChar = trimmed.last!
        if lastChar != "." && lastChar != "!" && lastChar != "?" {
            let lower = trimmed.lowercased()
            let questionStarters = ["where", "when", "why", "what", "how", "who", "which", "could", "would", "can", "should", "is", "are", "do", "does", "did", "will"]
            let isQuestion = questionStarters.contains(where: { lower.hasPrefix($0 + " ") })
            
            if isQuestion {
                return trimmed + "?"
            } else {
                return trimmed + (style == .casual && (lower.contains("thanks") || lower.contains("cheers")) ? "!" : ".")
            }
        }
        
        return res
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
                .foregroundColor(style == .formal ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color(red: 0.95, green: 0.65, blue: 0.25))
            
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
