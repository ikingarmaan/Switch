import Foundation
import AppKit

public final class AppearanceService: @unchecked Sendable {
    public static let shared = AppearanceService()
    
    private typealias SLSSetAppearanceThemeLegacy = @convention(c) (Bool) -> Void
    private var setAppearanceFunc: SLSSetAppearanceThemeLegacy?
    
    private init() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) {
            if let sym = dlsym(handle, "SLSSetAppearanceThemeLegacy") {
                self.setAppearanceFunc = unsafeBitCast(sym, to: SLSSetAppearanceThemeLegacy.self)
            }
        }
    }
    
    public func isDarkMode() -> Bool {
        if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
            return style.caseInsensitiveCompare("Dark") == .orderedSame
        }
        let res = Shell.run("defaults read -g AppleInterfaceStyle 2>/dev/null")
        return res.caseInsensitiveCompare("Dark") == .orderedSame
    }
    
    public func setDarkMode(_ isDark: Bool) {
        if let setFunc = setAppearanceFunc {
            setFunc(isDark)
        }
    }
}
