import SwiftUI
import AppKit

// MARK: - View State (ObservableObject to avoid SwiftUIMacros.StateMacro issue on CommandLineTools)
public final class SelfControlViewState: ObservableObject {
    public enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case sos = "Urge SOS"
        case roadmap = "90-Day Reboot"
        case checkin = "Daily Check-In"
        case reasons = "My Whys"
        case settings = "Settings"
        
        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .overview: return "flame.fill"
            case .sos: return "exclamationmark.shield.fill"
            case .roadmap: return "brain.head.profile"
            case .checkin: return "square.and.pencil"
            case .reasons: return "target"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    @Published public var selectedTab: Tab = .overview
    @Published public var breathPhase: String = "Inhale"
    @Published public var isBreathingExpanded: Bool = false
    @Published public var checkinIntensity: Double = 3.0
    @Published public var selectedHalt: Set<String> = []
    @Published public var checkinNotes: String = ""
    @Published public var checkinSavedNotice: Bool = false
    @Published public var newReasonText: String = ""
    @Published public var customDate: Date = Date()
    @Published public var relapseTrigger: String = ""
    @Published public var showResetConfirm: Bool = false
    
    public init() {}
}

public struct SelfControlView: View {
    @ObservedObject private var service = SelfControlService.shared
    @StateObject private var state = SelfControlViewState()
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 0.28, green: 0.85, blue: 0.56))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SELF CONTROL")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.white)
                        Text("Recovery & Reboot")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 14)
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.bottom, 8)
                
                // Tabs
                ForEach(SelfControlViewState.Tab.allCases) { tab in
                    Button(action: {
                        state.selectedTab = tab
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                            Text(tab.rawValue)
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                        }
                        .foregroundColor(state.selectedTab == tab ? .white : .white.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(state.selectedTab == tab ? Color(red: 0.28, green: 0.85, blue: 0.56).opacity(0.2) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Urge Emergency Quick Trigger
                Button(action: {
                    state.selectedTab = .sos
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bell.badge.fill")
                        Text("I Have An Urge")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 1.0, green: 0.35, blue: 0.45).opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 1.0, green: 0.35, blue: 0.45).opacity(0.4), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            .frame(width: 180)
            .background(Color(red: 0.10, green: 0.11, blue: 0.13))
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // Content Pane
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch state.selectedTab {
                    case .overview:
                        overviewPane
                    case .sos:
                        sosPane
                    case .roadmap:
                        roadmapPane
                    case .checkin:
                        checkinPane
                    case .reasons:
                        reasonsPane
                    case .settings:
                        settingsPane
                    }
                }
                .padding(24)
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        }
        .frame(minWidth: 680, minHeight: 620)
        .onAppear {
            state.customDate = service.startDate
            startBreathingAnimation()
        }
    }
    
    // MARK: - Tab 1: Overview
    private var overviewPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Hero Live Streak Card
            VStack(spacing: 16) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 0.28, green: 0.85, blue: 0.56))
                            .frame(width: 8, height: 8)
                        Text("ACTIVE RECOVERY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.28, green: 0.85, blue: 0.56))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.28, green: 0.85, blue: 0.56).opacity(0.12))
                    .cornerRadius(12)
                    
                    Spacer()
                    
                    Text("Started: \(service.startDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Clock units
                HStack(spacing: 14) {
                    timeUnit(val: "\(service.daysInt)", label: "DAYS")
                    timeSep
                    timeUnit(val: String(format: "%02d", service.hoursInt), label: "HOURS")
                    timeSep
                    timeUnit(val: String(format: "%02d", service.minutesInt), label: "MINUTES")
                    timeSep
                    timeUnit(val: String(format: "%02d", service.secondsInt), label: "SECONDS")
                }
                .padding(.vertical, 6)
                
                // 90-Day Reboot Progress
                VStack(spacing: 6) {
                    HStack {
                        Text("90-Day Neuroplasticity Reboot")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text(String(format: "%.1f%%", service.rebootPercentage))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 0.38, green: 0.82, blue: 0.98))
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 10)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.28, green: 0.85, blue: 0.56), Color(red: 0.38, green: 0.82, blue: 0.98)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(service.rebootPercentage / 100.0))), height: 10)
                        }
                    }
                    .frame(height: 10)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Three stat metrics
                HStack(spacing: 16) {
                    statBox(title: "Urges Defeated", value: "\(service.urgesResisted)", icon: "shield.fill", color: Color(red: 0.28, green: 0.85, blue: 0.56))
                    statBox(title: "Current Phase", value: service.currentPhaseTitle.components(separatedBy: ":").first ?? "Phase 1", icon: "brain", color: Color(red: 0.38, green: 0.82, blue: 0.98))
                    statBox(title: "Longest Streak", value: String(format: "%.1fd", service.longestStreakDays), icon: "trophy.fill", color: Color(red: 1.0, green: 0.78, blue: 0.25))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            
            // Shield Toggle Card
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(service.isShieldActive ? Color(red: 0.28, green: 0.85, blue: 0.56).opacity(0.2) : Color.white.opacity(0.06))
                        .frame(width: 44, height: 44)
                    Image(systemName: service.isShieldActive ? "shield.fill" : "shield.slash.fill")
                        .font(.system(size: 20))
                        .foregroundColor(service.isShieldActive ? Color(red: 0.28, green: 0.85, blue: 0.56) : .white.opacity(0.4))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac Adult Content Blocker")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Enforces Family DNS protection across all browsers, incognito tabs, and background network traffic.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { service.isShieldActive },
                    set: { service.setShield($0) }
                ))
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.28, green: 0.85, blue: 0.56)))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            )
            
            // Current Stage Insights
            VStack(alignment: .leading, spacing: 8) {
                Text(service.currentPhaseTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.38, green: 0.82, blue: 0.98))
                
                Text(phaseInsightText(days: service.daysClean))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .lineSpacing(3)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            )
        }
    }
    
    // MARK: - Tab 2: SOS Urge Center
    private var sosPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🚨 Emergency Grounding & Urge Surfer")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.55))
                Text("Urges peak in chemical intensity for 90 seconds. You do not need to fight it — breathe through it.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Breathing Circle
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.28, green: 0.85, blue: 0.56).opacity(state.isBreathingExpanded ? 0.25 : 0.1))
                        .frame(width: state.isBreathingExpanded ? 160 : 110, height: state.isBreathingExpanded ? 160 : 110)
                        .animation(.easeInOut(duration: 4.0), value: state.isBreathingExpanded)
                    
                    Circle()
                        .stroke(Color(red: 0.28, green: 0.85, blue: 0.56), lineWidth: 3)
                        .frame(width: state.isBreathingExpanded ? 140 : 100, height: state.isBreathingExpanded ? 140 : 100)
                        .animation(.easeInOut(duration: 4.0), value: state.isBreathingExpanded)
                    
                    VStack(spacing: 4) {
                        Text(state.breathPhase)
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.white)
                        Text("4 Seconds")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .frame(height: 180)
                
                Text("Deep belly breathing down-regulates adrenaline and shifts blood back to your rational prefrontal cortex.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            )
            
            // 5-4-3-2-1 Sensory Grounding
            VStack(alignment: .leading, spacing: 8) {
                Text("👀 5-4-3-2-1 Sensory Reality Shock")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("• **5 things** you can see right in front of you.")
                    Text("• **4 things** you can physically touch (keyboard, desk, shirt, floor).")
                    Text("• **3 sounds** you can hear in your environment.")
                    Text("• **2 scents** you can smell.")
                    Text("• **1 taste** on your tongue.")
                }
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.75))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            )
            
            // Physical Transmutation Card
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚡ Physical Transmutation")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text("Drop down and do 20 pushups or splash ice water on your face. Redirect your blood flow immediately.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                Button(action: {
                    service.logUrgeVictory(trigger: "Emergency Urge Surfer")
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("I Defeated It (+1)")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.28, green: 0.85, blue: 0.56))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            )
        }
    }
    
    // MARK: - Tab 3: Roadmap
    private var roadmapPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🧬 The 90-Day Brain Reboot Timeline")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text("What clinically occurs in your dopamine pathways as you heal:")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            VStack(spacing: 12) {
                roadmapStep(
                    title: "Days 1–3: The Acute Withdrawal",
                    meta: "Dopamine Starvation & Restlessness",
                    desc: "Your reward circuitry is shocked by the absence of artificial super-stimuli. Moodiness and strong cravings occur. A craving only lasts 15-20 minutes if you do not feed it attention.",
                    isCurrent: service.daysClean < 3
                )
                
                roadmapStep(
                    title: "Days 4–7: The Androgen Surge",
                    meta: "Testosterone & Drive Spike (Day 7 Peak)",
                    desc: "Scientific research documents a marked spike in androgen receptor sensitivity around Day 7. Energy surges. Channel this into heavy workouts, deep study, or creative work.",
                    isCurrent: service.daysClean >= 3 && service.daysClean < 7
                )
                
                roadmapStep(
                    title: "Days 8–14: Prefrontal Awakening",
                    meta: "Self-Control Reclaims Authority",
                    desc: "Your prefrontal cortex regains dominion over the limbic system. Urges turn from constant noise into gentle waves. Beware the temptation to 'just check if you're cured'.",
                    isCurrent: service.daysClean >= 7 && service.daysClean < 14
                )
                
                roadmapStep(
                    title: "Days 15–30: Fog Clearing & The Flatline",
                    meta: "Dopamine D2 Receptor Multiplication",
                    desc: "Mental fog lifts, concentration deepens. You may experience a temporary 'flatline' (low libido) — this is your nervous system getting much needed rest and healing.",
                    isCurrent: service.daysClean >= 14 && service.daysClean < 30
                )
                
                roadmapStep(
                    title: "Days 31–60: Deep Neural Rewiring",
                    meta: "Decoupling Addictive Reflexes",
                    desc: "Delta-FosB proteins that bonded porn pathways are steadily dismantling. Real-world social interaction and genuine intimacy feel magnetic and rewarding.",
                    isCurrent: service.daysClean >= 30 && service.daysClean < 60
                )
                
                roadmapStep(
                    title: "Days 61–90+: Unshakeable Mastery",
                    meta: "Baseline Restoration & Freedom",
                    desc: "Your baseline dopamine sensitivity is restored. Social anxiety diminishes, eye contact feels effortless, and self-respect is rock-solid.",
                    isCurrent: service.daysClean >= 60
                )
            }
        }
    }
    
    // MARK: - Tab 4: Check-In
    private var checkinPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("📝 Daily Reflection & HALT Tracker")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text("Track your internal weather to catch patterns before urges strike.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            VStack(alignment: .leading, spacing: 14) {
                // Slider
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Craving Intensity (1-10):")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Text("\(Int(state.checkinIntensity))")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(Color(red: 0.28, green: 0.85, blue: 0.56))
                    }
                    Slider(value: $state.checkinIntensity, in: 1...10, step: 1)
                        .tint(Color(red: 0.28, green: 0.85, blue: 0.56))
                }
                
                // HALT Tags
                VStack(alignment: .leading, spacing: 6) {
                    Text("Are You Experiencing Any Triggers? (HALT)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 8) {
                        ForEach(["Hungry", "Angry", "Lonely", "Tired", "Bored", "Stressed"], id: \.self) { tag in
                            let isSelected = state.selectedHalt.contains(tag)
                            Button(action: {
                                if isSelected {
                                    state.selectedHalt.remove(tag)
                                } else {
                                    state.selectedHalt.insert(tag)
                                }
                            }) {
                                Text(tag)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(isSelected ? Color(red: 0.28, green: 0.85, blue: 0.56) : .white.opacity(0.65))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? Color(red: 0.28, green: 0.85, blue: 0.56).opacity(0.2) : Color.white.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Notes
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reflections, Gratitude or Challenges:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    TextEditor(text: $state.checkinNotes)
                        .font(.system(size: 12))
                        .frame(height: 70)
                        .padding(6)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                }
                
                HStack {
                    Button(action: {
                        service.logCheckIn(
                            intensity: Int(state.checkinIntensity),
                            triggers: Array(state.selectedHalt),
                            notes: state.checkinNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        state.checkinNotes = ""
                        state.selectedHalt.removeAll()
                        state.checkinSavedNotice = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            state.checkinSavedNotice = false
                        }
                    }) {
                        Text("Save Daily Reflection")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.28, green: 0.85, blue: 0.56))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    if state.checkinSavedNotice {
                        Text("✓ Saved to recovery record!")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color(red: 0.28, green: 0.85, blue: 0.56))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            )
            
            // Past Log History
            if !service.checkins.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Past Reflections (\(service.checkins.count))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    
                    ForEach(service.checkins.prefix(5)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Text("Craving: \(item.intensity)/10")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(red: 0.38, green: 0.82, blue: 0.98))
                            }
                            if !item.triggers.isEmpty {
                                Text("Triggers: \(item.triggers.joined(separator: ", "))")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(Color(red: 0.28, green: 0.85, blue: 0.56))
                            }
                            if !item.notes.isEmpty {
                                Text(item.notes)
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - Tab 5: Reasons
    private var reasonsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🎯 My Core Reasons Why")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text("When cravings weaken willpower, core identity anchors you.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Add reason form
            HStack(spacing: 8) {
                TextField("Add a personal truth (e.g. To restore eye contact and confidence)...", text: $state.newReasonText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                
                Button(action: {
                    service.addReason(state.newReasonText)
                    state.newReasonText = ""
                }) {
                    Text("Add")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.28, green: 0.85, blue: 0.56))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(state.newReasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            // List of reasons
            VStack(spacing: 8) {
                ForEach(Array(service.personalReasons.enumerated()), id: \.offset) { index, reason in
                    HStack(spacing: 12) {
                        Text("“\(reason)”")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        Button(action: {
                            service.removeReason(at: index)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                    )
                }
            }
        }
    }
    
    // MARK: - Tab 6: Settings
    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("⚙️ Adjustments & Honest Reset")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text("Update your quit date or record a relapse with zero shame.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Adjust start date
            VStack(alignment: .leading, spacing: 10) {
                Text("Adjust Start Date:")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                
                HStack(spacing: 12) {
                    DatePicker("", selection: $state.customDate, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                    
                    Button(action: {
                        service.setCustomStartDate(state.customDate)
                    }) {
                        Text("Apply Date")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.28, green: 0.85, blue: 0.56))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            )
            
            // Compassionate Reset
            VStack(alignment: .leading, spacing: 10) {
                Text("Log Relapse / Reset Streak:")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.55))
                
                Text("Relapses are part of rewiring. A single slip does not wipe out your physical neural healing. Note the trigger and start anew.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.6))
                
                TextField("What triggered the relapse? (e.g. Phone in bed at 1 AM)...", text: $state.relapseTrigger)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                
                Button(action: {
                    state.showResetConfirm = true
                }) {
                    Text("Reset Streak & Save Trigger")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.55))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(red: 1.0, green: 0.45, blue: 0.55).opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .alert("Reset Streak?", isPresented: $state.showResetConfirm) {
                    Button("Reset Now", role: .destructive) {
                        service.resetStreak(trigger: state.relapseTrigger.isEmpty ? "Unspecified" : state.relapseTrigger)
                        state.relapseTrigger = ""
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your progress is saved to history. Stand up, wash your face, and continue the mission.")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
            )
        }
    }
    
    // MARK: - Helper Views & Functions
    private func timeUnit(val: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(val)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.32))
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.45))
        }
    }
    
    private var timeSep: some View {
        Text(":")
            .font(.system(size: 22, weight: .light))
            .foregroundColor(.white.opacity(0.2))
            .padding(.bottom, 12)
    }
    
    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func roadmapStep(title: String, meta: String, desc: String, isCurrent: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(isCurrent ? Color(red: 0.28, green: 0.85, blue: 0.56) : Color.white.opacity(0.2))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(isCurrent ? Color(red: 0.28, green: 0.85, blue: 0.56) : .white)
                    if isCurrent {
                        Text("• ACTIVE")
                            .font(.system(size: 9.5, weight: .black))
                            .foregroundColor(Color(red: 0.28, green: 0.85, blue: 0.56))
                    }
                }
                
                Text(meta)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.38, green: 0.82, blue: 0.98))
                
                Text(desc)
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.7))
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? Color(red: 0.28, green: 0.85, blue: 0.56).opacity(0.08) : Color(red: 0.12, green: 0.13, blue: 0.16))
        )
    }
    
    private func phaseInsightText(days: Double) -> String {
        if days < 3 {
            return "Your dopamine receptors are craving stimulation. Do not negotiate with urges. Keep screens out of private spaces."
        } else if days < 7 {
            return "Testosterone receptors are sensitizing. Turn this surge of energy into vigorous exercise or creative work."
        } else if days < 14 {
            return "Prefrontal authority is strengthening. The brain is quieting down. Stay alert against 'testing' yourself."
        } else if days < 30 {
            return "Brain fog is clearing. If you feel flat, trust that your neural circuits are undergoing deep restorative rest."
        } else if days < 60 {
            return "Old addiction highways are decaying. Healthy real-world desires are returning. Keep your standards high."
        } else {
            return "Dopamine baseline reset achieved! Unshakeable self-respect and presence. Maintain your habits."
        }
    }
    
    private func startBreathingAnimation() {
        var phaseIndex = 0
        let phases = [("Inhale", true), ("Hold", true), ("Exhale", false), ("Rest", false)]
        
        state.breathPhase = phases[0].0
        state.isBreathingExpanded = phases[0].1
        
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            phaseIndex = (phaseIndex + 1) % phases.count
            state.breathPhase = phases[phaseIndex].0
            state.isBreathingExpanded = phases[phaseIndex].1
        }
    }
}
