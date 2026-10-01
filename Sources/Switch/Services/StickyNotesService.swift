import Foundation
import Cocoa
import SwiftUI
import Combine

public extension Notification.Name {
    static let stickyNotesStateDidChange = Notification.Name("SwitchStickyNotesStateDidChange")
    static let stickyNotesCountDidChange = Notification.Name("SwitchStickyNotesCountDidChange")
}

// MARK: - Colorful Themes
public enum StickyNoteColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case yellow
    case coral
    case mint
    case blue
    case purple
    case orange
    case charcoal
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .yellow: return "Sunburst Yellow"
        case .coral: return "Coral Pink"
        case .mint: return "Fresh Mint"
        case .blue: return "Sky Blue"
        case .purple: return "Electric Violet"
        case .orange: return "Warm Tangerine"
        case .charcoal: return "Midnight Slate"
        }
    }
    
    public var topColor: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.93, blue: 0.45)
        case .coral: return Color(red: 1.0, green: 0.53, blue: 0.65)
        case .mint: return Color(red: 0.45, green: 0.93, blue: 0.68)
        case .blue: return Color(red: 0.42, green: 0.82, blue: 0.98)
        case .purple: return Color(red: 0.80, green: 0.60, blue: 0.98)
        case .orange: return Color(red: 1.0, green: 0.68, blue: 0.38)
        case .charcoal: return Color(red: 0.20, green: 0.21, blue: 0.24)
        }
    }
    
    public var bottomColor: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.25)
        case .coral: return Color(red: 0.98, green: 0.38, blue: 0.54)
        case .mint: return Color(red: 0.30, green: 0.85, blue: 0.56)
        case .blue: return Color(red: 0.26, green: 0.70, blue: 0.95)
        case .purple: return Color(red: 0.68, green: 0.45, blue: 0.95)
        case .orange: return Color(red: 0.98, green: 0.53, blue: 0.20)
        case .charcoal: return Color(red: 0.12, green: 0.13, blue: 0.15)
        }
    }
    
    public var dotColor: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.82, blue: 0.10)
        case .coral: return Color(red: 1.0, green: 0.35, blue: 0.55)
        case .mint: return Color(red: 0.25, green: 0.85, blue: 0.55)
        case .blue: return Color(red: 0.25, green: 0.72, blue: 0.98)
        case .purple: return Color(red: 0.72, green: 0.45, blue: 0.98)
        case .orange: return Color(red: 1.0, green: 0.55, blue: 0.15)
        case .charcoal: return Color(red: 0.35, green: 0.37, blue: 0.42)
        }
    }
    
    public var textColor: Color {
        switch self {
        case .charcoal: return Color(red: 0.96, green: 0.96, blue: 0.98)
        default: return Color(red: 0.14, green: 0.14, blue: 0.16)
        }
    }
    
    public var nsTextColor: NSColor {
        switch self {
        case .charcoal: return NSColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
        default: return NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
        }
    }
    
    public var secondaryTextColor: Color {
        switch self {
        case .charcoal: return Color(red: 0.65, green: 0.68, blue: 0.75)
        default: return Color(red: 0.35, green: 0.35, blue: 0.40)
        }
    }
    
    public var headerButtonBg: Color {
        switch self {
        case .charcoal: return Color.white.opacity(0.12)
        default: return Color.black.opacity(0.08)
        }
    }
    
    public var borderColor: Color {
        switch self {
        case .charcoal: return Color.white.opacity(0.18)
        default: return Color.black.opacity(0.12)
        }
    }
}

// MARK: - Sticky Note Model
public struct StickyNote: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var content: String
    public var color: StickyNoteColor
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat
    public var isPinnedToDesktop: Bool
    public var isCollapsed: Bool
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        content: String = "",
        color: StickyNoteColor = .yellow,
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 260,
        height: CGFloat = 240,
        isPinnedToDesktop: Bool = true,
        isCollapsed: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.color = color
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.isPinnedToDesktop = isPinnedToDesktop
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Dedicated Panel Subclass
public final class StickyNotePanel: NSPanel {
    public var noteId: UUID?
    
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
}

// MARK: - Service
public final class StickyNotesService: ObservableObject, @unchecked Sendable {
    public static let shared = StickyNotesService()
    
    private let keyEnabled = "switch.stickyNotes.enabled"
    private let keyDefaultColor = "switch.stickyNotes.defaultColor"
    private let keyDefaultPin = "switch.stickyNotes.defaultPin"
    
    @Published public private(set) var notes: [StickyNote] = []
    @Published public private(set) var isVisible: Bool = true
    @Published public var defaultColor: StickyNoteColor = .yellow
    @Published public var defaultPinToDesktop: Bool = true
    
    private var noteWindows: [UUID: StickyNotePanel] = [:]
    private var saveDebounceTimer: Timer?
    
    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent("Switch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var storageFileURL: URL {
        supportDirectory.appendingPathComponent("sticky_notes.json")
    }
    
