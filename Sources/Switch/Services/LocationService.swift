import Foundation
import CoreLocation
import Cocoa
import ApplicationServices

public extension Notification.Name {
    static let locationServicesStateDidChange = Notification.Name("SwitchLocationServicesStateDidChange")
}

public final class LocationService: NSObject, ObservableObject, @unchecked Sendable {
    public static let shared = LocationService()
    
    private var pollTimer: Timer?
    private var isToggling: Bool = false
    
    @Published public private(set) var isEnabled: Bool = false
    
    public var statusSubtitle: String {
        if isEnabled {
            return "Enabled · Location Active"
        } else {
            return "Off · Privacy Protected"
        }
    }
    
    private override init() {
        super.init()
        self.isEnabled = CLLocationManager.locationServicesEnabled()
        startMonitoring()
    }
    
    // MARK: - Status Monitoring
    
    @discardableResult
    public func checkStatus() -> Bool {
        let current = CLLocationManager.locationServicesEnabled()
        if current != isEnabled {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isEnabled = current
                NotificationCenter.default.post(name: .locationServicesStateDidChange, object: current)
            }
        }
        return current
    }
    
    public func startMonitoring() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            _ = self?.checkStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
    }
    
    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    // MARK: - Open Settings
    
    public func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Automated Toggle
    
    public func toggle(targetState: Bool? = nil) {
        guard !isToggling else { return }
        isToggling = true
        
        let desiredState = targetState ?? !isEnabled
        let wasRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first != nil
        
        // Open Location Services pane
        openLocationSettings()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                self?.isToggling = false
            }
            
            // Wait for System Settings application to launch and activate
            let deadline = Date().addingTimeInterval(5.0)
            var targetApp: NSRunningApplication?
            
            while Date() < deadline {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first {
                    targetApp = app
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            guard let app = targetApp else { return }
            app.activate()
            
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var targetWin: AXUIElement?
            
            // Wait for Location Services window
            for _ in 0..<30 {
                var winVal: AnyObject?
                AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &winVal)
                if let w = (winVal as? [AXUIElement])?.first {
                    targetWin = w
                    break
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            
            guard let win = targetWin else { return }
            
            // Find the master switch
            var masterSwitch: AXUIElement?
            for _ in 0..<25 {
                if let s = self?.findMasterSwitch(win) {
                    masterSwitch = s
                    break
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            
            guard let s = masterSwitch else { return }
            
            var valVal: AnyObject?
            AXUIElementCopyAttributeValue(s, kAXValueAttribute as CFString, &valVal)
            let currentSwitchVal = (valVal as? NSNumber)?.intValue == 1
            
            // If already in desired state, do nothing
            if currentSwitchVal == desiredState {
                _ = self?.checkStatus()
                if !wasRunning {
                    Thread.sleep(forTimeInterval: 0.5)
                    app.terminate()
                }
                return
            }
            
            // Get screen coordinates of the master switch
            var posVal: AnyObject?
            AXUIElementCopyAttributeValue(s, kAXPositionAttribute as CFString, &posVal)
            var sizeVal: AnyObject?
            AXUIElementCopyAttributeValue(s, kAXSizeAttribute as CFString, &sizeVal)
            
            var pt = CGPoint.zero
            if let v = posVal {
                AXValueGetValue(v as! AXValue, .cgPoint, &pt)
            }
            var sz = CGSize.zero
            if let v = sizeVal {
                AXValueGetValue(v as! AXValue, .cgSize, &sz)
            }
            
            let center = CGPoint(x: pt.x + sz.width / 2.0, y: pt.y + sz.height / 2.0)
            
            // Simulate mouse click on the master switch
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
            down?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.05)
            up?.post(tap: .cghidEventTap)
            
            // If disabling, handle confirmation alert if shown
            if !desiredState {
                Thread.sleep(forTimeInterval: 0.4)
                if let turnOffButton = self?.findButton(in: win, withTitle: "Turn Off") {
                    _ = AXUIElementPerformAction(turnOffButton, kAXPressAction as CFString)
                }
            }
            
            // Wait for system state update
            Thread.sleep(forTimeInterval: 0.8)
            _ = self?.checkStatus()
            
            // If System Settings was not previously running, clean up
            if !wasRunning {
                Thread.sleep(forTimeInterval: 0.4)
                app.terminate()
            }
        }
    }
    
    // MARK: - Accessibility Helpers
    
    private func findMasterSwitch(_ el: AXUIElement) -> AXUIElement? {
        var roleVal: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleVal)
        var descVal: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleDescriptionAttribute as CFString, &descVal)
        
        if (roleVal as? String) == "AXCheckBox" && (descVal as? String) == "switch" {
            return el
        }
        
        var childrenVal: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenVal) == .success,
           let children = childrenVal as? [AXUIElement] {
            for c in children {
                if let found = findMasterSwitch(c) {
                    return found
                }
            }
        }
        return nil
    }
    
    private func findButton(in el: AXUIElement, withTitle targetTitle: String) -> AXUIElement? {
        var roleVal: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleVal)
        var titleVal: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &titleVal)
        
        let role = (roleVal as? String) ?? ""
        let title = (titleVal as? String) ?? ""
        
        if role == "AXButton" && title.localizedCaseInsensitiveContains(targetTitle) {
            return el
        }
        
        var childrenVal: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenVal) == .success,
           let children = childrenVal as? [AXUIElement] {
            for c in children {
                if let found = findButton(in: c, withTitle: targetTitle) {
                    return found
                }
            }
        }
        return nil
    }
}
