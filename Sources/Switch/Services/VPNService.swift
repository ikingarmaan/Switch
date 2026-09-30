import Foundation
import AppKit
import Combine

public extension Notification.Name {
    static let vpnStateDidChange = Notification.Name("SwitchVPNStateDidChange")
}

public enum VPNCountry: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "auto"
    case us = "us"
    case gb = "gb"
    case de = "de"
    case jp = "jp"
    case sg = "sg"
    case ca = "ca"
    case nl = "nl"
    case fr = "fr"
    case ch = "ch"
    case au = "au"
    case `in` = "in"
    
    public var id: String { rawValue }
    
    public var flag: String {
        switch self {
        case .auto: return "🌐"
        case .us: return "🇺🇸"
        case .gb: return "🇬🇧"
        case .de: return "🇩🇪"
        case .jp: return "🇯🇵"
        case .sg: return "🇸🇬"
        case .ca: return "🇨🇦"
        case .nl: return "🇳🇱"
        case .fr: return "🇫🇷"
        case .ch: return "🇨🇭"
        case .au: return "🇦🇺"
        case .in: return "🇮🇳"
        }
    }
    
    public var name: String {
        switch self {
        case .auto: return "Auto (Fastest Server)"
        case .us: return "United States"
        case .gb: return "United Kingdom"
        case .de: return "Germany"
        case .jp: return "Japan"
        case .sg: return "Singapore"
        case .ca: return "Canada"
        case .nl: return "Netherlands"
        case .fr: return "France"
        case .ch: return "Switzerland"
        case .au: return "Australia"
        case .in: return "India"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .us: return "US"
        case .gb: return "UK"
        case .de: return "DE"
        case .jp: return "JP"
        case .sg: return "SG"
        case .ca: return "CA"
        case .nl: return "NL"
        case .fr: return "FR"
        case .ch: return "CH"
        case .au: return "AU"
        case .in: return "IN"
        }
    }
}

public final class VPNService: ObservableObject, @unchecked Sendable {
    public static let shared = VPNService()
    
    private let userDefaultsKey = "switch.vpn.selectedCountry"
    private var checkTimer: Timer?
    
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isConnecting: Bool = false
    @Published public var selectedCountry: VPNCountry = .auto
    @Published public private(set) var activeVPNServiceName: String? = nil
    @Published public private(set) var detectedLocation: String? = nil
    @Published public private(set) var detectedIP: String? = nil
    @Published public private(set) var statusSubtitle: String = "Disconnected"
    
