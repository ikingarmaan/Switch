import Cocoa
import CoreGraphics
import SwiftUI

public extension Notification.Name {
    static let keyboardLockDidChange = Notification.Name("SwitchKeyboardLockDidChange")
}

public final class KeyboardLockService: @unchecked Sendable {
    public static let shared = KeyboardLockService()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hudWindow: NSPanel?
    
    public private(set) var isLocked: Bool = false
    
    private init() {}
    
    @MainActor
    public func setLocked(_ locked: Bool) {
        if locked {
            lock()
        } else {
            unlock()
        }
    }
    
    @MainActor
    public func lock() {
        guard !isLocked else { return }
        
        let isTrusted = AXIsProcessTrusted()
        if !isTrusted {
            let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
            let options = [checkOptPrompt: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            
            // Also present a user-friendly alert
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "To lock the keyboard, Switch needs Accessibility permission.\n\nPlease enable Switch in System Settings > Privacy & Security > Accessibility."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            
            NotificationCenter.default.post(name: .keyboardLockDidChange, object: false)
            return
        }
        
        // If tap already exists, just re-enable it without recreating mach ports
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            self.isLocked = true
            showHUD()
            NotificationCenter.default.post(name: .keyboardLockDidChange, object: true)
            return
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << 14) // Power button
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout {
                    if let tap = KeyboardLockService.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return nil
                }
                return nil
            },
            userInfo: nil
        ) else {
            print("Failed to create keyboard event tap")
            NotificationCenter.default.post(name: .keyboardLockDidChange, object: false)
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        self.isLocked = true
        showHUD()
        NotificationCenter.default.post(name: .keyboardLockDidChange, object: true)
    }
    
    @MainActor
    public func unlock() {
        guard isLocked else { return }
        self.isLocked = false
        
        // Safely disable event tap without destroying ports or run loop sources
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        hideHUD()
        NotificationCenter.default.post(name: .keyboardLockDidChange, object: false)
    }
    
    // MARK: - Floating Unlock Banner HUD
    
    @MainActor
    private func setupHUDIfNeeded() {
        if hudWindow != nil { return }
        
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let width: CGFloat = 340
        let height: CGFloat = 54
        let x = screenRect.midX - (width / 2)
        let y = screenRect.minY + 60
        
        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hudView = NSHostingView(rootView: KeyboardLockHUDView { [weak self] in
            DispatchQueue.main.async {
                self?.unlock()
            }
        })
        
        panel.contentView = hudView
        self.hudWindow = panel
    }
    
    @MainActor
    private func showHUD() {
        setupHUDIfNeeded()
        hudWindow?.orderFrontRegardless()
    }
    
    @MainActor
    private func hideHUD() {
        hudWindow?.orderOut(nil)
    }
}

// MARK: - HUD SwiftUI View

private struct KeyboardLockHUDView: View {
    var onUnlock: () -> Void
    
    var body: some View {
        Button(action: {
            DispatchQueue.main.async {
                onUnlock()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.yellow)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keyboard Locked")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Click here or toggle in Switch to unlock")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.75))
                }
                
                Spacer()
                
                Text("Unlock")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.yellow))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95))
            )
            .overlay(
                Capsule()
                    .stroke(Color.yellow.opacity(0.6), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
