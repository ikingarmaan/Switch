import SwiftUI

public struct SwitchRowView: View {
    @ObservedObject var item: SwitchItem
    var onToggle: (Bool) -> Void
    var onAction: (() -> Void)? = nil
    
    
    public init(
        item: SwitchItem,
        onToggle: @escaping (Bool) -> Void,
        onAction: (() -> Void)? = nil
    ) {
        self.item = item
        self.onToggle = onToggle
        self.onAction = onAction
    }
    
    public var body: some View {
        HStack(spacing: 14) {
            // Icon
            Image(systemName: item.iconName)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 24, height: 24, alignment: .center)
            
            // Title & Subtitle
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                
                if item.type == .timer {
                    Menu {
                        ForEach(CountdownTimerService.shared.presets, id: \.seconds) { preset in
                            Button(action: {
                                CountdownTimerService.shared.setDuration(preset.seconds)
                            }) {
                                HStack {
                                    Text(preset.label)
                                    if CountdownTimerService.shared.selectedDuration == preset.seconds {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(item.subtitle ?? CountdownTimerService.shared.formattedSelectedDuration)
                                .font(.system(size: 12, weight: item.isOn ? .bold : .regular, design: item.isOn ? .monospaced : .default))
                                .foregroundColor(item.isOn ? Color(red: 0.28, green: 0.76, blue: 0.52) : Color.gray.opacity(0.85))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(Color.gray.opacity(0.6))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else if item.type == .amphetamine {
                    Menu {
                        ForEach(AmphetamineService.shared.presets, id: \.seconds) { preset in
                            Button(action: {
                                AmphetamineService.shared.setDuration(preset.seconds)
                            }) {
                                HStack {
                                    Text(preset.label)
                                    if AmphetamineService.shared.selectedDuration == preset.seconds {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(item.subtitle ?? AmphetamineService.shared.formattedSelectedDuration)
                                .font(.system(size: 12, weight: item.isOn ? .bold : .regular, design: item.isOn ? .monospaced : .default))
                                .foregroundColor(item.isOn ? Color(red: 0.95, green: 0.65, blue: 0.25) : Color.gray.opacity(0.85))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(Color.gray.opacity(0.6))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else if item.type == .mouseJiggler {
                    HStack(spacing: 4) {
                        Menu {
                            Section("Move Distance (Tiles)") {
                                ForEach(MouseJigglerService.shared.tilePresets, id: \.tiles) { preset in
                                    Button(action: {
                                        MouseJigglerService.shared.setMovementTiles(preset.tiles)
                                    }) {
                                        HStack {
                                            Text(preset.label)
                                            if MouseJigglerService.shared.movementTiles == preset.tiles {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Session Duration") {
                                ForEach(MouseJigglerService.shared.presets, id: \.seconds) { preset in
                                    Button(action: {
                                        MouseJigglerService.shared.setDuration(preset.seconds)
                                    }) {
                                        HStack {
                                            Text(preset.label)
                                            if MouseJigglerService.shared.selectedDuration == preset.seconds {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                MouseJigglerService.shared.testJiggleNow()
                            }) {
                                HStack {
                                    Text("Test Move Now (\(MouseJigglerService.shared.movementTiles) tiles)")
                                    Image(systemName: "cursorarrow.motionlines")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.subtitle ?? MouseJigglerService.shared.formattedSubtitle)
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .regular, design: item.isOn ? .monospaced : .default))
                                    .foregroundColor(item.isOn ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } else if item.type == .autoScroll {
                    HStack(spacing: 4) {
                        Menu {
                            Section("Scroll Direction & Mode") {
                                ForEach(ScrollMode.allCases) { mode in
                                    Button(action: {
                                        AutoScrollService.shared.setMode(mode)
                                    }) {
                                        HStack {
                                            Text(mode.rawValue)
                                            if AutoScrollService.shared.mode == mode {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Scroll Speed") {
                                ForEach(ScrollSpeed.allCases) { speed in
                                    Button(action: {
                                        AutoScrollService.shared.setSpeed(speed)
                                    }) {
                                        HStack {
                                            Text(speed.rawValue)
                                            if AutoScrollService.shared.speed == speed {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            if AutoScrollService.shared.mode == .bounceUpDown {
                                Divider()
                                Section("Bounce Turnaround Range") {
                                    ForEach(AutoScrollService.shared.bouncePresets, id: \.steps) { preset in
                                        Button(action: {
                                            AutoScrollService.shared.setBounceSteps(preset.steps)
                                        }) {
                                            HStack {
                                                Text(preset.label)
                                                if AutoScrollService.shared.bounceSteps == preset.steps {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Session Timer") {
                                ForEach(AutoScrollService.shared.durationPresets, id: \.seconds) { preset in
                                    Button(action: {
                                        AutoScrollService.shared.setDuration(preset.seconds)
                                    }) {
                                        HStack {
                                            Text(preset.label)
                                            if AutoScrollService.shared.selectedDuration == preset.seconds {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.subtitle ?? AutoScrollService.shared.statusSubtitle)
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .medium, design: .rounded))
                                    .foregroundColor(item.isOn ? Color(red: 0.35, green: 0.85, blue: 0.65) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } else if item.type == .autoTabSwitch {
                    HStack(spacing: 5) {
                        if item.isOn {
                            Button(action: {
                                AutoTabSwitchService.shared.switchTabNow()
                            }) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(red: 0.38, green: 0.75, blue: 0.98))
                            }
                            .buttonStyle(.plain)
                            .help("Switch Tab Immediately (Next Tab)")
                        }
                        
                        Menu {
                            Section("Switch Interval") {
                                ForEach(AutoTabSwitchService.shared.intervalPresets, id: \.seconds) { preset in
                                    Button(action: {
                                        AutoTabSwitchService.shared.setInterval(preset.seconds)
                                    }) {
                                        HStack {
                                            Text(preset.label)
                                            if AutoTabSwitchService.shared.switchInterval == preset.seconds {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Switch Direction") {
                                ForEach(TabSwitchDirection.allCases) { dir in
                                    Button(action: {
                                        AutoTabSwitchService.shared.setDirection(dir)
                                    }) {
                                        HStack {
                                            Text(dir.rawValue)
                                            if AutoTabSwitchService.shared.direction == dir {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Shortcut Style") {
                                ForEach(TabShortcutStyle.allCases) { style in
                                    Button(action: {
                                        AutoTabSwitchService.shared.setShortcutStyle(style)
                                    }) {
                                        HStack {
                                            Text(style.rawValue)
                                            if AutoTabSwitchService.shared.shortcutStyle == style {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Session Timer") {
                                ForEach(AutoTabSwitchService.shared.durationPresets, id: \.seconds) { preset in
                                    Button(action: {
                                        AutoTabSwitchService.shared.setDuration(preset.seconds)
                                    }) {
                                        HStack {
                                            Text(preset.label)
                                            if AutoTabSwitchService.shared.selectedDuration == preset.seconds {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                AutoTabSwitchService.shared.setKeepAwake(!AutoTabSwitchService.shared.keepAwake)
                            }) {
                                HStack {
                                    Text("Keep Screen Awake")
                                    if AutoTabSwitchService.shared.keepAwake {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            Button(action: {
                                AutoTabSwitchService.shared.setPlaySound(!AutoTabSwitchService.shared.playSound)
                            }) {
                                HStack {
                                    Text("Sound on Tab Switch")
                                    if AutoTabSwitchService.shared.playSound {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                AutoTabSwitchService.shared.requestAccessibilityPermission(forcePrompt: true)
                            }) {
                                HStack {
                                    Text("Accessibility Permission...")
                                    Image(systemName: AutoTabSwitchService.shared.isAccessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                AutoTabSwitchService.shared.switchTabNow()
                            }) {
                                HStack {
                                    Text("Switch Tab Now")
                                    Image(systemName: "arrow.forward.to.line")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.subtitle ?? AutoTabSwitchService.shared.statusSubtitle)
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .medium, design: .rounded))
                                    .foregroundColor(item.isOn ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .contextMenu {
                        Section("Auto Tab Switcher") {
                            ForEach(AutoTabSwitchService.shared.intervalPresets, id: \.seconds) { preset in
                                Button(action: {
                                    AutoTabSwitchService.shared.setInterval(preset.seconds)
                                }) {
                                    HStack {
                                        Text("Interval: \(preset.label)")
                                        if AutoTabSwitchService.shared.switchInterval == preset.seconds {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            AutoTabSwitchService.shared.requestAccessibilityPermission(forcePrompt: true)
                        }) {
                            HStack {
                                Text("Accessibility Permission...")
                                Image(systemName: AutoTabSwitchService.shared.isAccessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            AutoTabSwitchService.shared.switchTabNow()
                        }) {
                            HStack {
                                Text("Switch Tab Now")
                                Image(systemName: "arrow.forward.to.line")
                            }
                        }
                    }
                } else if item.type == .nightShift {
                    HStack(spacing: 5) {
                        if item.isOn {
                            // Slider to adjust Night Shift warmth / intensity
                            HStack(spacing: 3) {
                                Image(systemName: "sun.min")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.orange.opacity(0.65))
                                    .help("Cooler (Less Warm)")
                                
                                Slider(
                                    value: Binding(
                                        get: { Double(NightShiftService.shared.currentStrength) },
                                        set: { NightShiftService.shared.setStrength(Float($0)) }
                                    ),
                                    in: 0.1...1.0
                                )
                                .controlSize(.mini)
                                .frame(width: 58)
                                .accentColor(Color.orange)
                                .help("Night Shift Warmth: \(NightShiftService.shared.formattedStrength)")
                                
                                Image(systemName: "sun.max.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.orange)
                                    .help("Warmer (More Amber)")
                            }
                            
                            Menu {
                                Section("Night Shift Warmth") {
                                    ForEach(NightShiftService.shared.presets, id: \.strength) { preset in
                                        Button(action: {
                                            NightShiftService.shared.setStrength(preset.strength)
                                        }) {
                                            HStack {
                                                Text(preset.label)
                                                if abs(NightShiftService.shared.currentStrength - preset.strength) < 0.05 {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.displays") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    HStack {
                                        Text("Display Settings...")
                                        Image(systemName: "gearshape")
                                    }
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(NightShiftService.shared.formattedStrength)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.orange)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 7))
                                        .foregroundColor(Color.gray.opacity(0.6))
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        } else {
                            Menu {
                                Section("Preferred Warmth") {
                                    ForEach(NightShiftService.shared.presets, id: \.strength) { preset in
                                        Button(action: {
                                            NightShiftService.shared.setStrength(preset.strength)
                                        }) {
                                            HStack {
                                                Text(preset.label)
                                                if abs(NightShiftService.shared.currentStrength - preset.strength) < 0.05 {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.displays") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }) {
                                    HStack {
                                        Text("Display Settings...")
                                        Image(systemName: "gearshape")
                                    }
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text(item.subtitle ?? NightShiftService.shared.formattedStrength)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.gray.opacity(0.85))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8))
                                        .foregroundColor(Color.gray.opacity(0.6))
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                    .contextMenu {
                        Section("Night Shift Intensity") {
                            ForEach(NightShiftService.shared.presets, id: \.strength) { preset in
                                Button(action: {
                                    NightShiftService.shared.setStrength(preset.strength)
                                }) {
                                    HStack {
                                        Text(preset.label)
                                        if abs(NightShiftService.shared.currentStrength - preset.strength) < 0.05 {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.displays") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack {
                                Text("Display Settings...")
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                } else if item.type == .googlyEyes {
                    HStack(spacing: 5) {
                        if item.isOn {
                            // Slider to increase/decrease eye size
                            HStack(spacing: 3) {
                                Image(systemName: "eye")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.7))
                                    .help("Smaller eye size")
                                
                                Slider(
                                    value: Binding(
                                        get: { GooglyEyesService.shared.eyeScale },
                                        set: { GooglyEyesService.shared.setEyeScale($0) }
                                    ),
                                    in: 0.5...1.6
                                )
                                .controlSize(.mini)
                                .frame(width: 58)
                                .accentColor(Color(red: 0.28, green: 0.76, blue: 0.98))
                                .help("Eye Size: \(Int(GooglyEyesService.shared.eyeScale * 100))%")
                                
                                Image(systemName: "eye")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.white.opacity(0.85))
                                    .help("Larger eye size")
                            }
                            
                            Menu {
                                Section("Eye Size Presets") {
                                    Button("Tiny (50%)") { GooglyEyesService.shared.setEyeScale(0.5) }
                                    Button("Small (75%)") { GooglyEyesService.shared.setEyeScale(0.75) }
                                    Button("Default (100%)") { GooglyEyesService.shared.setEyeScale(1.0) }
                                    Button("Large (130%)") { GooglyEyesService.shared.setEyeScale(1.3) }
                                    Button("Giant (160%)") { GooglyEyesService.shared.setEyeScale(1.6) }
                                }
                                
                                Divider()
                                
                                Section("Emotions") {
                                    ForEach(EyeEmotion.allCases, id: \.self) { emotion in
                                        Button(action: {
                                            GooglyEyesService.shared.setManualEmotion(emotion)
                                        }) {
                                            HStack {
                                                Text(emotion.label)
                                                if GooglyEyesService.shared.currentEmotion == emotion {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    GooglyEyesService.shared.testBlink()
                                }) {
                                    HStack {
                                        Text("Double Blink 👀")
                                        Image(systemName: "eyes")
                                    }
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Text("\(Int(GooglyEyesService.shared.eyeScale * 100))%")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.98))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 7))
                                        .foregroundColor(Color.gray.opacity(0.6))
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        } else {
                            Menu {
                                Section("Eye Size Presets") {
                                    Button("Tiny (50%)") { GooglyEyesService.shared.setEyeScale(0.5) }
                                    Button("Small (75%)") { GooglyEyesService.shared.setEyeScale(0.75) }
                                    Button("Default (100%)") { GooglyEyesService.shared.setEyeScale(1.0) }
                                    Button("Large (130%)") { GooglyEyesService.shared.setEyeScale(1.3) }
                                    Button("Giant (160%)") { GooglyEyesService.shared.setEyeScale(1.6) }
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text("\(Int(GooglyEyesService.shared.eyeScale * 100))%")
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundColor(Color.gray.opacity(0.75))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 7))
                                        .foregroundColor(Color.gray.opacity(0.5))
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                } else if item.type == .volumeBoost {
                    HStack(spacing: 5) {
                        // FineTune-style 3-chevron stacked indicator
                        BoostChevronsView(
                            level: VolumeBoostService.shared.activeLevel,
                            onTap: {
                                VolumeBoostService.shared.cycleLevel()
                            }
                        )
                        
                        Menu {
                            ForEach(VolumeBoostLevel.activePresets) { level in
                                Button(action: {
                                    VolumeBoostService.shared.setLevel(level)
                                }) {
                                    HStack {
                                        Text(level.displayTitle)
                                        if VolumeBoostService.shared.activeLevel == level && VolumeBoostService.shared.isActive {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button(action: {
                                VolumeBoostService.shared.stop()
                            }) {
                                HStack {
                                    Text("Turn Off")
                                    if !VolumeBoostService.shared.isActive {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Divider()
                            Button(action: {
                                VolumeBoostService.openSystemSettingsPrivacy()
                            }) {
                                HStack {
                                    Text("Screen & Audio Permission...")
                                    Image(systemName: "hand.raised.fill")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(VolumeBoostService.shared.isActive ? VolumeBoostService.shared.selectedLevel.label : "Off")
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .regular, design: .rounded))
                                    .foregroundColor(item.isOn ? Color(red: 0.95, green: 0.45, blue: 0.25) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } else if item.type == .grammarCoach {
                    HStack(spacing: 6) {
                        if !GrammarCoachService.shared.isAccessibilityGranted {
                            Button(action: {
                                GrammarCoachService.shared.openAccessibilitySettings()
                            }) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                            .help("Accessibility permission needed for live typing auto-correct in other apps. Click to grant.")
                        }
                        
                        Button(action: {
                            GrammarCoachService.shared.showTypingBox()
                        }) {
                            Image(systemName: "character.textbox")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(item.isOn ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .help("Open Grammar Typing Box (Formal & Casual Polishing)")
                        
                        Menu {
                            Button(action: {
                                GrammarCoachService.shared.setStyle(.formal)
                            }) {
                                HStack {
                                    Text("👔 Formal Writing")
                                    if GrammarCoachService.shared.currentStyle == .formal {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button(action: {
                                GrammarCoachService.shared.setStyle(.casual)
                            }) {
                                HStack {
                                    Text("☕ Casual Writing")
                                    if GrammarCoachService.shared.currentStyle == .casual {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Divider()
                            Button(action: {
                                GrammarCoachService.shared.showTypingBox()
                            }) {
                                HStack {
                                    Text("Open Typing Box...")
                                    Image(systemName: "macwindow")
                                }
                            }
                            if !GrammarCoachService.shared.isAccessibilityGranted {
                                Divider()
                                Button(action: {
                                    GrammarCoachService.shared.openAccessibilitySettings()
                                }) {
                                    HStack {
                                        Text("Accessibility Permission...")
                                        Image(systemName: "hand.raised.fill")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.isOn ? (GrammarCoachService.shared.currentStyle == .formal ? "Formal" : "Casual") : "Off")
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .regular, design: .rounded))
                                    .foregroundColor(item.isOn ? (GrammarCoachService.shared.currentStyle == .formal ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color(red: 0.95, green: 0.65, blue: 0.25)) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } else if item.type == .systemMonitor {
                    HStack(spacing: 6) {
                        if item.isOn {
                            Button(action: {
                                SystemMonitorService.shared.togglePopover()
                            }) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
                            }
                            .buttonStyle(.plain)
                            .help("Open detailed live System Monitor popover")
                        }
                        
                        Menu {
                            ForEach(MonitorDisplayMode.allCases) { mode in
                                Button(action: {
                                    SystemMonitorService.shared.displayMode = mode
                                }) {
                                    HStack {
                                        Text(mode.label)
                                        if SystemMonitorService.shared.displayMode == mode {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button(action: {
                                SystemMonitorService.shared.togglePopover()
                            }) {
                                HStack {
                                    Text("Open Monitor Details...")
                                    Image(systemName: "gauge.with.needle")
                                }
                            }
                            Button(action: {
                                SystemMonitorService.shared.openActivityMonitor()
                            }) {
                                HStack {
                                    Text("Open Activity Monitor...")
                                    Image(systemName: "chart.bar.xaxis")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.isOn ? "Live" : "Off")
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .regular, design: .rounded))
                                    .foregroundColor(item.isOn ? Color(red: 0.22, green: 0.74, blue: 0.97) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } else if item.type == .loomRecorder {
                    HStack(spacing: 6) {
                        if item.isOn {
                            Button(action: {
                                LoomRecorderService.shared.triggerRecordingToggle()
                            }) {
                                Image(systemName: LoomRecorderService.shared.isRecording ? "stop.circle.fill" : "record.circle")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color.red)
                            }
                            .buttonStyle(.plain)
                            .help(LoomRecorderService.shared.isRecording ? "Stop Recording" : "Start Recording")
                        }
                        
                        Menu {
                            if LoomRecorderService.shared.isRecording {
                                Button(action: {
                                    LoomRecorderService.shared.stopRecording(discard: false)
                                }) {
                                    HStack {
                                        Text("Stop & Review Video")
                                        Image(systemName: "stop.fill")
                                    }
                                }
                                Button(action: {
                                    if LoomRecorderService.shared.isPaused {
                                        LoomRecorderService.shared.resumeRecording()
                                    } else {
                                        LoomRecorderService.shared.pauseRecording()
                                    }
                                }) {
                                    HStack {
                                        Text(LoomRecorderService.shared.isPaused ? "Resume Recording" : "Pause Recording")
                                        Image(systemName: LoomRecorderService.shared.isPaused ? "play.fill" : "pause.fill")
                                    }
                                }
                                Button(action: {
                                    LoomRecorderService.shared.restartRecording()
                                }) {
                                    HStack {
                                        Text("Restart Take")
                                        Image(systemName: "arrow.counterclockwise")
                                    }
                                }
                                Button(action: {
                                    LoomRecorderService.shared.stopRecording(discard: true)
                                }) {
                                    HStack {
                                        Text("Cancel & Trash")
                                        Image(systemName: "trash.fill")
                                    }
                                }
                                Divider()
                            } else if LoomRecorderService.shared.isSessionActive {
                                Button(action: {
                                    LoomRecorderService.shared.startCountdownAndRecord()
                                }) {
                                    HStack {
                                        Text("Start Recording (3s)")
                                        Image(systemName: "record.circle.fill")
                                    }
                                }
                                Divider()
                            }
                            
                            Menu("Camera Bubble Size") {
                                ForEach(LoomBubbleSize.allCases) { size in
                                    Button(action: {
                                        LoomRecorderService.shared.bubbleSize = size
                                    }) {
                                        HStack {
                                            Text(size.label)
                                            if LoomRecorderService.shared.bubbleSize == size {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Menu("Camera Bubble Shape") {
                                ForEach(LoomBubbleShape.allCases) { shape in
                                    Button(action: {
                                        LoomRecorderService.shared.bubbleShape = shape
                                    }) {
                                        HStack {
                                            Text(shape.rawValue)
                                            if LoomRecorderService.shared.bubbleShape == shape {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Button(action: {
                                LoomRecorderService.shared.isMicEnabled.toggle()
                            }) {
                                HStack {
                                    Text(LoomRecorderService.shared.isMicEnabled ? "Mute Microphone" : "Enable Microphone")
                                    Image(systemName: LoomRecorderService.shared.isMicEnabled ? "mic.fill" : "mic.slash.fill")
                                }
                            }
                            
                            Button(action: {
                                LoomRecorderService.shared.isMirrored.toggle()
                            }) {
                                HStack {
                                    Text(LoomRecorderService.shared.isMirrored ? "Unmirror Camera" : "Mirror Camera")
                                    Image(systemName: "arrow.left.and.right")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                LoomRecorderService.shared.openRecordingsFolder()
                            }) {
                                HStack {
                                    Text("Open Recordings Folder...")
                                    Image(systemName: "folder")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                if LoomRecorderService.shared.isRecording {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 6, height: 6)
                                    Text(LoomRecorderService.shared.formattedDuration)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color.red)
                                } else {
                                    Text(item.isOn ? "Ready" : "Off")
                                        .font(.system(size: 12, weight: item.isOn ? .bold : .regular, design: .rounded))
                                        .foregroundColor(item.isOn ? Color(red: 0.95, green: 0.35, blue: 0.35) : Color.gray.opacity(0.85))
                                }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } else if item.type == .autoVPN {
                    HStack(spacing: 6) {
                        if item.isOn {
                            Circle()
                                .fill(Color(red: 0.25, green: 0.85, blue: 0.50))
                                .frame(width: 6, height: 6)
                        }
                        
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 11.5, weight: item.isOn ? .medium : .regular))
                                .foregroundColor(item.isOn ? Color(red: 0.25, green: 0.85, blue: 0.50) : Color.gray.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .contextMenu {
                        if let serviceName = VPNService.shared.activeVPNServiceName {
                            Text("VPN Provider: \(serviceName)")
                        }
                        Button(action: {
                            VPNService.shared.fetchLiveIPAndLocation()
                        }) {
                            HStack {
                                Text("Refresh IP & Geo Location")
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        Divider()
                        Button(action: {
                            VPNService.shared.openNetworkSettings()
                        }) {
                            HStack {
                                Text("macOS VPN Settings...")
                                Image(systemName: "gearshape")
                            }
                        }
                        if VPNService.shared.isProtonVPNInstalled {
                            Button(action: {
                                VPNService.shared.openProtonVPNApp()
                            }) {
                                HStack {
                                    Text("Open ProtonVPN App...")
                                    Image(systemName: "arrow.up.forward.app")
                                }
                            }
                        }
                    }
                } else if item.type == .tidyFolders {
                    HStack(spacing: 6) {
                        if item.isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else if item.isOn {
                            Circle()
                                .fill(Color(red: 0.95, green: 0.65, blue: 0.25))
                                .frame(width: 6, height: 6)
                        }
                        
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 11.5, weight: item.isOn ? .medium : .regular))
                                .foregroundColor(item.isOn ? Color(red: 0.95, green: 0.65, blue: 0.25) : Color.gray.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .contextMenu {
                        Button(action: {
                            FolderTidyService.shared.tidyUpAll()
                        }) {
                            HStack {
                                Text("Tidy Desktop & Downloads")
                                Image(systemName: "sparkles")
                            }
                        }
                        Button(action: {
                            FolderTidyService.shared.tidyDesktopOnly()
                        }) {
                            HStack {
                                Text("Tidy Desktop Only")
                                Image(systemName: "display")
                            }
                        }
                        Button(action: {
                            FolderTidyService.shared.tidyDownloadsOnly()
                        }) {
                            HStack {
                                Text("Tidy Downloads Only")
                                Image(systemName: "arrow.down.circle")
                            }
                        }
                        
                        if FolderTidyService.shared.canUndo {
                            Divider()
                            Button(action: {
                                FolderTidyService.shared.undoLastTidy()
                            }) {
                                HStack {
                                    Text("Undo Last Tidy (Restore Files)")
                                    Image(systemName: "arrow.uturn.backward")
                                }
                            }
                        }
                        
                        Divider()
                        Button(action: {
                            FolderTidyService.shared.openFolder(type: .desktopDirectory)
                        }) {
                            HStack {
                                Text("Open Desktop Folder...")
                                Image(systemName: "folder")
                            }
                        }
                        Button(action: {
                            FolderTidyService.shared.openFolder(type: .downloadsDirectory)
                        }) {
                            HStack {
                                Text("Open Downloads Folder...")
                                Image(systemName: "folder")
                            }
                        }
                    }
                } else if item.type == .adblockDNS {
                    HStack(spacing: 6) {
                        Menu {
                            Section(header: Text("DNS Protection Profiles")) {
                                ForEach(DNSProfile.allCases) { profile in
                                    Button(action: {
                                        DNSService.shared.selectProfile(profile)
                                    }) {
                                        HStack {
                                            Text(profile.label)
                                            if DNSService.shared.selectedProfile == profile {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                DNSService.shared.flushDNSCache()
                            }) {
                                HStack {
                                    Text("Flush DNS Cache Now")
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                            
                            Button(action: {
                                DNSService.shared.openNetworkSettings()
                            }) {
                                HStack {
                                    Text("macOS DNS Settings...")
                                    Image(systemName: "gearshape")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                DNSService.shared.resetToDefault()
                            }) {
                                HStack {
                                    Text("Reset to Automatic (DHCP)")
                                    Image(systemName: "arrow.counterclockwise")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(DNSService.shared.selectedProfile.shortLabel)
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .medium, design: .rounded))
                                    .foregroundColor(item.isOn ? Color(red: 0.25, green: 0.85, blue: 0.50) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(item.isOn ? Color(red: 0.25, green: 0.85, blue: 0.50).opacity(0.85) : Color.gray.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    .contextMenu {
                        Section(header: Text("Select DNS Profile")) {
                            ForEach(DNSProfile.allCases) { profile in
                                Button(action: {
                                    DNSService.shared.selectProfile(profile)
                                }) {
                                    HStack {
                                        Text(profile.label)
                                        if DNSService.shared.selectedProfile == profile {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            DNSService.shared.flushDNSCache()
                        }) {
                            HStack {
                                Text("Flush DNS Cache")
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        
                        Button(action: {
                            DNSService.shared.openNetworkSettings()
                        }) {
                            HStack {
                                Text("Open macOS DNS Settings...")
                                Image(systemName: "gearshape")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            DNSService.shared.resetToDefault()
                        }) {
                            HStack {
                                Text("Reset to Automatic (DHCP)")
                                Image(systemName: "arrow.counterclockwise")
                            }
                        }
                    }
                } else if item.type == .knockScreenshot {
                    HStack(spacing: 6) {
                        Menu {
                            Section(header: Text("Knock Sensitivity")) {
                                ForEach(KnockSensitivity.allCases) { sens in
                                    Button(action: {
                                        KnockScreenshotService.shared.setSensitivity(sens)
                                    }) {
                                        HStack {
                                            Text(sens.rawValue)
                                            if KnockScreenshotService.shared.sensitivity == sens {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section(header: Text("Save Destination")) {
                                ForEach(KnockScreenshotDestination.allCases) { dest in
                                    Button(action: {
                                        KnockScreenshotService.shared.setDestination(dest)
                                    }) {
                                        HStack {
                                            Text(dest.rawValue)
                                            if KnockScreenshotService.shared.destination == dest {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section(header: Text("Feedback Effects")) {
                                Button(action: {
                                    KnockScreenshotService.shared.setFlashScreen(!KnockScreenshotService.shared.flashScreen)
                                }) {
                                    HStack {
                                        Text("Screen Flash Effect")
                                        if KnockScreenshotService.shared.flashScreen {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                
                                Button(action: {
                                    KnockScreenshotService.shared.setPlaySound(!KnockScreenshotService.shared.playSound)
                                }) {
                                    HStack {
                                        Text("Camera Shutter Sound")
                                        if KnockScreenshotService.shared.playSound {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                KnockScreenshotService.shared.takeScreenshotNow()
                            }) {
                                HStack {
                                    Text("Test Screenshot Now")
                                    Image(systemName: "camera")
                                }
                            }
                            
                            Button(action: {
                                KnockScreenshotService.shared.openScreenshotsFolder()
                            }) {
                                HStack {
                                    Text("Open Desktop Folder...")
                                    Image(systemName: "folder")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                KnockScreenshotService.shared.openMicrophoneSettings()
                            }) {
                                HStack {
                                    Text("Microphone Permission...")
                                    Image(systemName: "hand.raised.fill")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(KnockScreenshotService.shared.sensitivity.shortLabel)
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .medium, design: .rounded))
                                    .foregroundColor(item.isOn ? Color(red: 0.25, green: 0.85, blue: 0.50) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 11, weight: item.isOn ? .medium : .regular))
                                .foregroundColor(
                                    subtitle.contains("Knock 1")
                                        ? Color.yellow
                                        : (subtitle.contains("Capturing") || subtitle.contains("Captured")
                                            ? Color(red: 0.25, green: 0.85, blue: 0.50)
                                            : (item.isOn ? Color(red: 0.25, green: 0.85, blue: 0.50).opacity(0.85) : Color.gray.opacity(0.75)))
                                )
                                .lineLimit(1)
                        }
                    }
                    .contextMenu {
                        Section(header: Text("Knock Sensitivity")) {
                            ForEach(KnockSensitivity.allCases) { sens in
                                Button(action: {
                                    KnockScreenshotService.shared.setSensitivity(sens)
                                }) {
                                    HStack {
                                        Text(sens.rawValue)
                                        if KnockScreenshotService.shared.sensitivity == sens {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Section(header: Text("Save Destination")) {
                            ForEach(KnockScreenshotDestination.allCases) { dest in
                                Button(action: {
                                    KnockScreenshotService.shared.setDestination(dest)
                                }) {
                                    HStack {
                                        Text(dest.rawValue)
                                        if KnockScreenshotService.shared.destination == dest {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            KnockScreenshotService.shared.takeScreenshotNow()
                        }) {
                            HStack {
                                Text("Test Screenshot Now")
                                Image(systemName: "camera")
                            }
                        }
                        
                        Button(action: {
                            KnockScreenshotService.shared.openScreenshotsFolder()
                        }) {
                            HStack {
                                Text("Open Desktop Folder...")
                                Image(systemName: "folder")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            KnockScreenshotService.shared.openMicrophoneSettings()
                        }) {
                            HStack {
                                Text("Microphone Permission...")
                                Image(systemName: "hand.raised.fill")
                            }
                        }
                    }
                } else if item.type == .clipboardManager {
                    HStack(spacing: 6) {
                        if item.isOn {
                            Button(action: {
                                ClipboardService.shared.toggleWindow()
                            }) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(red: 0.38, green: 0.75, blue: 0.98))
                            }
                            .buttonStyle(.plain)
                            .help("Open Clipboard History window (or press F9 twice)")
                        }
                        
                        Menu {
                            Button(action: {
                                ClipboardService.shared.toggleWindow()
                            }) {
                                HStack {
                                    Text("Open Clipboard History (F9 x2)")
                                    Image(systemName: "macwindow")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                ClipboardService.shared.setAutoPaste(!ClipboardService.shared.autoPaste)
                            }) {
                                HStack {
                                    Text("Auto-Paste on Selection")
                                    if ClipboardService.shared.autoPaste {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                ClipboardService.shared.clearAllHistory()
                            }) {
                                HStack {
                                    Text("Clear History (\(ClipboardService.shared.items.count))")
                                    Image(systemName: "trash")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                ClipboardService.shared.resetWindowPosition()
                            }) {
                                HStack {
                                    Text("Reset Window Near Searchbar")
                                    Image(systemName: "arrow.counterclockwise")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                let current = ClipboardService.shared.isStandardFunctionKeysEnabled
                                ClipboardService.shared.setStandardFunctionKeys(!current)
                            }) {
                                HStack {
                                    Text("Use F1-F12 as Standard Keys")
                                    if ClipboardService.shared.isStandardFunctionKeysEnabled {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                ClipboardService.shared.openAccessibilitySettings()
                            }) {
                                HStack {
                                    Text("Accessibility Settings...")
                                    Image(systemName: "hand.raised.fill")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text("F9 ×2")
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .medium, design: .rounded))
                                    .foregroundColor(item.isOn ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 11, weight: item.isOn ? .medium : .regular))
                                .foregroundColor(item.isOn ? Color(red: 0.38, green: 0.75, blue: 0.98).opacity(0.85) : Color.gray.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    .contextMenu {
                        Button(action: {
                            ClipboardService.shared.toggleWindow()
                        }) {
                            HStack {
                                Text("Open Clipboard History (F9 x2)")
                                Image(systemName: "macwindow")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            ClipboardService.shared.setAutoPaste(!ClipboardService.shared.autoPaste)
                        }) {
                            HStack {
                                Text("Auto-Paste on Selection")
                                if ClipboardService.shared.autoPaste {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            ClipboardService.shared.clearAllHistory()
                        }) {
                            HStack {
                                Text("Clear History (\(ClipboardService.shared.items.count) items)")
                                Image(systemName: "trash")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            ClipboardService.shared.resetWindowPosition()
                        }) {
                            HStack {
                                Text("Reset Window Near Searchbar")
                                Image(systemName: "arrow.counterclockwise")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            let current = ClipboardService.shared.isStandardFunctionKeysEnabled
                            ClipboardService.shared.setStandardFunctionKeys(!current)
                        }) {
                            HStack {
                                Text("Use F1-F12 as Standard Keys")
                                if ClipboardService.shared.isStandardFunctionKeysEnabled {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            ClipboardService.shared.openAccessibilitySettings()
                        }) {
                            HStack {
                                Text("Accessibility Settings...")
                                Image(systemName: "hand.raised.fill")
                            }
                        }
                    }
                } else if item.type == .stickyNotes {
                    HStack(spacing: 6) {
                        Button(action: {
                            StickyNotesService.shared.createNote()
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.10))
                        }
                        .buttonStyle(.plain)
                        .help("Add New Sticky Note")
                        
                        Menu {
                            Button(action: {
                                StickyNotesService.shared.createNote()
                            }) {
                                HStack {
                                    Text("New Sticky Note")
                                    Image(systemName: "square.and.pencil")
                                }
                            }
                            
                            Button(action: {
                                StickyNotesService.shared.createNote(
                                    isChecklist: true,
                                    checklistItems: [StickyChecklistItem(title: "", isCompleted: false)]
                                )
                            }) {
                                HStack {
                                    Text("New To-Do Checklist")
                                    Image(systemName: "checklist")
                                }
                            }
                            
                            Divider()
                            
                            Section("Placement") {
                                Button(action: {
                                    StickyNotesService.shared.setPinAllToDesktop(true)
                                }) {
                                    HStack {
                                        Text("Pin All to Desktop (Home Page)")
                                        if StickyNotesService.shared.notes.allSatisfy({ $0.isPinnedToDesktop }) && !StickyNotesService.shared.notes.isEmpty {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                
                                Button(action: {
                                    StickyNotesService.shared.setPinAllToDesktop(false)
                                }) {
                                    HStack {
                                        Text("Float All on Top")
                                        if StickyNotesService.shared.notes.allSatisfy({ !$0.isPinnedToDesktop }) && !StickyNotesService.shared.notes.isEmpty {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Section("Default Color") {
                                ForEach(StickyNoteColor.allCases) { color in
                                    Button(action: {
                                        StickyNotesService.shared.setDefaultColor(color)
                                    }) {
                                        HStack {
                                            Text(color.title)
                                            if StickyNotesService.shared.defaultColor == color {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                StickyNotesService.shared.bringAllToFront()
                            }) {
                                HStack {
                                    Text("Bring All Notes to Front")
                                    Image(systemName: "arrow.up.forward.app")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                StickyNotesService.shared.deleteAllNotes()
                            }) {
                                HStack {
                                    Text("Delete All Notes (\(StickyNotesService.shared.notes.count))")
                                    Image(systemName: "trash")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.subtitle ?? StickyNotesService.shared.statusSubtitle)
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .medium, design: .rounded))
                                    .foregroundColor(item.isOn ? Color(red: 1.0, green: 0.82, blue: 0.10) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .contextMenu {
                        Button(action: {
                            StickyNotesService.shared.createNote()
                        }) {
                            HStack {
                                Text("New Sticky Note")
                                Image(systemName: "square.and.pencil")
                            }
                        }
                        
                        Button(action: {
                            StickyNotesService.shared.createNote(
                                isChecklist: true,
                                checklistItems: [StickyChecklistItem(title: "", isCompleted: false)]
                            )
                        }) {
                            HStack {
                                Text("New To-Do Checklist")
                                Image(systemName: "checklist")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            StickyNotesService.shared.setPinAllToDesktop(true)
                        }) {
                            HStack {
                                Text("Pin All to Desktop (Home Page)")
                                Image(systemName: "house.fill")
                            }
                        }
                        
                        Button(action: {
                            StickyNotesService.shared.setPinAllToDesktop(false)
                        }) {
                            HStack {
                                Text("Float All on Top")
                                Image(systemName: "pin.fill")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            StickyNotesService.shared.deleteAllNotes()
                        }) {
                            HStack {
                                Text("Delete All Notes")
                                Image(systemName: "trash")
                            }
                        }
                    }
                } else if item.type == .selfControl {
                    HStack(spacing: 6) {
                        Button(action: {
                            SelfControlWindowManager.shared.showWindow()
                        }) {
                            Image(systemName: "macwindow")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(red: 0.28, green: 0.85, blue: 0.56))
                        }
                        .buttonStyle(.plain)
                        .help("Open Self-Control & Recovery Tracker")
                        
                        Menu {
                            Button(action: {
                                SelfControlWindowManager.shared.showWindow()
                            }) {
                                HStack {
                                    Text("Open Recovery Tracker")
                                    Image(systemName: "shield.checkered")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                SelfControlService.shared.logUrgeVictory(trigger: "Menu Victory")
                            }) {
                                HStack {
                                    Text("Log Resisted Urge (+1 Victory)")
                                    Image(systemName: "checkmark.seal.fill")
                                }
                            }
                            
                            Divider()
                            
                            Button(action: {
                                SelfControlService.shared.toggleShield()
                            }) {
                                HStack {
                                    Text(SelfControlService.shared.isShieldActive ? "Disable Family Blocker" : "Enable Family Blocker")
                                    Image(systemName: SelfControlService.shared.isShieldActive ? "shield.slash" : "shield.fill")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(item.subtitle ?? SelfControlService.shared.statusSubtitle)
                                    .font(.system(size: 12, weight: item.isOn ? .bold : .medium, design: .rounded))
                                    .foregroundColor(item.isOn ? Color(red: 0.28, green: 0.85, blue: 0.56) : Color.gray.opacity(0.85))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color.gray.opacity(0.6))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .contextMenu {
                        Button(action: {
                            SelfControlWindowManager.shared.showWindow()
                        }) {
                            HStack {
                                Text("Open Recovery Tracker")
                                Image(systemName: "shield.checkered")
                            }
                        }
                        
                        Button(action: {
                            SelfControlService.shared.logUrgeVictory(trigger: "Context Menu Victory")
                        }) {
                            HStack {
                                Text("Log Resisted Urge (+1 Victory)")
                                Image(systemName: "checkmark.seal.fill")
                            }
                        }
                    }
                } else if item.type == .autohideMenuBar {
                    Menu {
                        Section("Menu Bar Behavior") {
                            ForEach(MenuBarAutoHideMode.allCases) { mode in
                                Button(action: {
                                    SystemControlService.shared.setMenuBarAutoHideMode(mode)
                                }) {
                                    HStack {
                                        Text(mode.title)
                                        if SystemControlService.shared.currentMenuBarAutoHideMode == mode {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack {
                                Text("Desktop & Dock Settings...")
                                Image(systemName: "gearshape")
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(item.subtitle ?? SystemControlService.shared.currentMenuBarAutoHideMode.shortLabel)
                                .font(.system(size: 12, weight: item.isOn ? .bold : .medium, design: .rounded))
                                .foregroundColor(item.isOn ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color.gray.opacity(0.85))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(Color.gray.opacity(0.6))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .contextMenu {
                        Section("Menu Bar Behavior") {
                            ForEach(MenuBarAutoHideMode.allCases) { mode in
                                Button(action: {
                                    SystemControlService.shared.setMenuBarAutoHideMode(mode)
                                }) {
                                    HStack {
                                        Text(mode.title)
                                        if SystemControlService.shared.currentMenuBarAutoHideMode == mode {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.gray.opacity(0.85))
                }
            }
            
            Spacer()
            
            // Right Control: Toggle or Action Button
            if item.isActionOnly {
                Button(action: {
                    onAction?()
                }) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            } else {
                Toggle("", isOn: Binding(
                    get: { item.isOn },
                    set: { newValue in
                        onToggle(newValue)
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                .labelsHidden()
                .disabled(item.isLoading)
                .opacity(item.isLoading ? 0.6 : 1.0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3.8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.isHovered ? Color(red: 0.16, green: 0.22, blue: 0.32).opacity(0.7) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                item.isHovered = hovering
            }
        }
    }
}

public struct BoostChevronsView: View {
    let level: VolumeBoostLevel
    let onTap: () -> Void
    
    public init(level: VolumeBoostLevel, onTap: @escaping () -> Void) {
        self.level = level
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: -3) {
                ForEach((0..<3).reversed(), id: \.self) { index in
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(
                            index < level.litChevronsCount
                                ? Color(red: 0.95, green: 0.45, blue: 0.25)
                                : Color.white.opacity(0.2)
                        )
                }
            }
            .frame(width: 14, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Volume Boost: \(level.label). Click to cycle level.")
    }
}

