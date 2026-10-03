import Foundation
import Cocoa
import SwiftUI
import Combine
import CryptoKit
import ApplicationServices

public extension Notification.Name {
    static let clipboardStateDidChange = Notification.Name("SwitchClipboardStateDidChange")
    static let clipboardItemsDidChange = Notification.Name("SwitchClipboardItemsDidChange")
    static let clipboardAutoPastedComment = Notification.Name("SwitchClipboardAutoPastedComment")
}

public enum ClipboardItemType: String, Codable, Sendable {
    case text
    case image
}

public struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let type: ClipboardItemType
    public let textContent: String?
    public let imageFileName: String?
    public let imageWidth: CGFloat?
    public let imageHeight: CGFloat?
    public let byteSize: Int
    public let contentHash: String
    public var createdAt: Date
    
    public init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        textContent: String? = nil,
        imageFileName: String? = nil,
        imageWidth: CGFloat? = nil,
        imageHeight: CGFloat? = nil,
        byteSize: Int,
        contentHash: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.textContent = textContent
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteSize = byteSize
        self.contentHash = contentHash
        self.createdAt = createdAt
    }
    
    public var previewTitle: String {
        switch type {
        case .text:
            guard let text = textContent else { return "Empty text" }
            let line = text.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? text
            return line.trimmingCharacters(in: .whitespaces)
        case .image:
            let w = Int(imageWidth ?? 0)
            let h = Int(imageHeight ?? 0)
            return "Image (\(w) × \(h))"
        }
    }
    
    public var previewSubtitle: String {
        switch type {
        case .text:
            guard let text = textContent else { return "" }
            let charCount = text.count
            let lines = text.components(separatedBy: .newlines).count
            return "\(charCount) chars · \(lines) \(lines == 1 ? "line" : "lines") · \(formattedTime)"
        case .image:
            return "\(formattedSize) · \(formattedTime)"
        }
    }
    
    public var formattedSize: String {
        if byteSize < 1024 {
            return "\(byteSize) B"
        } else if byteSize < 1024 * 1024 {
            return String(format: "%.1f KB", Double(byteSize) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(byteSize) / (1024.0 * 1024.0))
        }
    }
    
    public var formattedTime: String {
        let elapsed = Int(Date().timeIntervalSince(createdAt))
        if elapsed < 60 {
            return "Just now"
        } else if elapsed < 3600 {
            return "\(elapsed / 60)m ago"
        } else if elapsed < 86400 {
            return "\(elapsed / 3600)h ago"
        } else {
            return "\(elapsed / 86400)d ago"
        }
    }
}

public final class ClipboardService: ObservableObject, @unchecked Sendable {
    public static let shared = ClipboardService()
    public static let maxItems = 50
    
    private let keyEnabled = "switch.clipboard.enabled"
    private let keyAutoPaste = "switch.clipboard.autoPaste"
    private let keyAutoPasteOnCommentClick = "switch.clipboard.autoPasteOnCommentClick"
    private let keyAutoPasteCommentOncePerCopy = "switch.clipboard.autoPasteCommentOncePerCopy"
    private let keyAutoPasteSound = "switch.clipboard.autoPasteSound"
    
    @Published public private(set) var isEnabled: Bool = true
    @Published public var autoPaste: Bool = true
    @Published public var autoPasteOnCommentClick: Bool = true
    @Published public var autoPasteCommentOncePerCopy: Bool = true
    @Published public var autoPasteSound: Bool = true
    @Published public private(set) var items: [ClipboardItem] = []
    @Published public private(set) var isWindowVisible: Bool = false
    
    // In-memory thumbnail cache
    private var thumbnailCache: [UUID: NSImage] = [:]
    
    // Polling & Key/Mouse monitoring
    private var pollTimer: Timer?
    private var lastChangeCount: Int = -1
    private var isSelfCopying: Bool = false
    
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var lastF9Time: TimeInterval = 0
    
