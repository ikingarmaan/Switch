import Foundation
import SwiftUI
import Combine

@MainActor
public final class SwitchListViewModel: ObservableObject {
    @Published public var switches: [SwitchItem] = []
    @Published public var isRefreshing: Bool = false
    
    private var timer: AnyCancellable?
    private let controlService = SystemControlService.shared
    
    public var visibleSwitches: [SwitchItem] {
        switches.filter { AppSettings.shared.isSwitchEnabled($0.type) }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupSwitches()
        refreshAll()
        startPeriodicRefresh()
        
        NotificationCenter.default.publisher(for: .settingsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .keyboardLockDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let isLocked = notif.object as? Bool,
                      let index = self.switches.firstIndex(where: { $0.type == .lockKeyboard })
                else { return }
                self.switches[index].isOn = isLocked
                self.switches[index].isLoading = false
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .cameraPreviewDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let isRunning = notif.object as? Bool,
                      let index = self.switches.firstIndex(where: { $0.type == .cameraPreview })
                else { return }
                self.switches[index].isOn = isRunning
                self.switches[index].isLoading = false
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .timerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .timer })
                else { return }
                let s = CountdownTimerService.shared
                self.switches[index].isOn = s.isRunning
                self.switches[index].isLoading = false
                self.switches[index].subtitle = s.isRunning ? s.formattedRemainingTime : s.formattedSelectedDuration
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .timerTick)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let timeStr = notif.object as? String,
                      let index = self.switches.firstIndex(where: { $0.type == .timer })
                else { return }
                if !timeStr.isEmpty {
                    self.switches[index].subtitle = timeStr
                } else {
                    self.switches[index].subtitle = CountdownTimerService.shared.formattedSelectedDuration
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .amphetamineStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .amphetamine })
                else { return }
                let a = AmphetamineService.shared
                self.switches[index].isOn = a.isActive
                self.switches[index].isLoading = false
                self.switches[index].subtitle = a.isActive ? a.formattedRemainingTime : a.formattedSelectedDuration
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .amphetamineTick)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let timeStr = notif.object as? String,
                      let index = self.switches.firstIndex(where: { $0.type == .amphetamine })
                else { return }
                if !timeStr.isEmpty {
                    self.switches[index].subtitle = timeStr
                } else {
                    self.switches[index].subtitle = AmphetamineService.shared.formattedSelectedDuration
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .mouseJigglerStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .mouseJiggler })
                else { return }
                let m = MouseJigglerService.shared
                self.switches[index].isOn = m.isActive
                self.switches[index].isLoading = false
                self.switches[index].subtitle = m.formattedSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .mouseJigglerTick)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .mouseJiggler })
                else { return }
                if let timeStr = notif.object as? String, !timeStr.isEmpty {
                    self.switches[index].subtitle = timeStr
                } else {
                    self.switches[index].subtitle = MouseJigglerService.shared.formattedSubtitle
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .googlyEyesStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let isEnabled = notif.object as? Bool,
                      let index = self.switches.firstIndex(where: { $0.type == .googlyEyes })
                else { return }
                self.switches[index].isOn = isEnabled
                self.switches[index].isLoading = false
                self.switches[index].subtitle = isEnabled ? GooglyEyesService.shared.currentEmotion.label : nil
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .googlyEyesEmotionDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let emotionLabel = notif.object as? String,
                      let index = self.switches.firstIndex(where: { $0.type == .googlyEyes })
                else { return }
                if self.switches[index].isOn {
                    self.switches[index].subtitle = emotionLabel
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .volumeBoostStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .volumeBoost })
                else { return }
                let v = VolumeBoostService.shared
                self.switches[index].isOn = v.isActive
                self.switches[index].isLoading = false
                self.switches[index].subtitle = v.isActive ? v.selectedLevel.label : nil
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .grammarCoachStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let isEnabled = notif.object as? Bool,
                      let index = self.switches.firstIndex(where: { $0.type == .grammarCoach })
                else { return }
                self.switches[index].isOn = isEnabled
                self.switches[index].isLoading = false
                self.switches[index].subtitle = isEnabled ? GrammarCoachService.shared.currentStyle.rawValue : nil
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .grammarCoachStyleDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let style = notif.object as? WritingStyle,
                      let index = self.switches.firstIndex(where: { $0.type == .grammarCoach })
                else { return }
                if self.switches[index].isOn {
                    self.switches[index].subtitle = style.rawValue
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .systemMonitorDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let isEnabled = notif.object as? Bool,
                      let index = self.switches.firstIndex(where: { $0.type == .systemMonitor })
                else { return }
                self.switches[index].isOn = isEnabled
                self.switches[index].isLoading = false
                self.switches[index].subtitle = isEnabled ? "Menu Bar" : nil
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .systemMonitorTick)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .systemMonitor })
                else { return }
                if self.switches[index].isOn {
                    self.switches[index].subtitle = "Menu Bar"
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .loomRecorderDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let isActive = notif.object as? Bool,
                      let index = self.switches.firstIndex(where: { $0.type == .loomRecorder })
                else { return }
                let loom = LoomRecorderService.shared
                self.switches[index].isOn = isActive
                self.switches[index].isLoading = false
                if loom.isRecording {
                    self.switches[index].subtitle = loom.formattedDuration
                } else if loom.isSessionActive {
                    self.switches[index].subtitle = "Ready"
                } else {
                    self.switches[index].subtitle = nil
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .loomRecorderTick)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let timeStr = notif.object as? String,
                      let index = self.switches.firstIndex(where: { $0.type == .loomRecorder })
                else { return }
                if self.switches[index].isOn {
                    self.switches[index].subtitle = timeStr
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: Notification.Name("SwitchForceQuitDidComplete"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .forceQuitApps })
                else { return }
                let count = notif.object as? Int ?? 0
                self.switches[index].isOn = false
                self.switches[index].isLoading = false
                self.switches[index].subtitle = count > 0 ? "Closed \(count) apps" : "All apps closed"
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .vpnStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .autoVPN })
                else { return }
                let v = VPNService.shared
                self.switches[index].isOn = v.isConnected
                self.switches[index].isLoading = v.isConnecting
                self.switches[index].subtitle = v.statusSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .folderTidyDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .tidyFolders })
                else { return }
                let tidy = FolderTidyService.shared
                self.switches[index].isOn = tidy.isOrganizing
                self.switches[index].isLoading = tidy.isOrganizing
                self.switches[index].subtitle = tidy.statusSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .dnsStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .adblockDNS })
                else { return }
                let dns = DNSService.shared
                self.switches[index].isOn = dns.isEnabled
                self.switches[index].isLoading = false
                self.switches[index].subtitle = dns.statusSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .knockScreenshotDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .knockScreenshot })
                else { return }
                let knock = KnockScreenshotService.shared
                let isListening = notif.object as? Bool ?? knock.isListening
                self.switches[index].isOn = isListening
                self.switches[index].isLoading = false
                self.switches[index].subtitle = isListening ? knock.statusSubtitle : "2 Knocks"
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .knockScreenshotStatusTick)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .knockScreenshot })
                else { return }
                if let text = notif.object as? String {
                    self.switches[index].subtitle = text
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .clipboardStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .clipboardManager })
                else { return }
                let clip = ClipboardService.shared
                let isEnabled = notif.object as? Bool ?? clip.isEnabled
                self.switches[index].isOn = isEnabled
                self.switches[index].isLoading = false
                self.switches[index].subtitle = isEnabled ? clip.statusSubtitle : "Off"
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .clipboardItemsDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .clipboardManager })
                else { return }
                let clip = ClipboardService.shared
                if self.switches[index].isOn {
                    self.switches[index].subtitle = clip.statusSubtitle
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .autoScrollStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .autoScroll })
                else { return }
                let scroll = AutoScrollService.shared
                let isRunning = notif.object as? Bool ?? scroll.isActive
                self.switches[index].isOn = isRunning
                self.switches[index].isLoading = false
                self.switches[index].subtitle = scroll.statusSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .autoScrollTick)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .autoScroll })
                else { return }
                if let text = notif.object as? String {
                    self.switches[index].subtitle = text
                } else {
                    self.switches[index].subtitle = AutoScrollService.shared.statusSubtitle
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .stickyNotesStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .stickyNotes })
                else { return }
                let s = StickyNotesService.shared
                self.switches[index].isOn = s.isVisible
                self.switches[index].isLoading = false
                self.switches[index].subtitle = s.statusSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .stickyNotesCountDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .stickyNotes })
                else { return }
                let s = StickyNotesService.shared
                self.switches[index].subtitle = s.statusSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .menuBarAutoHideModeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .autohideMenuBar })
                else { return }
                let status = SystemControlService.shared.getStatus(for: .autohideMenuBar)
                self.switches[index].isOn = status.isOn
                self.switches[index].isLoading = false
                self.switches[index].subtitle = status.subtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .selfControlStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .selfControl })
                else { return }
                let sc = SelfControlService.shared
                self.switches[index].isOn = sc.isShieldActive
                self.switches[index].isLoading = false
                self.switches[index].subtitle = sc.statusSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .locationServicesStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .locationServices })
                else { return }
                let loc = LocationService.shared
                let isEnabled = notif.object as? Bool ?? loc.isEnabled
                self.switches[index].isOn = isEnabled
                self.switches[index].isLoading = false
                self.switches[index].subtitle = loc.statusSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .nightShiftDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .nightShift })
                else { return }
                let ns = NightShiftService.shared
                self.switches[index].isOn = ns.isEnabled()
                self.switches[index].isLoading = false
                self.switches[index].subtitle = ns.subtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .selfControlTick)
            .receive(on: RunLoop.main)
            .sink { [weak self] notif in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .selfControl })
                else { return }
                if let sub = notif.object as? String {
                    self.switches[index].subtitle = sub
                } else {
                    self.switches[index].subtitle = SelfControlService.shared.statusSubtitle
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .ramGpuResetStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .ramGpuReset })
                else { return }
                let ram = RAMGPUResetService.shared
                self.switches[index].isOn = ram.isAutoGuardEnabled
                self.switches[index].isLoading = false
                self.switches[index].subtitle = ram.statusSubtitle
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .ramGpuResetDidComplete)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      let index = self.switches.firstIndex(where: { $0.type == .ramGpuReset })
                else { return }
                let ram = RAMGPUResetService.shared
                self.switches[index].subtitle = ram.statusSubtitle
            }
            .store(in: &cancellables)
    }
    
    private func setupSwitches() {
        // Ordered as shown in user's image + lockKeyboard + cameraPreview + timer + amphetamine + mouseJiggler + autoScroll + googlyEyes + volumeBoost + grammarCoach + systemMonitor + loomRecorder + forceQuitApps + autoVPN + tidyFolders + adblockDNS + knockScreenshot + clipboardManager + stickyNotes + selfControl + locationServices + ramGpuReset
        let initialTypes: [SwitchType] = [
            .hideDesktop,
            .keepAwake,
            .screenSaver,
            .nightShift,
            .autohideDock,
            .autohideMenuBar,
            .hiddenFiles,
            .lockKeyboard,
            .cameraPreview,
            .timer,
            .amphetamine,
            .mouseJiggler,
            .autoScroll,
            .googlyEyes,
            .volumeBoost,
            .grammarCoach,
            .systemMonitor,
            .loomRecorder,
            .forceQuitApps,
            .autoVPN,
            .tidyFolders,
            .adblockDNS,
            .knockScreenshot,
            .clipboardManager,
            .stickyNotes,
            .selfControl,
            .locationServices,
            .ramGpuReset
        ]
        
        self.switches = initialTypes.map { type in
            SwitchItem(type: type)
        }
    }
    
    public func startPeriodicRefresh() {
        timer?.cancel()
        timer = Timer.publish(every: 4.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshAll(silently: true)
            }
    }
    
    public func stopPeriodicRefresh() {
        timer?.cancel()
        timer = nil
    }
    
    public func refreshAll(silently: Bool = false) {
        if !silently {
            isRefreshing = true
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            
            let currentItems = self.switches
            let updatedStates: [(type: SwitchType, isOn: Bool, subtitle: String?)] = await Task.detached(priority: .userInitiated) {
                var results: [(type: SwitchType, isOn: Bool, subtitle: String?)] = []
                let service = SystemControlService.shared
                for item in currentItems {
                    let status = service.getStatus(for: item.type)
                    results.append((type: item.type, isOn: status.isOn, subtitle: status.subtitle))
                }
                return results
            }.value
            
            for state in updatedStates {
                if let index = self.switches.firstIndex(where: { $0.type == state.type }) {
                    if !self.switches[index].isLoading {
                        self.switches[index].isOn = state.isOn
                        if let sub = state.subtitle {
                            self.switches[index].subtitle = sub
                        }
                    }
                }
            }
            self.isRefreshing = false
        }
    }
    
    public func toggleSwitch(item: SwitchItem, newValue: Bool) {
        guard let index = switches.firstIndex(where: { $0.type == item.type }) else { return }
        
        if AppSettings.shared.playSound {
            NSSound(named: "Tink")?.play()
        }
        
        switches[index].isOn = newValue
        switches[index].isLoading = true
        
        let switchType = item.type
        
        Task { [weak self] in
            let status = await Task.detached(priority: .userInitiated) { () -> (isOn: Bool, subtitle: String?) in
                let service = SystemControlService.shared
                service.setStatus(for: switchType, isOn: newValue)
                try? await Task.sleep(nanoseconds: 300_000_000)
                return service.getStatus(for: switchType)
            }.value
            
            guard let self = self,
                  let currentIndex = self.switches.firstIndex(where: { $0.type == switchType })
            else { return }
            
            self.switches[currentIndex].isLoading = false
            self.switches[currentIndex].isOn = status.isOn
            if let sub = status.subtitle {
                self.switches[currentIndex].subtitle = sub
            }
        }
    }
    
    public func triggerAction(type: SwitchType) {
        Task {
            await Task.detached(priority: .userInitiated) {
                SystemControlService.shared.triggerAction(for: type)
            }.value
        }
    }
    
    public func quitApp() {
        PersistenceService.shared.disablePersistence()
        NSApplication.shared.terminate(nil)
    }
}
