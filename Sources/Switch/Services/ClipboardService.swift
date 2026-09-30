import Foundation
import Cocoa
import SwiftUI
import Combine
import CryptoKit

public extension Notification.Name {
    static let clipboardStateDidChange = Notification.Name("SwitchClipboardStateDidChange")
    static let clipboardItemsDidChange = Notification.Name("SwitchClipboardItemsDidChange")
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
    
    @Published public private(set) var isEnabled: Bool = true
    @Published public var autoPaste: Bool = true
    @Published public private(set) var items: [ClipboardItem] = []
    @Published public private(set) var isWindowVisible: Bool = false
    
    // In-memory thumbnail cache
    private var thumbnailCache: [UUID: NSImage] = [:]
    
    // Polling & Key monitoring
    private var pollTimer: Timer?
    private var lastChangeCount: Int = -1
    private var isSelfCopying: Bool = false
    
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var lastF9Time: TimeInterval = 0
    
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
            return "\(items.count) items · F9 x2"
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
        
        startKeyMonitoring()
    }
    
    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        stopKeyMonitoring()
    }
    
    // MARK: - F9 Double-Tap Shortcut
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    public var isStandardFunctionKeysEnabled: Bool {
        let val = Shell.run("defaults read -g com.apple.keyboard.fnState 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        return val == "1" || val == "true"
    }
    
    public func setStandardFunctionKeys(_ enabled: Bool) {
        _ = Shell.run("defaults write -g com.apple.keyboard.fnState -bool \(enabled)")
    }
    
    private func startKeyMonitoring() {
        stopKeyMonitoring()
        
        // 1. Install Event Tap (captures both standard F9 and physical F9 media key, consuming on trigger)
        installEventTap()
        
        // 2. Global event monitor (matching KeyDown and SystemDefined media keys)
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
    }
    
    private func stopKeyMonitoring() {
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
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
    
    private var localEventMonitor: Any? {
        get { localKeyMonitor }
        set { localKeyMonitor = newValue }
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
        // Standard virtual keycode 101
        if event.type == .keyDown && event.keyCode == 101 {
            return true
        }
        
        // Media key for F9 (Fast-Forward 19, Next Track 17) when Fn is NOT pressed
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
            // Double press F9!
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
        NSSound(named: "Tink")?.play()
        
        // Close clipboard window
        closeWindow()
        
        // Optional Auto-Paste simulation via ⌘V
        if autoPaste && autoPasteIfEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.simulatePasteShortcut()
            }
        }
    }
    
    public func simulatePasteShortcut() {
        guard AXIsProcessTrusted() else { return }
        
        let src = CGEventSource(stateID: .combinedSessionState)
        // 9 is kVK_ANSI_V
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
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
        
        // Position window: check for saved user-dragged position, otherwise near the searchbar (top right)
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