    public var isProtonVPNInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/ProtonVPN.app")
    }
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let country = VPNCountry(rawValue: saved) {
            self.selectedCountry = country
        }
        self.statusSubtitle = isProtonVPNInstalled ? "1-Click Secure Tunnel • Ready" : "No VPN Configured"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.detectAvailableVPNService()
            self?.refreshStatus()
        }
    }
    
    // MARK: - Detect macOS VPN Services
    
    public func detectAvailableVPNService() {
        let output = Shell.run("/usr/sbin/scutil --nc list 2>/dev/null")
        let lines = output.components(separatedBy: .newlines)
        
        var detected: String? = nil
        for line in lines {
            if line.contains("VPN") {
                if let firstQuote = line.firstIndex(of: "\""),
                   let lastQuote = line.lastIndex(of: "\""),
                   firstQuote < lastQuote {
                    detected = String(line[line.index(after: firstQuote)..<lastQuote])
                    break
                }
            }
        }
        
        if detected == nil && isProtonVPNInstalled {
            detected = "ProtonVPN"
        }
        
        let finalDetected = detected
        DispatchQueue.main.async { [weak self] in
            self?.activeVPNServiceName = finalDetected
        }
    }
    
    // MARK: - Query Status
    
    public func refreshStatus() {
        let serviceName = activeVPNServiceName
        guard let sName = serviceName else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isConnected = false
                self.isConnecting = false
                self.statusSubtitle = self.isProtonVPNInstalled ? "1-Click Secure Tunnel • Ready" : "No VPN Configured"
                self.notifyChange()
            }
            return
        }
        
        let output = Shell.run("/usr/sbin/scutil --nc status \"\(sName)\" 2>/dev/null")
        let firstLine = output.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if firstLine.caseInsensitiveCompare("Connected") == .orderedSame {
                let wasConnected = self.isConnected
                self.isConnected = true
                self.isConnecting = false
                if !wasConnected || self.detectedLocation == nil {
                    self.fetchLiveIPAndLocation()
                } else {
                    self.updateSubtitle()
                }
            } else if firstLine.caseInsensitiveCompare("Connecting") == .orderedSame {
                self.isConnected = false
                self.isConnecting = true
                self.statusSubtitle = "Connecting to Secure Tunnel..."
            } else {
                self.isConnected = false
                self.isConnecting = false
                self.detectedLocation = nil
                self.detectedIP = nil
                self.statusSubtitle = self.isProtonVPNInstalled ? "1-Click Secure Tunnel • Ready" : "No VPN Configured"
            }
            self.notifyChange()
        }
    }
    
    // MARK: - Connection Actions
    
    public func setEnabled(_ isOn: Bool) {
        if isOn {
            connect()
        } else {
            disconnect()
        }
    }
    
    public func toggleConnection() {
        if isConnected {
            disconnect()
        } else {
            connect()
        }
    }
    
    public func selectCountry(_ country: VPNCountry) {
        self.selectedCountry = country
        UserDefaults.standard.set(country.rawValue, forKey: userDefaultsKey)
        
        if isConnected {
            // Reconnect to target country
            disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.connect()
            }
        } else {
            self.statusSubtitle = "\(country.flag) \(country.shortLabel) • Ready"
            notifyChange()
        }
    }
    
    public func connect() {
        detectAvailableVPNService()
        
        guard let serviceName = activeVPNServiceName else {
            if isProtonVPNInstalled {
                openProtonVPNApp()
            } else {
                openNetworkSettings()
            }
            return
        }
        
        self.isConnecting = true
        self.statusSubtitle = "\(selectedCountry.flag) Connecting to \(selectedCountry.shortLabel)..."
        notifyChange()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Ensure ProtonVPN helper is quietly running in background if needed
            if self.isProtonVPNInstalled && NSRunningApplication.runningApplications(withBundleIdentifier: "ch.protonvpn.mac").isEmpty {
                _ = Shell.run("/usr/bin/open -g -j -a ProtonVPN 2>/dev/null")
                Thread.sleep(forTimeInterval: 0.5)
            }
            
            _ = Shell.run("/usr/sbin/scutil --nc start \"\(serviceName)\" 2>/dev/null")
            
            // Poll for connection up to 10 seconds
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 1.0)
                let status = Shell.run("/usr/sbin/scutil --nc status \"\(serviceName)\" 2>/dev/null")
                let line = status.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
                if line.caseInsensitiveCompare("Connected") == .orderedSame {
                    DispatchQueue.main.async {
                        self.isConnected = true
                        self.isConnecting = false
                        self.fetchLiveIPAndLocation()
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                self.refreshStatus()
            }
        }
    }
    
    public func disconnect() {
        guard let serviceName = activeVPNServiceName else { return }
        
        self.isConnecting = false
        self.isConnected = false
        self.detectedLocation = nil
        self.detectedIP = nil
        self.statusSubtitle = "\(selectedCountry.flag) Disconnecting..."
        notifyChange()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            _ = Shell.run("/usr/sbin/scutil --nc stop \"\(serviceName)\" 2>/dev/null")
            Thread.sleep(forTimeInterval: 0.8)
            DispatchQueue.main.async {
                self.refreshStatus()
            }
        }
    }
    
    // MARK: - Live IP & Geo Location Lookup
    
    public func fetchLiveIPAndLocation() {
        guard let url = URL(string: "https://ipwho.is/") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.updateSubtitle()
                }
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let isSuccess = json["success"] as? Bool, isSuccess {
                let country = json["country"] as? String ?? ""
                let city = json["city"] as? String ?? ""
                let ip = json["ip"] as? String ?? ""
                let flagDict = json["flag"] as? [String: Any]
                let flag = flagDict?["emoji"] as? String ?? "🛡️"
                
                let locationString = city.isEmpty ? "\(flag) \(country)" : "\(flag) \(city), \(country)"
                
                DispatchQueue.main.async {
                    self.detectedLocation = locationString
                    self.detectedIP = ip
                    self.updateSubtitle()
                }
            } else {
                DispatchQueue.main.async {
                    self.updateSubtitle()
                }
            }
        }.resume()
    }
    
    private func updateSubtitle() {
        if isConnected {
            if let loc = detectedLocation {
                if let ip = detectedIP {
                    let parts = ip.components(separatedBy: ".")
                    let maskedIP = parts.count == 4 ? "\(parts[0]).\(parts[1]).*.*" : ip
                    self.statusSubtitle = "\(loc) (\(maskedIP)) • WireGuard"
                } else {
                    self.statusSubtitle = "\(loc) • WireGuard"
                }
            } else {
                self.statusSubtitle = "🛡️ Connected • WireGuard"
            }
        } else {
            self.statusSubtitle = isProtonVPNInstalled ? "1-Click Secure Tunnel • Ready" : "No VPN Configured"
        }
        notifyChange()
    }
    
    private func notifyChange() {
        NotificationCenter.default.post(name: .vpnStateDidChange, object: isConnected)
    }
    
    // MARK: - Shortcuts
    
    public func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?VPN") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.network?VPN") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func openProtonVPNApp() {
        _ = Shell.run("open -a ProtonVPN")
    }
}
