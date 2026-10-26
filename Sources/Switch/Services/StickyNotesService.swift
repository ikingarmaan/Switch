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

// MARK: - Text Alignment
public enum StickyNoteTextAlignment: String, Codable, CaseIterable, Identifiable, Sendable {
    case left
    case center
    case right
    
    public var id: String { rawValue }
    
    public var textAlignment: TextAlignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
    
    public var icon: String {
        switch self {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
    
    public var title: String {
        switch self {
        case .left: return "Align Left"
        case .center: return "Align Center"
        case .right: return "Align Right"
        }
    }
}

// MARK: - Font Size
public enum StickyNoteFontSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case regular
    case large
    
    public var id: String { rawValue }
    
    public var pointSize: CGFloat {
        switch self {
        case .small: return 12.0
        case .regular: return 13.5
        case .large: return 16.5
        }
    }
    
    public var label: String {
        switch self {
        case .small: return "S"
        case .regular: return "M"
        case .large: return "L"
        }
    }
    
    public var title: String {
        switch self {
        case .small: return "Small"
        case .regular: return "Normal"
        case .large: return "Large"
        }
    }
}

// MARK: - Checklist Item
public struct StickyChecklistItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    
    public init(id: UUID = UUID(), title: String = "", isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
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
    public var textAlignment: StickyNoteTextAlignment
    public var fontSize: StickyNoteFontSize
    public var isChecklistMode: Bool
    public var checklistItems: [StickyChecklistItem]
    public var isClosed: Bool
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
        textAlignment: StickyNoteTextAlignment = .left,
        fontSize: StickyNoteFontSize = .regular,
        isChecklistMode: Bool = false,
        checklistItems: [StickyChecklistItem] = [],
        isClosed: Bool = false,
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
        self.textAlignment = textAlignment
        self.fontSize = fontSize
        self.isChecklistMode = isChecklistMode
        self.checklistItems = checklistItems
        self.isClosed = isClosed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.color = try container.decodeIfPresent(StickyNoteColor.self, forKey: .color) ?? .yellow
        self.x = try container.decodeIfPresent(CGFloat.self, forKey: .x) ?? 100
        self.y = try container.decodeIfPresent(CGFloat.self, forKey: .y) ?? 100
        self.width = try container.decodeIfPresent(CGFloat.self, forKey: .width) ?? 260
        self.height = try container.decodeIfPresent(CGFloat.self, forKey: .height) ?? 240
        self.isPinnedToDesktop = try container.decodeIfPresent(Bool.self, forKey: .isPinnedToDesktop) ?? true
        self.isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        self.textAlignment = try container.decodeIfPresent(StickyNoteTextAlignment.self, forKey: .textAlignment) ?? .left
        self.fontSize = try container.decodeIfPresent(StickyNoteFontSize.self, forKey: .fontSize) ?? .regular
        self.isChecklistMode = try container.decodeIfPresent(Bool.self, forKey: .isChecklistMode) ?? false
        self.checklistItems = try container.decodeIfPresent([StickyChecklistItem].self, forKey: .checklistItems) ?? []
        self.isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

// MARK: - Dedicated Panel Subclass
public final class StickyNotePanel: NSPanel {
    public var noteId: UUID?
    
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            if !isKeyWindow {
                makeKeyAndOrderFront(nil)
            }
        }
        super.sendEvent(event)
    }
    
    public override func performClose(_ sender: Any?) {
        if let id = noteId {
            StickyNotesService.shared.closeNote(id: id)
        } else {
            orderOut(sender)
        }
    }
}

// MARK: - Service
public final class StickyNotesService: ObservableObject, @unchecked Sendable {
    public static let shared = StickyNotesService()
    
    private let keyEnabled = "switch.stickyNotes.enabled"
    private let keyDefaultColor = "switch.stickyNotes.defaultColor"
    private let keyDefaultPin = "switch.stickyNotes.defaultPin"
    private let userDefaultsBackupKey = "switch.stickyNotes.snapshotBackup"
    
    @Published public private(set) var notes: [StickyNote] = []
    @Published public private(set) var isVisible: Bool = true
    @Published public var defaultColor: StickyNoteColor = .yellow
    @Published public var defaultPinToDesktop: Bool = true
    
    public var activeNotes: [StickyNote] {
        notes.filter { !$0.isClosed }
    }
    
    public var closedNotes: [StickyNote] {
        notes.filter { $0.isClosed }
    }
    
