import Foundation
import Cocoa

public final class FinderServicesProvider: NSObject {
    public static let shared = FinderServicesProvider()
    
    private func extractPaths(from pboard: NSPasteboard) -> [String] {
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return urls.map { $0.path }
        }
        if let filenames = pboard.propertyList(forType: NSPasteboard.PasteboardType(rawValue: "NSFilenamesPboardType")) as? [String], !filenames.isEmpty {
            return filenames
        }
        if let string = pboard.string(forType: .string), !string.isEmpty {
            if string.hasPrefix("/") {
                return [string]
            }
        }
        return []
    }
    
    @objc public func openMouseBoostHUDService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let paths = extractPaths(from: pboard)
        DispatchQueue.main.async {
            if let first = paths.first {
                MouseBoostProService.shared.setExplicitPath(first)
            }
            MouseBoostProService.shared.showSuperHUD()
        }
    }
    
    @objc public func createNewFileService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let paths = extractPaths(from: pboard)
        DispatchQueue.main.async {
            if let first = paths.first {
                MouseBoostProService.shared.setExplicitPath(first)
            }
            MouseBoostProService.shared.showSuperHUD()
        }
    }
    
    @objc public func openTerminalService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let paths = extractPaths(from: pboard)
        DispatchQueue.main.async {
            if let first = paths.first {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: first, isDirectory: &isDir) {
                    let dir = isDir.boolValue ? first : (first as NSString).deletingLastPathComponent
                    Shell.run("open -a Terminal \"\(dir)\"")
                    return
                }
            }
            MouseBoostProService.shared.openInTerminal()
        }
    }
    
    @objc public func openVSCodeService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let paths = extractPaths(from: pboard)
        DispatchQueue.main.async {
            if let first = paths.first {
                Shell.run("open -a 'Visual Studio Code' \"\(first)\" || code \"\(first)\"")
                return
            }
            MouseBoostProService.shared.openInVSCode()
        }
    }
    
    @objc public func copyPathService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let paths = extractPaths(from: pboard)
        DispatchQueue.main.async {
            if let first = paths.first {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(first, forType: .string)
                NSSound(named: "Tink")?.play()
                return
            }
            MouseBoostProService.shared.copyCurrentPath()
        }
    }
}
