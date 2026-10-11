import Cocoa
import Foundation
import Vision
import Combine
import SwiftUI

public extension Notification.Name {
    static let textGrabberStateDidChange = Notification.Name("SwitchTextGrabberStateDidChange")
}

public final class TextGrabberService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = TextGrabberService()
    
    private let keyEnabled = "Switch_TextGrabber_Enabled"
    private let keySingleLine = "Switch_TextGrabber_SingleLine"
    private let keyRecentSnippets = "Switch_TextGrabber_RecentSnippets"
    
    @Published public private(set) var isEnabled: Bool = true
    @Published public private(set) var isSnapping: Bool = false
    @Published public private(set) var lastRecognizedText: String = ""
    @Published public var singleLineMode: Bool = false {
        didSet {
            UserDefaults.standard.set(singleLineMode, forKey: keySingleLine)
        }
    }
    @Published public private(set) var recentSnippets: [String] = []
    
    @Published public private(set) var statusSubtitle: String = "Tap to Copy Text"
    
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var toastPanel: NSPanel?
    private var toastDismissWorkItem: DispatchWorkItem?
    
    private override init() {
        super.init()
        
        let savedEnabled = UserDefaults.standard.object(forKey: keyEnabled) != nil
            ? UserDefaults.standard.bool(forKey: keyEnabled)
            : true
        self.isEnabled = savedEnabled
        
        self.singleLineMode = UserDefaults.standard.bool(forKey: keySingleLine)
        self.recentSnippets = UserDefaults.standard.stringArray(forKey: keyRecentSnippets) ?? []
        
        if let last = recentSnippets.first, !last.isEmpty {
            self.lastRecognizedText = last
            self.statusSubtitle = "Ready · ⌘⌥C"
        }
        
        setupHotkeys()
    }
    
    deinit {
        removeHotkeys()
        toastPanel?.close()
    }
    
    // MARK: - Hotkeys (⌘⌥C or ⌘⇧2)
    
    private func setupHotkeys() {
        removeHotkeys()
        guard isEnabled else { return }
        
        // Listen globally for ⌘⌥C (Command + Option + C)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }
    }
    
    private func removeHotkeys() {
        if let gm = globalKeyMonitor {
            NSEvent.removeMonitor(gm)
            globalKeyMonitor = nil
        }
        if let lm = localKeyMonitor {
            NSEvent.removeMonitor(lm)
            localKeyMonitor = nil
        }
    }
    
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard isEnabled else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // ⌘⌥C (Command + Option + C)
        if flags.contains([.command, .option]) && event.keyCode == 8 { // 8 = 'C'
            snipAreaAndCopyText()
            return true
        }
        
        return false
    }
    
    // MARK: - Toggle / State
    
    public func toggle() {
        setEnabled(!isEnabled)
    }
    
    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: keyEnabled)
        
        if enabled {
            setupHotkeys()
            statusSubtitle = "Ready · ⌘⌥C"
        } else {
            removeHotkeys()
            statusSubtitle = "Disabled"
        }
        
        NotificationCenter.default.post(name: .textGrabberStateDidChange, object: enabled)
    }
    
    // MARK: - Snip & Copy Text Execution
    
    public func snipAreaAndCopyText() {
        performCapture(fullScreen: false)
    }
    
    public func snipFullScreenAndCopyText() {
        performCapture(fullScreen: true)
    }
    
    private func performCapture(fullScreen: Bool) {
        guard !isSnapping else { return }
        isSnapping = true
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            let tempDir = NSTemporaryDirectory()
            let tempFile = "\(tempDir)switch_ocr_\(UUID().uuidString).png"
            
            // Invoke screencapture
            let cmd: String
            if fullScreen {
                cmd = "/usr/sbin/screencapture -x \"\(tempFile)\" 2>/dev/null"
            } else {
                // Interactive selection with crosshairs (-i), muted (-x)
                cmd = "/usr/sbin/screencapture -i -x \"\(tempFile)\" 2>/dev/null"
            }
            
            _ = Shell.run(cmd)
            
            defer {
                DispatchQueue.main.async {
                    self.isSnapping = false
                }
                // Cleanup temp file
                try? FileManager.default.removeItem(atPath: tempFile)
            }
            
            // Check if file was captured (user might have pressed ESC to cancel)
            guard FileManager.default.fileExists(atPath: tempFile),
                  let image = NSImage(contentsOfFile: tempFile),
                  let cgImage = self.cgImage(from: image) else {
                return
            }
            
            // Perform OCR via Vision Framework
            self.extractText(from: cgImage)
        }
    }
    
    // MARK: - Vision OCR
    
    private func extractText(from cgImage: CGImage) {
        let request = VNRecognizeTextRequest { [weak self] (req, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("TextGrabber Vision OCR error: \(error)")
                DispatchQueue.main.async {
                    self.showToast(title: "Recognition Error", text: error.localizedDescription, isSuccess: false)
                }
                return
            }
            
            guard let observations = req.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                DispatchQueue.main.async {
                    self.showToast(title: "No Text Found", text: "No recognizable text found in the selected area.", isSuccess: false)
                }
                return
            }
            
            // Extract top candidates
            let recognizedLines = observations.compactMap { obs in
                obs.topCandidates(1).first?.string
            }
            
            guard !recognizedLines.isEmpty else {
                DispatchQueue.main.async {
                    self.showToast(title: "No Text Found", text: "No recognizable text found in the selected area.", isSuccess: false)
                }
                return
            }
            
            // Format text
            let finalString: String
            if self.singleLineMode {
                finalString = recognizedLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                finalString = recognizedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            guard !finalString.isEmpty else { return }
            
            DispatchQueue.main.async {
                self.handleRecognizedText(finalString)
            }
        }
        
        // Configure Vision request for maximum accuracy
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [
            "en-US", "es-ES", "fr-FR", "de-DE", "it-IT",
            "pt-BR", "zh-Hans", "zh-Hant", "ja", "ko", "ru"
        ]
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform OCR request: \(error)")
        }
    }
    
    private func handleRecognizedText(_ text: String) {
        // Copy to system clipboard
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        
        // Save to recent snippets
        self.lastRecognizedText = text
        var list = self.recentSnippets.filter { $0 != text }
        list.insert(text, at: 0)
        if list.count > 10 {
            list = Array(list.prefix(10))
        }
        self.recentSnippets = list
        UserDefaults.standard.set(list, forKey: keyRecentSnippets)
        
        // Update subtitle
        let count = text.count
        self.statusSubtitle = "Copied (\(count) chars)"
        NotificationCenter.default.post(name: .textGrabberStateDidChange, object: nil)
        
        // Play subtle copy feedback sound
        NSSound(named: "Tink")?.play()
        
        // Show stylish floating HUD
        showToast(title: "✓ Copied to Clipboard", text: text, isSuccess: true)
    }
    
    // MARK: - Floating Toast Notification
    
    private func showToast(title: String, text: String, isSuccess: Bool) {
        toastDismissWorkItem?.cancel()
        
        if toastPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 72),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.sharingType = .none // Exclude from screen recordings
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            self.toastPanel = panel
        }
        
        guard let panel = toastPanel else { return }
        
        panel.contentView = NSHostingView(
            rootView: TextGrabToastView(
                title: title,
                text: text,
                isSuccess: isSuccess,
                onTap: { [weak self] in
                    if isSuccess {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                    }
                    self?.toastPanel?.orderOut(nil)
                }
            )
        )
        
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - 170
            let y = screen.visibleFrame.maxY - 90
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
        
        let workItem = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self?.toastPanel?.animator().alphaValue = 0.0
            }, completionHandler: {
                self?.toastPanel?.orderOut(nil)
                self?.toastPanel?.alphaValue = 1.0
            })
        }
        self.toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: workItem)
    }
    
    // MARK: - CGImage Helper
    
    private func cgImage(from nsImage: NSImage) -> CGImage? {
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.cgImage
    }
    
    public func clearHistory() {
        self.recentSnippets.removeAll()
        UserDefaults.standard.removeObject(forKey: keyRecentSnippets)
        self.statusSubtitle = "History Cleared"
        NotificationCenter.default.post(name: .textGrabberStateDidChange, object: nil)
    }
    
    public func copySnippet(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        showToast(title: "✓ Copied Again", text: text, isSuccess: true)
    }
}

// MARK: - Floating Toast UI

public struct TextGrabToastView: View {
    let title: String
    let text: String
    let isSuccess: Bool
    let onTap: () -> Void
    
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSuccess ? Color(red: 0.15, green: 0.65, blue: 1.0).opacity(0.2) : Color.red.opacity(0.2))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: isSuccess ? "text.viewfinder" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isSuccess ? Color(red: 0.25, green: 0.75, blue: 1.0) : Color.red)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(text.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.8))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                
                Spacer(minLength: 4)
                
                if isSuccess {
                    Text("\(text.count)c")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSuccess ? Color(red: 0.25, green: 0.75, blue: 1.0).opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
    }
}