    private var noteWindows: [UUID: StickyNotePanel] = [:]
    private var saveDebounceTimer: Timer?
    private var hasLoadedNotesSuccessfully: Bool = false
    private var lastSnapshotBackupTime: Date = Date.distantPast
    
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
    
    private var archiveFileURL: URL {
        supportDirectory.appendingPathComponent("sticky_notes_permanent_archive.json")
    }
    
    private var backupsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("StickyNotesBackups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    public var statusSubtitle: String {
        if !isVisible {
            return "Hidden"
        }
        let active = activeNotes
        if active.isEmpty {
            let closed = closedNotes
            if !closed.isEmpty {
                return "\(closed.count) saved • Click +"
            }
            return "0 notes • Click +"
        }
        let countStr = "\(active.count) \(active.count == 1 ? "note" : "notes")"
        let allPinned = active.allSatisfy { $0.isPinnedToDesktop }
        let allFloating = active.allSatisfy { !$0.isPinnedToDesktop }
        
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
            if activeNotes.isEmpty {
                if !closedNotes.isEmpty {
                    reopenAllNotes()
                } else if notes.isEmpty {
                    createWelcomeNote()
                }
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
    
    @discardableResult
    public func createNote(
        color: StickyNoteColor? = nil,
        content: String = "",
        isChecklist: Bool = false,
        checklistItems: [StickyChecklistItem] = [],
        alignment: StickyNoteTextAlignment = .left,
        fontSize: StickyNoteFontSize = .regular
    ) -> StickyNote {
        let chosenColor = color ?? defaultColor
        
        // Calculate a nice default position cascading from top-right
        var origin = NSPoint(x: 100, y: 100)
        if let screen = NSScreen.main {
            let offset = CGFloat((activeNotes.count % 8) * 28)
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
            textAlignment: alignment,
            fontSize: fontSize,
            isChecklistMode: isChecklist,
            checklistItems: checklistItems,
            isClosed: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        notes.append(newNote)
        saveNotesImmediate()
        
        if !isVisible {
            isVisible = true
            UserDefaults.standard.set(true, forKey: keyEnabled)
            NotificationCenter.default.post(name: .stickyNotesStateDidChange, object: true)
        }
        
        presentNoteWindow(for: newNote, makeKey: true)
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: activeNotes.count)
        
        return newNote
    }
    
    // MARK: - Safe Retention Actions (Never Delete Any Notes!)
    
    public func closeNote(id: UUID) {
        if let panel = noteWindows[id] {
            panel.orderOut(nil)
            noteWindows.removeValue(forKey: id)
        }
        if let index = notes.firstIndex(where: { $0.id == id }) {
            notes[index].isClosed = true
            notes[index].updatedAt = Date()
        }
        saveNotesImmediate()
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: activeNotes.count)
    }
    
    public func closeAllNotes() {
        for (_, panel) in noteWindows {
            panel.orderOut(nil)
        }
        noteWindows.removeAll()
        for index in notes.indices {
            notes[index].isClosed = true
            notes[index].updatedAt = Date()
        }
        saveNotesImmediate()
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: 0)
    }
    
