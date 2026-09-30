import Foundation
import AppKit
import Combine

public extension Notification.Name {
    static let dnsStateDidChange = Notification.Name("SwitchDNSStateDidChange")
}

public enum DNSProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case adguard = "adguard"
    case family = "family"
    case highSpeed = "highSpeed"
    case google = "google"
    case quad9 = "quad9"
    
    public var id: String { rawValue }
    
    public var label: String {
        switch self {
        case .adguard: return "AdGuard (Block Ads)"
        case .family: return "Family (Block Adult)"
        case .highSpeed: return "High-Speed (Cloudflare)"
        case .google: return "Google (8.8.8.8)"
        case .quad9: return "Quad9 (Threat Block)"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .adguard: return "AdGuard"
        case .family: return "Family"
        case .highSpeed: return "1.1.1.1"
        case .google: return "Google"
        case .quad9: return "Quad9"
        }
    }
    
    public var icon: String {
        switch self {
        case .adguard: return "shield.fill"
        case .family: return "figure.2.and.child.holdinghands"
        case .highSpeed: return "bolt.fill"
        case .google: return "globe"
        case .quad9: return "lock.shield.fill"
        }
    }
    
    public var servers: [String] {
        switch self {
        case .adguard:
            return ["94.140.14.14", "94.140.15.15"]
        case .family:
            return ["94.140.14.15", "94.140.15.16"]
        case .highSpeed:
            return ["1.1.1.1", "1.0.0.1"]
        case .google:
            return ["8.8.8.8", "8.8.4.4"]
        case .quad9:
            return ["9.9.9.9", "149.112.112.112"]
        }
    }
    
    public var description: String {
        switch self {
        case .adguard:
            return "Blocks ads, trackers & popups across all apps and sites"
        case .family:
            return "Blocks adult & NSFW websites, phishing, plus ads"
        case .highSpeed:
            return "Ultra-fast Cloudflare DNS for lowest latency and ping"
        case .google:
            return "Google Public DNS for ultra-reliable global resolution"
        case .quad9:
            return "Blocks malicious domains, botnets and cyber threats"
        }
    }
}

public final class DNSService: ObservableObject, @unchecked Sendable {
    public static let shared = DNSService()
    
    private let userDefaultsKey = "switch.dns.selectedProfile"
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public var selectedProfile: DNSProfile = .adguard
    @Published public private(set) var statusSubtitle: String = "Automatic (DHCP)"
    @Published public private(set) var currentDnsServers: [String] = []
    @Published public private(set) var activeNetworkService: String = "Wi-Fi"
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let profile = DNSProfile(rawValue: saved) {
            self.selectedProfile = profile
        }
        self.statusSubtitle = "\(selectedProfile.shortLabel) • Off (DHCP)"
        
        // Asynchronously inspect actual active service and DNS configuration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.detectActiveService()
            self?.refreshStatus()
        }
    }
    
    // MARK: - Detect Active Network Service
    
    public func detectActiveService() {
        let output = Shell.run("/usr/sbin/networksetup -listnetworkserviceorder 2>/dev/null")
        let lines = output.components(separatedBy: .newlines)
        
        var detected = "Wi-Fi"
        for line in lines {
            if line.contains("Hardware Port:") {
                let parts = line.components(separatedBy: ",")
                if let firstPart = parts.first {
                    let portName = firstPart.replacingOccurrences(of: "(Hardware Port:", with: "")
                        .replacingOccurrences(of: "(Hardware Port", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if portName.caseInsensitiveCompare("Wi-Fi") == .orderedSame || portName.caseInsensitiveCompare("Ethernet") == .orderedSame {
                        detected = portName
                        break
                    }
                }
            }
        }
        let finalDetected = detected
        DispatchQueue.main.async { [weak self] in
            self?.activeNetworkService = finalDetected
        }
    }
    
    // MARK: - Query Status
    
    public func refreshStatus() {
        let service = self.activeNetworkService
        let output = Shell.run("/usr/sbin/networksetup -getdnsservers \"\(service)\" 2>/dev/null")
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            
        let isConfigured = !lines.isEmpty && !output.localizedCaseInsensitiveContains("aren't any") && !output.localizedCaseInsensitiveContains("There aren't")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if isConfigured {
                self.isEnabled = true
                self.currentDnsServers = lines
                
                // Match against known profiles
                if let matched = DNSProfile.allCases.first(where: { profile in
                    profile.servers == lines || (lines.count > 0 && lines[0] == profile.servers[0])
                }) {
                    self.selectedProfile = matched
                    self.statusSubtitle = "\(matched.shortLabel) • \(lines[0])"
                } else {
                    self.statusSubtitle = "Custom • \(lines[0])"
                }
            } else {
                self.isEnabled = false
                self.currentDnsServers = []
                self.statusSubtitle = "\(self.selectedProfile.shortLabel) • Off (DHCP)"
            }
            self.notifyChange()
        }
    }
    
    // MARK: - Actions
    
    public func setEnabled(_ on: Bool) {
        if on {
            applyProfile(selectedProfile)
        } else {
            resetToDefault()
        }
    }
    
    public func toggle() {
        setEnabled(!isEnabled)
    }
    
    public func selectProfile(_ profile: DNSProfile) {
        self.selectedProfile = profile
        UserDefaults.standard.set(profile.rawValue, forKey: userDefaultsKey)
        
        if isEnabled {
            // Apply new profile immediately
            applyProfile(profile)
        } else {
            self.statusSubtitle = "\(profile.shortLabel) • Off (DHCP)"
            notifyChange()
        }
    }
    
    public func applyProfile(_ profile: DNSProfile) {
        self.selectedProfile = profile
        UserDefaults.standard.set(profile.rawValue, forKey: userDefaultsKey)
        
        self.isEnabled = true
        self.currentDnsServers = profile.servers
        self.statusSubtitle = "\(profile.shortLabel) • \(profile.servers[0])"
        notifyChange()
        
        let service = activeNetworkService
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let serverArgs = profile.servers.joined(separator: " ")
            _ = Shell.run("/usr/sbin/networksetup -setdnsservers \"\(service)\" \(serverArgs) 2>/dev/null")
            _ = Shell.run("/usr/bin/dscacheutil -flushcache 2>/dev/null")
            self?.refreshStatus()
        }
    }
    
    public func resetToDefault() {
        self.isEnabled = false
        self.currentDnsServers = []
        self.statusSubtitle = "\(selectedProfile.shortLabel) • Off (DHCP)"
        notifyChange()
        
        let service = activeNetworkService
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = Shell.run("/usr/sbin/networksetup -setdnsservers \"\(service)\" empty 2>/dev/null")
            _ = Shell.run("/usr/bin/dscacheutil -flushcache 2>/dev/null")
            self?.refreshStatus()
        }
    }
    
    public func flushDNSCache() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Shell.run("/usr/bin/dscacheutil -flushcache 2>/dev/null")
            DispatchQueue.main.async {
                NSSound(named: "Tink")?.play()
            }
        }
    }
    
    private func notifyChange() {
        NotificationCenter.default.post(name: .dnsStateDidChange, object: isEnabled)
    }
    
    // MARK: - Shortcuts
    
    public func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?DNS") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.network") {
            NSWorkspace.shared.open(url)
        }
    }
}
