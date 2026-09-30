import Foundation
import SwiftUI
import ServiceManagement

public extension Notification.Name {
    static let settingsDidChange = Notification.Name("SwitchSettingsDidChange")
    static let menuBarIconDidChange = Notification.Name("SwitchMenuBarIconDidChange")
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    // Keys
    private let keyLaunchAtLogin = "switch.launchAtLogin"
    private let keyMenuBarIcon = "switch.menuBarIcon"
    private let keyScreenSaverDelay = "switch.screenSaverDelay"
    private let keyPlaySound = "switch.playSound"
    private let keyEnabledSwitches = "switch.enabledSwitches"
    
    @Published public var launchAtLogin: Bool = false
    @Published public var menuBarIcon: String = "switch.2"
    @Published public var defaultScreenSaverDelay: Int = 300
    @Published public var playSound: Bool = true
    @Published public var enabledSwitches: [String: Bool] = [:]
    
    public let availableIcons: [(id: String, name: String, symbol: String)] = [
        ("switch.2", "Default Switch", "switch.2"),
        ("slider.horizontal.3", "Sliders", "slider.horizontal.3"),
        ("bolt.circle.fill", "Power Bolt", "bolt.circle.fill"),
        ("power", "Power Button", "power")
    ]
    
    public let screenSaverDurations: [(seconds: Int, label: String)] = [
        (60, "1 Minute"),
        (120, "2 Minutes"),
        (300, "5 Minutes (Default)"),
        (600, "10 Minutes"),
        (900, "15 Minutes"),
        (1200, "20 Minutes"),
        (1800, "30 Minutes")
    ]
    
    private init() {
        loadSettings()
        checkLaunchAtLoginStatus()
    }
    
    public func loadSettings() {
        if defaults.object(forKey: keyMenuBarIcon) != nil {
            self.menuBarIcon = defaults.string(forKey: keyMenuBarIcon) ?? "switch.2"
        }
        
        if defaults.object(forKey: keyScreenSaverDelay) != nil {
            let saved = defaults.integer(forKey: keyScreenSaverDelay)
            self.defaultScreenSaverDelay = saved > 0 ? saved : 300
        }
        
        if defaults.object(forKey: keyPlaySound) != nil {
            self.playSound = defaults.bool(forKey: keyPlaySound)
        }
        
        if let savedSwitches = defaults.dictionary(forKey: keyEnabledSwitches) as? [String: Bool] {
            var dict = savedSwitches
            for type in SwitchType.allCases {
                if dict[type.rawValue] == nil {
                    dict[type.rawValue] = true
                }
            }
            self.enabledSwitches = dict
        } else {
            // Default: all switches enabled
            var dict: [String: Bool] = [:]
            for type in SwitchType.allCases {
                dict[type.rawValue] = true
            }
            self.enabledSwitches = dict
        }
    }
    
    public func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = defaults.bool(forKey: keyLaunchAtLogin)
        }
    }
    
    public func setLaunchAtLogin(_ enable: Bool) {
        self.launchAtLogin = enable
        defaults.set(enable, forKey: keyLaunchAtLogin)
        
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("Failed to register/unregister SMAppService: \(error.localizedDescription)")
            }
            checkLaunchAtLoginStatus()
        }
    }
    
    public func setMenuBarIcon(_ icon: String) {
        self.menuBarIcon = icon
        defaults.set(icon, forKey: keyMenuBarIcon)
        NotificationCenter.default.post(name: .menuBarIconDidChange, object: icon)
    }
    
    public func setScreenSaverDelay(_ seconds: Int) {
        self.defaultScreenSaverDelay = seconds
        defaults.set(seconds, forKey: keyScreenSaverDelay)
        defaults.set(seconds, forKey: "savedScreenSaverInterval")
    }
    
    public func setPlaySound(_ enable: Bool) {
        self.playSound = enable
        defaults.set(enable, forKey: keyPlaySound)
    }
    
    public func isSwitchEnabled(_ type: SwitchType) -> Bool {
        return enabledSwitches[type.rawValue] ?? true
    }
    
    public func setSwitchEnabled(_ type: SwitchType, isEnabled: Bool) {
        enabledSwitches[type.rawValue] = isEnabled
        defaults.set(enabledSwitches, forKey: keyEnabledSwitches)
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
    
    public func enableAllSwitches() {
        for type in SwitchType.allCases {
            enabledSwitches[type.rawValue] = true
        }
        defaults.set(enabledSwitches, forKey: keyEnabledSwitches)
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
    
    public func resetToDefaults() {
        setLaunchAtLogin(false)
        setMenuBarIcon("switch.2")
        setScreenSaverDelay(300)
        setPlaySound(true)
        enableAllSwitches()
    }
}