    public func reopenNote(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isClosed = false
        notes[index].updatedAt = Date()
        saveNotesImmediate()
        
        if !isVisible {
            isVisible = true
            UserDefaults.standard.set(true, forKey: keyEnabled)
            NotificationCenter.default.post(name: .stickyNotesStateDidChange, object: true)
        }
        
        presentNoteWindow(for: notes[index], makeKey: true)
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: activeNotes.count)
    }
    
    public func reopenAllNotes() {
        for index in notes.indices {
            notes[index].isClosed = false
            notes[index].updatedAt = Date()
        }
        saveNotesImmediate()
        
        if !isVisible {
            isVisible = true
            UserDefaults.standard.set(true, forKey: keyEnabled)
            NotificationCenter.default.post(name: .stickyNotesStateDidChange, object: true)
        }
        
        presentAllNotes()
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: activeNotes.count)
    }
    
    // Closing a note hides it from the screen but preserves 100% of its content and history
    public func deleteNote(id: UUID) {
        closeNote(id: id)
    }
    
    // Dedicated explicit permanent deletion (triggered ONLY by the separate Delete button)
    public func deleteNotePermanently(id: UUID) {
        if let panel = noteWindows[id] {
            panel.orderOut(nil)
            noteWindows.removeValue(forKey: id)
        }
        notes.removeAll(where: { $0.id == id })
        saveNotesImmediate()
        NotificationCenter.default.post(name: .stickyNotesCountDidChange, object: activeNotes.count)
    }
    
    public func deleteAllNotes() {
        closeAllNotes()
    }
    
    public func openBackupsFolderInFinder() {
        let dir = supportDirectory
        NSWorkspace.shared.selectFile(storageFileURL.path, inFileViewerRootedAtPath: dir.path)
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
    }
    
    public func setTextAlignment(id: UUID, alignment: StickyNoteTextAlignment) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].textAlignment = alignment
        notes[index].updatedAt = Date()
        saveNotesDebounced()
    }
    
    public func setFontSize(id: UUID, fontSize: StickyNoteFontSize) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].fontSize = fontSize
        notes[index].updatedAt = Date()
        saveNotesDebounced()
    }
    
    public func toggleChecklistMode(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let nowChecklist = !notes[index].isChecklistMode
        notes[index].isChecklistMode = nowChecklist
        
        if nowChecklist {
            // Convert plain text into checklist items
            if notes[index].checklistItems.isEmpty {
                let lines = notes[index].content.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if lines.isEmpty {
                    notes[index].checklistItems = [StickyChecklistItem(title: "", isCompleted: false)]
                } else {
                    notes[index].checklistItems = lines.map { line in
                        let isDone = line.hasPrefix("[x] ") || line.hasPrefix("✓ ") || line.hasPrefix("✔ ")
                        let clean = line
                            .replacingOccurrences(of: "[x] ", with: "")
                            .replacingOccurrences(of: "[ ] ", with: "")
                            .replacingOccurrences(of: "✓ ", with: "")
                            .replacingOccurrences(of: "✔ ", with: "")
                            .replacingOccurrences(of: "• ", with: "")
                            .replacingOccurrences(of: "- ", with: "")
                        return StickyChecklistItem(title: clean, isCompleted: isDone)
                    }
                }
            }
        } else {
            // Convert checklist items into plain text
            let lines = notes[index].checklistItems.map { item in
                (item.isCompleted ? "[x] " : "[ ] ") + item.title
            }
            notes[index].content = lines.joined(separator: "\n")
        }
        notes[index].updatedAt = Date()
        saveNotesDebounced()
    }
    
    public func addChecklistItem(noteId: UUID, afterItemId: UUID? = nil) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteId }) else { return }
        let newItem = StickyChecklistItem()
        if let afterId = afterItemId, let itemIndex = notes[noteIndex].checklistItems.firstIndex(where: { $0.id == afterId }) {
            notes[noteIndex].checklistItems.insert(newItem, at: itemIndex + 1)
        } else {
            notes[noteIndex].checklistItems.append(newItem)
        }
        notes[noteIndex].updatedAt = Date()
        saveNotesDebounced()
    }
    
    public func updateChecklistItem(noteId: UUID, itemId: UUID, title: String? = nil, isCompleted: Bool? = nil) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = notes[noteIndex].checklistItems.firstIndex(where: { $0.id == itemId })
        else { return }
        if let t = title { notes[noteIndex].checklistItems[itemIndex].title = t }
        if let c = isCompleted { notes[noteIndex].checklistItems[itemIndex].isCompleted = c }
        notes[noteIndex].updatedAt = Date()
        saveNotesDebounced()
    }
    
    public func deleteChecklistItem(noteId: UUID, itemId: UUID) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[noteIndex].checklistItems.removeAll(where: { $0.id == itemId })
        if notes[noteIndex].checklistItems.isEmpty {
            notes[noteIndex].checklistItems.append(StickyChecklistItem())
        }
        notes[noteIndex].updatedAt = Date()
        saveNotesDebounced()
    }
    
    public func clearCompletedChecklistItems(noteId: UUID) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[noteIndex].checklistItems.removeAll(where: { $0.isCompleted })
        if notes[noteIndex].checklistItems.isEmpty {
            notes[noteIndex].checklistItems.append(StickyChecklistItem())
        }
        notes[noteIndex].updatedAt = Date()
        saveNotesDebounced()
    }
    
    public func insertBulletPoint(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if notes[index].content.isEmpty {
            notes[index].content = "• "
        } else {
            notes[index].content += "\n• "
        }
        notes[index].updatedAt = Date()
        saveNotesDebounced()
    }
    
    public func insertCurrentDate(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let stamp = "[\(formatter.string(from: Date()))] "
        if notes[index].content.isEmpty {
            notes[index].content = stamp
        } else {
            notes[index].content += "\n" + stamp
        }
        notes[index].updatedAt = Date()
        saveNotesDebounced()
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
    
    /// Opens and ensures sticky notes are shown and brought to front.
    /// If none are currently open, reopens closed notes or creates a fresh one.
    public func openAndBringNotesToFront(makeKey: Bool = false) {
        if !isVisible {
            setVisibility(true)
        }
        
        if activeNotes.isEmpty {
            if !closedNotes.isEmpty {
                reopenAllNotes()
            } else {
                _ = createNote()
            }
        } else {
            presentAllNotes()
            bringAllToFront()
        }
        
        if makeKey, let firstActive = activeNotes.first, let panel = noteWindows[firstActive.id] {
            panel.makeKeyAndOrderFront(nil)
        }
    }
    
    // MARK: - Window Management
    
    public func presentAllNotes() {
        for note in activeNotes {
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
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.noteId = note.id
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = false
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
    
    // MARK: - Welcome Note (Safe Guarded)
    
    private func createWelcomeNote() {
        guard notes.isEmpty else { return }
        // Never overwrite if existing notes exist anywhere
        if FileManager.default.fileExists(atPath: storageFileURL.path) ||
           FileManager.default.fileExists(atPath: archiveFileURL.path) ||
           UserDefaults.standard.object(forKey: userDefaultsBackupKey) != nil {
            return
        }
        
        let welcomeItems = [
            StickyChecklistItem(title: "Welcome to Sticky Notes! 🎨", isCompleted: true),
            StickyChecklistItem(title: "Click checkbox to mark done ☑️", isCompleted: false),
            StickyChecklistItem(title: "Click ≡ in format bar for Left/Center/Right alignment", isCompleted: false),
            StickyChecklistItem(title: "Click 📌 to pin to Desktop (Home Page)", isCompleted: false),
            StickyChecklistItem(title: "Your notes are permanently safe & never deleted", isCompleted: false)
        ]
        createNote(
            color: .yellow,
            content: "",
            isChecklist: true,
            checklistItems: welcomeItems,
            alignment: .left,
            fontSize: .regular
        )
    }
    
    // MARK: - Multi-Tier Disk & Backup Persistence
    
    private func saveNotesDebounced() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.saveNotesImmediate()
        }
    }
    
    public func saveNotesImmediate() {
        let itemsToSave = self.notes
        
        // CRITICAL PROTECTION: Never overwrite existing disk file with empty data if loading failed
        if itemsToSave.isEmpty && !self.hasLoadedNotesSuccessfully {
            return
        }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                let data = try encoder.encode(itemsToSave)
                
                // 1. Primary storage file (atomic write)
                try data.write(to: self.storageFileURL, options: .atomic)
                
                // 2. Permanent archive mirror (atomic write)
                try data.write(to: self.archiveFileURL, options: .atomic)
                
                // 3. System Preferences snapshot backup (UserDefaults)
                UserDefaults.standard.set(data, forKey: self.userDefaultsBackupKey)
                
                // 4. Timestamped rolling backup if notes exist and > 5 mins since last snapshot
                if !itemsToSave.isEmpty && Date().timeIntervalSince(self.lastSnapshotBackupTime) > 300 {
                    self.lastSnapshotBackupTime = Date()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyyMMdd_HHmmss"
                    let backupFileName = "sticky_notes_\(formatter.string(from: Date())).json"
                    let backupFileURL = self.backupsDirectory.appendingPathComponent(backupFileName)
                    try? data.write(to: backupFileURL, options: .atomic)
                    
                    self.pruneOldBackups()
                }
            } catch {
                print("Failed to save sticky notes: \(error)")
            }
        }
    }
    
    private func pruneOldBackups() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        if jsonFiles.count > 100 {
            let sorted = jsonFiles.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return d1 < d2
            }
            for file in sorted.prefix(jsonFiles.count - 100) {
                try? fm.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Resilient Multi-Tier Loader
    
    private func loadNotes() {
        // Priority 1: Primary storage file
        if let loaded = readNotesFromFile(url: storageFileURL), !loaded.isEmpty {
            self.notes = loaded
            self.hasLoadedNotesSuccessfully = true
            return
        }
        
        // Priority 2: Permanent mirror archive file
        if let loaded = readNotesFromFile(url: archiveFileURL), !loaded.isEmpty {
            self.notes = loaded
            self.hasLoadedNotesSuccessfully = true
            saveNotesImmediate()
            return
        }
        
        // Priority 3: Scan latest valid backup from StickyNotesBackups/
        if let backup = findLatestValidBackup(), let loaded = readNotesFromFile(url: backup), !loaded.isEmpty {
            self.notes = loaded
            self.hasLoadedNotesSuccessfully = true
            saveNotesImmediate()
            return
        }
        
        // Priority 4: UserDefaults snapshot
        if let data = UserDefaults.standard.data(forKey: userDefaultsBackupKey),
           let loaded = decodeNotes(from: data), !loaded.isEmpty {
            self.notes = loaded
            self.hasLoadedNotesSuccessfully = true
            saveNotesImmediate()
            return
        }
        
        // Priority 5: Fallback raw dictionary recovery if files exist but decode failed
        if FileManager.default.fileExists(atPath: storageFileURL.path),
           let data = try? Data(contentsOf: storageFileURL),
           let recovered = recoverNotesFromRawJSON(data: data), !recovered.isEmpty {
            self.notes = recovered
            self.hasLoadedNotesSuccessfully = true
            saveNotesImmediate()
            return
        }
        
        self.hasLoadedNotesSuccessfully = true
    }
    
    private func readNotesFromFile(url: URL) -> [StickyNote]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return decodeNotes(from: data) ?? recoverNotesFromRawJSON(data: data)
    }
    
    private func decodeNotes(from data: Data) -> [StickyNote]? {
        if let loaded = try? JSONDecoder().decode([StickyNote].self, from: data) {
            return loaded
        }
        return nil
    }
    
    private func findLatestValidBackup() -> URL? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        let sorted = jsonFiles.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return d1 > d2
        }
        return sorted.first
    }
    
    private func recoverNotesFromRawJSON(data: Data) -> [StickyNote]? {
        guard let rawObj = try? JSONSerialization.jsonObject(with: data, options: []),
              let arr = rawObj as? [[String: Any]] else { return nil }
        
        var recovered: [StickyNote] = []
        for dict in arr {
            let id = UUID(uuidString: dict["id"] as? String ?? "") ?? UUID()
            let content = dict["content"] as? String ?? ""
            let colorStr = dict["color"] as? String ?? "yellow"
            let color = StickyNoteColor(rawValue: colorStr) ?? .yellow
            let x = CGFloat(dict["x"] as? Double ?? 100)
            let y = CGFloat(dict["y"] as? Double ?? 100)
            let width = CGFloat(dict["width"] as? Double ?? 260)
            let height = CGFloat(dict["height"] as? Double ?? 240)
            let isPinned = dict["isPinnedToDesktop"] as? Bool ?? true
            let isCollapsed = dict["isCollapsed"] as? Bool ?? false
            let alignStr = dict["textAlignment"] as? String ?? "left"
            let alignment = StickyNoteTextAlignment(rawValue: alignStr) ?? .left
            let fontStr = dict["fontSize"] as? String ?? "regular"
            let fontSize = StickyNoteFontSize(rawValue: fontStr) ?? .regular
            let isChecklist = dict["isChecklistMode"] as? Bool ?? false
            let isClosed = dict["isClosed"] as? Bool ?? false
            
            var checklistItems: [StickyChecklistItem] = []
            if let rawItems = dict["checklistItems"] as? [[String: Any]] {
                for itemDict in rawItems {
                    let itemId = UUID(uuidString: itemDict["id"] as? String ?? "") ?? UUID()
                    let title = itemDict["title"] as? String ?? ""
                    let isCompleted = itemDict["isCompleted"] as? Bool ?? false
                    checklistItems.append(StickyChecklistItem(id: itemId, title: title, isCompleted: isCompleted))
                }
            }
            
            recovered.append(StickyNote(
                id: id,
                content: content,
                color: color,
                x: x,
                y: y,
                width: width,
                height: height,
                isPinnedToDesktop: isPinned,
                isCollapsed: isCollapsed,
                textAlignment: alignment,
                fontSize: fontSize,
                isChecklistMode: isChecklist,
                checklistItems: checklistItems,
                isClosed: isClosed,
                createdAt: Date(),
                updatedAt: Date()
            ))
        }
        return recovered.isEmpty ? nil : recovered
    }
}