    public var statusSubtitle: String {
        if !isVisible {
            return "Hidden"
        }
        if notes.isEmpty {
            return "0 notes • Click +"
        }
        let countStr = "\(notes.count) \(notes.count == 1 ? "note" : "notes")"
        let allPinned = notes.allSatisfy { $0.isPinnedToDesktop }
        let allFloating = notes.allSatisfy { !$0.isPinnedToDesktop }
        
        if allPinned {
            return "\(countStr) • On Desktop"
        } else if allFloating {
            return "\(countStr) • Floating"
        } else {
            return countStr
        }
    }
    
    private init() {
        if UserDefaults.standard.object(forKey: keyEnabled) != nil {
            self.isVisible = UserDefaults.standard.bool(forKey: keyEnabled)
        }
        if let rawColor = UserDefaults.standard.string(forKey: keyDefaultColor),
           let col = StickyNoteColor(rawValue: rawColor) {
            self.defaultColor = col
        }
        if UserDefaults.standard.object(forKey: keyDefaultPin) != nil {
            self.defaultPinToDesktop = UserDefaults.standard.bool(forKey: keyDefaultPin)
        }
        
        loadNotes()
        
        // If enabled on startup, display notes after short delay
        if isVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.presentAllNotes()
            }
        }
    }
    
    // MARK: - State & Visibility Controls
    
    public func setVisibility(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        UserDefaults.standard.set(visible, forKey: keyEnabled)
        
        if visible {
            if notes.isEmpty {
                createWelcomeNote()
            } else {
                presentAllNotes()
            }
        } else {
            hideAllNotes()
        }
        
        NotificationCenter.default.post(name: .stickyNotesStateDidChange, object: visible)
    }
    
    public func toggleVisibility() {
        setVisibility(!isVisible)
    }
    
    // MARK: - Note Operations
    
    @discardableResult
    public func createNote(color: StickyNoteColor? = nil, content: String = "") -> StickyNote {
        let chosenColor = color ?? defaultColor
        
        // Calculate a nice default position cascading from top-right
        var origin = NSPoint(x: 100, y: 100)
        if let screen = NSScreen.main {
            let offset = CGFloat((notes.count % 8) * 28)
            let x = screen.visibleFrame.maxX - 290 - offset
            let y = screen.visibleFrame.maxY - 280 - offset
            origin = NSPoint(x: max(screen.visibleFrame.minX + 20, x), y: max(screen.visibleFrame.minY + 20, y))
        }
        
        let newNote = StickyNote(
            id: UUID(),
            content: content,
            color: chosenColor,
            x: origin.x,
            y: origin.y,
            width: 260,
            height: 240,
            isPinnedToDesktop: defaultPinToDesktop,
            isCollapsed: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        notes.append(newNote)
        saveNotesDebounced()
        
        if !isVisible {
            isVisible = true
            UserDefaults.standard.set(true, forKey: keyEnabled)
            NotificationCenter.default.post(name: .stickyNotesStateDidChange, object: true)
        }
        
        presentNoteWindow(for: newNote, makeKey: true)
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: notes.count)
        
        return newNote
    }
    
    public func deleteNote(id: UUID) {
        if let panel = noteWindows[id] {
            panel.orderOut(nil)
            noteWindows.removeValue(forKey: id)
        }
        notes.removeAll(where: { $0.id == id })
        saveNotesDebounced()
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: notes.count)
    }
    
    public func deleteAllNotes() {
        for (_, panel) in noteWindows {
            panel.orderOut(nil)
        }
        noteWindows.removeAll()
        notes.removeAll()
        saveNotesDebounced()
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: 0)
    }
    
    public func updateNoteContent(id: UUID, content: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].content = content
        notes[index].updatedAt = Date()
        saveNotesDebounced()
    }
    
    public func updateNoteColor(id: UUID, color: StickyNoteColor) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].color = color
        notes[index].updatedAt = Date()
        saveNotesDebounced()
        
        // Re-render the window content
        if let panel = noteWindows[id] {
            panel.contentView = NSHostingView(rootView: StickyNoteView(noteId: id))
        }
    }
    
    public func togglePinToDesktop(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinnedToDesktop.toggle()
        let isPinned = notes[index].isPinnedToDesktop
        saveNotesDebounced()
        
        if let panel = noteWindows[id] {
            applyWindowLevel(panel: panel, isPinnedToDesktop: isPinned)
        }
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: notes.count)
    }
    
    public func setPinAllToDesktop(_ pin: Bool) {
        for index in notes.indices {
            notes[index].isPinnedToDesktop = pin
        }
        for (_, panel) in noteWindows {
            applyWindowLevel(panel: panel, isPinnedToDesktop: pin)
        }
        saveNotesDebounced()
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: notes.count)
    }
    
    public func toggleCollapse(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isCollapsed.toggle()
        let isCollapsed = notes[index].isCollapsed
        let targetHeight = notes[index].height
        saveNotesDebounced()
        
        if let panel = noteWindows[id] {
            var currentFrame = panel.frame
            if isCollapsed {
                currentFrame.origin.y += (currentFrame.size.height - 40)
                currentFrame.size.height = 40
            } else {
                let h = max(targetHeight, 200)
                currentFrame.origin.y -= (h - currentFrame.size.height)
                currentFrame.size.height = h
            }
            panel.setFrame(currentFrame, display: true, animate: true)
        }
    }
    
    public func setDefaultColor(_ color: StickyNoteColor) {
        self.defaultColor = color
        UserDefaults.standard.set(color.rawValue, forKey: keyDefaultColor)
    }
    
    public func bringAllToFront() {
        for (_, panel) in noteWindows {
            panel.orderFront(nil)
        }
    }
    
    // MARK: - Window Management
    
    public func presentAllNotes() {
        for note in notes {
            presentNoteWindow(for: note, makeKey: false)
        }
    }
    
    public func hideAllNotes() {
        for (_, panel) in noteWindows {
            panel.orderOut(nil)
        }
    }
    
    private func presentNoteWindow(for note: StickyNote, makeKey: Bool = false) {
        let panel: StickyNotePanel
        if let existing = noteWindows[note.id] {
            panel = existing
        } else {
            panel = createPanel(for: note)
            noteWindows[note.id] = panel
        }
        
        applyWindowLevel(panel: panel, isPinnedToDesktop: note.isPinnedToDesktop)
        
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel.orderFront(nil)
        }
    }
    
    private func createPanel(for note: StickyNote) -> StickyNotePanel {
        let currentH = note.isCollapsed ? 40 : max(note.height, 160)
        let currentW = max(note.width, 180)
        
        var origin = NSPoint(x: note.x, y: note.y)
        // Validate coordinates exist on some screen
        let testRect = NSRect(origin: origin, size: NSSize(width: currentW, height: currentH))
        let isVisibleOnScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(testRect) }
        
        if !isVisibleOnScreen || (origin.x == 0 && origin.y == 0) {
            if let screen = NSScreen.main {
                origin = NSPoint(x: screen.visibleFrame.midX - currentW / 2, y: screen.visibleFrame.midY - currentH / 2)
            }
        }
        
        let panel = StickyNotePanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: currentW, height: currentH)),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        
        panel.noteId = note.id
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 180, height: 140)
        
        applyWindowLevel(panel: panel, isPinnedToDesktop: note.isPinnedToDesktop)
        
        let hostingView = NSHostingView(rootView: StickyNoteView(noteId: note.id))
        panel.contentView = hostingView
        
        // Listen for moves and resizes to persist coordinates
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            guard let self = self, let panel = panel, let id = panel.noteId else { return }
            self.handleWindowMoved(id: id, frame: panel.frame)
        }
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            guard let self = self, let panel = panel, let id = panel.noteId else { return }
            self.handleWindowResized(id: id, frame: panel.frame)
        }
        
        return panel
    }
    
    private func applyWindowLevel(panel: StickyNotePanel, isPinnedToDesktop: Bool) {
        if isPinnedToDesktop {
            // Desktop Mode ("Home Page"): window level sits directly on the desktop
            panel.level = .normal
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        } else {
            // Floating Mode: hovers over other active applications
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }
    
    private func handleWindowMoved(id: UUID, frame: NSRect) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].x = frame.origin.x
        notes[index].y = frame.origin.y
        saveNotesDebounced()
    }
    
    private func handleWindowResized(id: UUID, frame: NSRect) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if !notes[index].isCollapsed {
            notes[index].width = frame.size.width
            notes[index].height = frame.size.height
            saveNotesDebounced()
        }
    }
    
    // MARK: - Welcome Note
    
    private func createWelcomeNote() {
        let welcomeText = """
        ✨ Welcome to Switch Sticky Notes!
        
        • Click the color dots above to change my theme 🎨
        • Click 📌 to pin me to your Desktop (Home Page)
        • Drag me anywhere by my top bar
        • Click + to add new notes
        
        Everything saves automatically!
        """
        createNote(color: .yellow, content: welcomeText)
    }
    
    // MARK: - Disk Persistence
    
    private func saveNotesDebounced() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.saveNotesImmediate()
        }
    }
    
    public func saveNotesImmediate() {
        let itemsToSave = self.notes
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(itemsToSave)
                try data.write(to: self.storageFileURL, options: .atomic)
            } catch {
                print("Failed to save sticky notes: \(error)")
            }
        }
    }
    
    private func loadNotes() {
        guard FileManager.default.fileExists(atPath: storageFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageFileURL)
            let loaded = try JSONDecoder().decode([StickyNote].self, from: data)
            self.notes = loaded
        } catch {
            print("Failed to load sticky notes: \(error)")
        }
    }
}