    // Auto-paste debounce and state
    private var hasAutoPastedCurrentItem: Bool = false
    private var lastAutoPasteTimestamp: TimeInterval = 0
    
    // Window manager
    private var clipboardPanel: NSPanel?
    
    // File paths
    private var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent("Switch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var imagesDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("clipboard_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var historyFileURL: URL {
        supportDirectory.appendingPathComponent("clipboard_history.json")
    }
    
    public var statusSubtitle: String {
        if isEnabled {
            if autoPasteOnCommentClick {
                return "\(items.count) items · Auto-Paste 💬"
            } else {
                return "\(items.count) items · F9 x2"
            }
        } else {
            return "Off"
        }
    }
    
    private init() {
        if UserDefaults.standard.object(forKey: keyEnabled) != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: keyEnabled)
        }
        if UserDefaults.standard.object(forKey: keyAutoPaste) != nil {
            self.autoPaste = UserDefaults.standard.bool(forKey: keyAutoPaste)
        }
        if UserDefaults.standard.object(forKey: keyAutoPasteOnCommentClick) != nil {
            self.autoPasteOnCommentClick = UserDefaults.standard.bool(forKey: keyAutoPasteOnCommentClick)
        } else {
            self.autoPasteOnCommentClick = true
        }
        if UserDefaults.standard.object(forKey: keyAutoPasteCommentOncePerCopy) != nil {
            self.autoPasteCommentOncePerCopy = UserDefaults.standard.bool(forKey: keyAutoPasteCommentOncePerCopy)
        } else {
            self.autoPasteCommentOncePerCopy = true
        }
        if UserDefaults.standard.object(forKey: keyAutoPasteSound) != nil {
            self.autoPasteSound = UserDefaults.standard.bool(forKey: keyAutoPasteSound)
        } else {
            self.autoPasteSound = true
        }
        
        loadHistoryFromDisk()
        
        if isEnabled {
            startMonitoring()
        }
    }
    
    // MARK: - Lifecycle & Settings
    
    public func setEnabled(_ enable: Bool) {
        self.isEnabled = enable
        UserDefaults.standard.set(enable, forKey: keyEnabled)
        
        if enable {
            startMonitoring()
        } else {
            stopMonitoring()
            closeWindow()
        }
        
        NotificationCenter.default.post(name: .clipboardStateDidChange, object: enable)
    }
    
    public func setAutoPaste(_ enable: Bool) {
        self.autoPaste = enable
        UserDefaults.standard.set(enable, forKey: keyAutoPaste)
        objectWillChange.send()
    }
    
    public func setAutoPasteOnCommentClick(_ enable: Bool) {
        self.autoPasteOnCommentClick = enable
        UserDefaults.standard.set(enable, forKey: keyAutoPasteOnCommentClick)
        objectWillChange.send()
        NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
    }
    
    public func setAutoPasteCommentOncePerCopy(_ enable: Bool) {
        self.autoPasteCommentOncePerCopy = enable
        UserDefaults.standard.set(enable, forKey: keyAutoPasteCommentOncePerCopy)
        objectWillChange.send()
    }
    
    public func setAutoPasteSound(_ enable: Bool) {
        self.autoPasteSound = enable
        UserDefaults.standard.set(enable, forKey: keyAutoPasteSound)
        objectWillChange.send()
    }
    
    public func startMonitoring() {
        stopMonitoring()
        
        // Initial change count
        lastChangeCount = NSPasteboard.general.changeCount
        
        // Poll every 0.35s in .common mode so polling runs continuously even when menus or drags are active
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
        
        // Capture initial item if history is empty
        if items.isEmpty {
            captureCurrentClipboard()
        }
        
        startInputMonitoring()
    }
    
    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        stopInputMonitoring()
    }
    
    // MARK: - Input Monitoring (F9 Shortcut & Mouse Clicks)
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    public var isStandardFunctionKeysEnabled: Bool {
        let val = Shell.run("defaults read -g com.apple.keyboard.fnState 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        return val == "1" || val == "true"
    }
    
    public func setStandardFunctionKeys(_ enabled: Bool) {
        _ = Shell.run("defaults write -g com.apple.keyboard.fnState -bool \(enabled)")
    }
    
    private func startInputMonitoring() {
        stopInputMonitoring()
        
        // 1. Install Event Tap for F9
        installEventTap()
        
        // 2. Global event monitor for F9
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            self?.handleNSEvent(event)
        }
        
        // 3. Local key monitor (when Switch or clipboard window is active)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { [weak self] event in
            if self?.isF9Event(event) == true {
                if self?.recordF9Press() == true {
                    return nil
                }
            }
            return event
        }
        
        // 4. Global mouse monitor for comment box detection on click
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.handleGlobalMouseUp(at: NSEvent.mouseLocation)
        }
        
        // 5. Local mouse monitor
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.handleGlobalMouseUp(at: NSEvent.mouseLocation)
            return event
        }
    }
    
    private func stopInputMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }
    
    private func installEventTap() {
        guard AXIsProcessTrusted() else { return }
        if eventTap != nil { return }
        
        // KeyDown (10) and NX_SYSDEFINED (14)
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << 14)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout {
                    if let t = ClipboardService.shared.eventTap {
                        CGEvent.tapEnable(tap: t, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                
                // Virtual Keycode 101 (F9 with Fn or standard F-keys)
                if type == .keyDown {
                    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                    if keycode == 101 {
                        if ClipboardService.shared.recordF9Press() {
                            return nil // consume event on trigger
                        }
                    }
                }
                
                // NX_SYSDEFINED (Media keys: Fast-Forward / Next Track is F9 on Apple keyboards!)
                if type.rawValue == 14 {
                    if let nsEvent = NSEvent(cgEvent: event),
                       nsEvent.type == .systemDefined,
                       nsEvent.subtype.rawValue == 8 {
                        let data = nsEvent.data1
                        let keyCode = Int((data & 0xFFFF0000) >> 16)
                        let keyFlags = data & 0x0000FFFF
                        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
                        let isRepeat = (keyFlags & 0x1) != 0
                        
                        // 19 is NX_KEYTYPE_FAST, 17 is NX_KEYTYPE_NEXT
                        if (keyCode == 19 || keyCode == 17) && isKeyDown && !isRepeat {
                            if ClipboardService.shared.recordF9Press() {
                                return nil // consume event on trigger
                            }
                        }
                    }
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func handleNSEvent(_ event: NSEvent) {
        if isF9Event(event) {
            _ = recordF9Press()
        }
    }
    
    private func isF9Event(_ event: NSEvent) -> Bool {
        if event.type == .keyDown && event.keyCode == 101 {
            return true
        }
        
        if event.type == .systemDefined && event.subtype.rawValue == 8 {
            let data = event.data1
            let keyCode = Int((data & 0xFFFF0000) >> 16)
            let keyFlags = data & 0x0000FFFF
            let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
            let isRepeat = (keyFlags & 0x1) != 0
            if (keyCode == 19 || keyCode == 17) && isKeyDown && !isRepeat {
                return true
            }
        }
        
        return false
    }
    
    @discardableResult
    public func recordF9Press() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = now - lastF9Time
        
        if delta <= 0.70 && delta >= 0.04 {
            lastF9Time = 0
            DispatchQueue.main.async { [weak self] in
                self?.toggleWindow()
            }
            return true
        } else {
            lastF9Time = now
            return false
        }
    }
    
    // MARK: - Comment Box Click Auto-Paste Detection
    
    private func handleGlobalMouseUp(at screenPoint: CGPoint) {
        guard isEnabled, autoPasteOnCommentClick, AXIsProcessTrusted() else { return }
        
        // Ensure clipboard history or pasteboard has an item
        guard let recentItem = items.first ?? fallbackPasteboardItem() else { return }
        
        // If "once per copy" mode is active, do not re-paste until new item is copied
        if autoPasteCommentOncePerCopy && hasAutoPastedCurrentItem {
            return
        }
        
        // Prevent rapid duplicate triggers
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastAutoPasteTimestamp < 1.0 {
            return
        }
        
        // Wait 120ms for target window/app to finish handling the click and placing the caret
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.checkAndAutoPasteComment(at: screenPoint, item: recentItem)
        }
    }
    
    private func checkAndAutoPasteComment(at screenPoint: CGPoint, item: ClipboardItem) {
        guard isEnabled, autoPasteOnCommentClick, AXIsProcessTrusted() else { return }
        if autoPasteCommentOncePerCopy && hasAutoPastedCurrentItem { return }
        
        var isTargetCommentBox = false
        let systemWide = AXUIElementCreateSystemWide()
        
        // 1. Inspect element directly under the mouse click
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? (NSScreen.main?.frame.height ?? 900)
        let axY = primaryScreenHeight - screenPoint.y
        var clickedEl: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemWide, Float(screenPoint.x), Float(axY), &clickedEl) == .success,
           let el = clickedEl {
            if isCommentOrInputBox(el) {
                isTargetCommentBox = true
            }
        }
        
        // 2. If not detected directly at point, inspect the focused element of the frontmost application
        if !isTargetCommentBox, let front = NSWorkspace.shared.frontmostApplication {
            // Skip Switch's own windows
            if front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                return
            }
            let appEl = AXUIElementCreateApplication(front.processIdentifier)
            var focusedEl: AnyObject?
            if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusedEl) == .success,
               let el = focusedEl as! AXUIElement? {
                if isCommentOrInputBox(el) {
                    isTargetCommentBox = true
                }
            }
        }
        
        guard isTargetCommentBox else { return }
        
        // Execute Auto-Paste
        executeCommentBoxAutoPaste(item: item)
    }
    
    private func isCommentOrInputBox(_ element: AXUIElement) -> Bool {
        // Never trigger inside Switch itself
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) == .success, pid == ProcessInfo.processInfo.processIdentifier {
            return false
        }
        
        var roleVal: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal)
        let role = roleVal as? String ?? ""
        
        var subroleVal: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleVal)
        let subrole = subroleVal as? String ?? ""
        
        var descVal: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &descVal)
        let desc = (descVal as? String ?? "").lowercased()
        
        // Filter out non-input structural elements
        if role == "AXWindow" || role == "AXWebArea" || role == "AXScrollArea" ||
           role == "AXScrollBar" || role == "AXMenu" || role == "AXMenuBar" || role == "AXMenuBarItem" {
            return false
        }
        
        // 1. Primary comment box & text field roles
        if role == "AXTextArea" || role == "AXTextField" || role == "AXComboBox" {
            return true
        }
        
        // 2. Rich text & search subroles
        if subrole == "AXRichEdit" || subrole == "AXSearchField" {
            return true
        }
        
        // 3. Descriptive matches for web comment boxes & editors
        if desc.contains("text entry") || desc.contains("text area") || desc.contains("comment") ||
           desc.contains("edit text") || desc.contains("editable") || desc.contains("editor") {
            return true
        }
        
        // 4. Settable value attribute indicates editable input field
        var isSettable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &isSettable) == .success && isSettable.boolValue {
            return true
        }
        
        // 5. Check if element has insertion caret / text selection range
        var selectedRange: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success {
            var rangeSettable: DarwinBoolean = false
            if AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &rangeSettable) == .success && rangeSettable.boolValue {
                return true
            }
        }
        
        // 6. Check parent hierarchy (e.g. placeholder text span, paragraph or div inside a rich comment box)
        if role == "AXStaticText" || role == "AXGroup" || role == "AXGenericElement" || role == "AXParagraph" {
            var curr = element
            for _ in 0..<3 {
                var parentVal: AnyObject?
                if AXUIElementCopyAttributeValue(curr, kAXParentAttribute as CFString, &parentVal) == .success,
                   let parent = parentVal as! AXUIElement? {
                    var pRole: AnyObject?
                    AXUIElementCopyAttributeValue(parent, kAXRoleAttribute as CFString, &pRole)
                    let parentRole = pRole as? String ?? ""
                    if parentRole == "AXTextArea" || parentRole == "AXTextField" {
                        return true
                    }
                    var pSettable: DarwinBoolean = false
                    if AXUIElementIsAttributeSettable(parent, kAXValueAttribute as CFString, &pSettable) == .success && pSettable.boolValue {
                        return true
                    }
                    curr = parent
                } else {
                    break
                }
            }
        }
        
        return false
    }
    
    private func ensurePasteboardHasItem(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        switch item.type {
        case .text:
            if let text = item.textContent, pb.string(forType: .string) != text {
                isSelfCopying = true
                pb.clearContents()
                pb.setString(text, forType: .string)
                lastChangeCount = pb.changeCount
            }
        case .image:
            isSelfCopying = true
            pb.clearContents()
            if let image = loadImage(for: item) {
                pb.writeObjects([image])
            }
            lastChangeCount = pb.changeCount
        }
    }
    
    private func executeCommentBoxAutoPaste(item: ClipboardItem) {
        lastAutoPasteTimestamp = ProcessInfo.processInfo.systemUptime
        hasAutoPastedCurrentItem = true
        
        // Ensure clipboard has this item loaded
        ensurePasteboardHasItem(item)
        
        // Send Command + V
        simulatePasteShortcut()
        
        if autoPasteSound {
            NSSound(named: "Tink")?.play()
        }
        
        NotificationCenter.default.post(name: .clipboardAutoPastedComment, object: item)
    }
    
    private func fallbackPasteboardItem() -> ClipboardItem? {
        let pb = NSPasteboard.general
        if let string = pb.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hash = SHA256.hash(data: Data(string.utf8)).compactMap { String(format: "%02x", $0) }.joined()
            return ClipboardItem(
                type: .text,
                textContent: string,
                byteSize: string.utf8.count,
                contentHash: hash
            )
        }
        return nil
    }
    
    // MARK: - Clipboard Polling
    
    private func checkPasteboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        
        if isSelfCopying {
            isSelfCopying = false
            return
        }
        
        captureCurrentClipboard()
    }
    
    public func captureCurrentClipboard() {
        let pb = NSPasteboard.general
        
        // 1. Check for Image (direct bitmap on pasteboard or copied image file from Finder)
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]
        let hasDirectImage = pb.types?.contains { imageTypes.contains($0) } ?? false
        
        var foundImage: NSImage?
        if hasDirectImage {
            foundImage = NSImage(pasteboard: pb)
        } else if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
                  let firstURL = urls.first,
                  ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff"].contains(firstURL.pathExtension.lowercased()) {
            foundImage = NSImage(contentsOf: firstURL)
        }
        
        if let image = foundImage,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let pngData = rep.representation(using: .png, properties: [:]) {
            
            let hash = SHA256.hash(data: pngData).compactMap { String(format: "%02x", $0) }.joined()
            
            // Check if matches the most recent item
            if let first = items.first, first.type == .image && first.contentHash == hash {
                return
            }
            
            // Check if duplicate exists elsewhere in history -> move to top
            if let existingIndex = items.firstIndex(where: { $0.type == .image && $0.contentHash == hash }) {
                var item = items.remove(at: existingIndex)
                item.createdAt = Date()
                items.insert(item, at: 0)
                hasAutoPastedCurrentItem = false // Rearm auto-paste for refreshed item
                saveHistoryToDisk()
                NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
                return
            }
            
            let id = UUID()
            let fileName = "\(id.uuidString).png"
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            
            do {
                try pngData.write(to: fileURL)
                let newItem = ClipboardItem(
                    id: id,
                    type: .image,
                    textContent: nil,
                    imageFileName: fileName,
                    imageWidth: image.size.width,
                    imageHeight: image.size.height,
                    byteSize: pngData.count,
                    contentHash: hash,
                    createdAt: Date()
                )
                
                thumbnailCache[id] = generateThumbnail(from: image)
                addItem(newItem)
            } catch {
                print("Failed to save clipboard image: \(error)")
            }
            return
        }
        
        // 2. Check for Text
        if let string = pb.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            
            let hash = SHA256.hash(data: Data(string.utf8)).compactMap { String(format: "%02x", $0) }.joined()
            
            // Deduplicate: if matches the top item, ignore
            if let first = items.first, first.type == .text && first.contentHash == hash {
                return
            }
            
            // If already exists in history, move to top
            if let existingIndex = items.firstIndex(where: { $0.type == .text && $0.contentHash == hash }) {
                var item = items.remove(at: existingIndex)
                item.createdAt = Date()
                items.insert(item, at: 0)
                hasAutoPastedCurrentItem = false // Rearm auto-paste for refreshed item
                saveHistoryToDisk()
                NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
                return
            }
            
            let newItem = ClipboardItem(
                id: UUID(),
                type: .text,
                textContent: string,
                imageFileName: nil,
                imageWidth: nil,
                imageHeight: nil,
                byteSize: string.utf8.count,
                contentHash: hash,
                createdAt: Date()
            )
            
            addItem(newItem)
        }
    }
    
    private func addItem(_ item: ClipboardItem) {
        items.insert(item, at: 0)
        hasAutoPastedCurrentItem = false // Fresh item is armed and ready to auto-paste into comment box
        
        // Prune older items beyond maxItems (50)
        while items.count > Self.maxItems {
            let removed = items.removeLast()
            if let fileName = removed.imageFileName {
                deleteImageFile(fileName)
            }
            thumbnailCache.removeValue(forKey: removed.id)
        }
        
        saveHistoryToDisk()
        NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
    }
    
    public func deleteItem(id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            let removed = items.remove(at: index)
            if let fileName = removed.imageFileName {
                deleteImageFile(fileName)
            }
            thumbnailCache.removeValue(forKey: id)
            saveHistoryToDisk()
            NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
        }
    }
    
    public func clearAllHistory() {
        for item in items {
            if let fileName = item.imageFileName {
                deleteImageFile(fileName)
            }
        }
        items.removeAll()
        thumbnailCache.removeAll()
        saveHistoryToDisk()
        NotificationCenter.default.post(name: .clipboardItemsDidChange, object: nil)
    }
    
    private func deleteImageFile(_ fileName: String) {
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Copy & Paste Item
    
    public func copyItemToPasteboard(_ item: ClipboardItem, autoPasteIfEnabled: Bool = true) {
        isSelfCopying = true
        
        let pb = NSPasteboard.general
        pb.clearContents()
        
        switch item.type {
        case .text:
            if let text = item.textContent {
                pb.setString(text, forType: .string)
            }
        case .image:
            if let image = loadImage(for: item) {
                pb.writeObjects([image])
            }
        }
        
        lastChangeCount = pb.changeCount
        hasAutoPastedCurrentItem = false // Rearm auto-paste on manual selection
        NSSound(named: "Tink")?.play()
        
        // Close clipboard window
        closeWindow()
        
        // Optional Auto-Paste simulation via ⌘V on selection
        if autoPaste && autoPasteIfEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.simulatePasteShortcut()
            }
        }
    }
    
    public func simulatePasteShortcut() {
        guard AXIsProcessTrusted() else { return }
        
        let src = CGEventSource(stateID: .combinedSessionState)
        // Keycode 55 = Command, Keycode 9 = V
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        
        Thread.sleep(forTimeInterval: 0.02)
        
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)
        
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: false)
        cmdUp?.flags = []
        cmdUp?.post(tap: .cghidEventTap)
    }
    
    // MARK: - Image Helpers & Cache
    
    public func thumbnail(for item: ClipboardItem) -> NSImage? {
        if let cached = thumbnailCache[item.id] {
            return cached
        }
        if let full = loadImage(for: item) {
            let thumb = generateThumbnail(from: full)
            thumbnailCache[item.id] = thumb
            return thumb
        }
        return nil
    }
    
    public func imageFileURL(for item: ClipboardItem) -> URL? {
        guard let fileName = item.imageFileName else { return nil }
        return imagesDirectory.appendingPathComponent(fileName)
    }
    
    public func loadImage(for item: ClipboardItem) -> NSImage? {
        guard let fileURL = imageFileURL(for: item) else { return nil }
        return NSImage(contentsOf: fileURL)
    }
    
    private func generateThumbnail(from image: NSImage, maxDimension: CGFloat = 160) -> NSImage {
        let size = image.size
        guard size.width > 0 && size.height > 0 else { return image }
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = NSSize(width: max(1, size.width * ratio), height: max(1, size.height * ratio))
        
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }
    
    // MARK: - Disk Persistence
    
    private func saveHistoryToDisk() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            do {
                let data = try JSONEncoder().encode(self.items)
                try data.write(to: self.historyFileURL, options: .atomic)
            } catch {
                print("Failed to save clipboard history: \(error)")
            }
        }
    }
    
    private func loadHistoryFromDisk() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyFileURL)
            let loaded = try JSONDecoder().decode([ClipboardItem].self, from: data)
            self.items = Array(loaded.prefix(Self.maxItems))
        } catch {
            print("Failed to load clipboard history: \(error)")
        }
    }
    
    // MARK: - Floating Clipboard Window
    
    public func toggleWindow() {
        if isWindowVisible {
            closeWindow()
        } else {
            showWindow()
        }
    }
    
    public func showWindow() {
        if clipboardPanel == nil {
            setupClipboardPanel()
        }
        
        guard let panel = clipboardPanel else { return }
        
        positionPanelNearSearchbar(panel)
        
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isWindowVisible = true
    }
    
    private func positionPanelNearSearchbar(_ panel: NSPanel) {
        let rect = panel.frame
        let savedX = UserDefaults.standard.double(forKey: "switch.clipboard.posX")
        let savedY = UserDefaults.standard.double(forKey: "switch.clipboard.posY")
        
        if savedX != 0 && savedY != 0 {
            let candidatePoint = NSPoint(x: savedX, y: savedY)
            let candidateRect = NSRect(origin: candidatePoint, size: rect.size)
            let isVisible = NSScreen.screens.contains { $0.visibleFrame.intersects(candidateRect) }
            if isVisible {
                panel.setFrameOrigin(candidatePoint)
                return
            }
        }
        
        // Default position: near top-right menu bar search icon (Spotlight)
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - rect.width - 20
            let y = screen.visibleFrame.maxY - rect.height - 8
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    public func resetWindowPosition() {
        UserDefaults.standard.removeObject(forKey: "switch.clipboard.posX")
        UserDefaults.standard.removeObject(forKey: "switch.clipboard.posY")
        if let screen = NSScreen.main, let panel = clipboardPanel {
            let rect = panel.frame
            let x = screen.visibleFrame.maxX - rect.width - 20
            let y = screen.visibleFrame.maxY - rect.height - 8
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    public func closeWindow() {
        clipboardPanel?.orderOut(nil)
        isWindowVisible = false
    }
    
    private func setupClipboardPanel() {
        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 340),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.setContentSize(NSSize(width: 310, height: 340))
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.sharingType = .readOnly
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            guard let origin = panel?.frame.origin else { return }
            UserDefaults.standard.set(origin.x, forKey: "switch.clipboard.posX")
            UserDefaults.standard.set(origin.y, forKey: "switch.clipboard.posY")
        }
        
        let hostingView = NSHostingView(
            rootView: ClipboardHistoryView(service: self)
        )
        panel.contentView = hostingView
        self.clipboardPanel = panel
    }
    
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func cancelOperation(_ sender: Any?) {
        ClipboardService.shared.closeWindow()
    }
}
