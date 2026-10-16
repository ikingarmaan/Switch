import SwiftUI

// MARK: - View State (No @State macro to avoid SwiftUIMacros compiler issues)
public final class WidgetStudioViewState: ObservableObject {
    @Published public var promptText: String = ""
    @Published public var selectedTheme: String = "glass"
    @Published public var isGenerating: Bool = false
    @Published public var previewWidget: CustomWidget?
    @Published public var successToast: String?
    @Published public var geminiApiKey: String = UserDefaults.standard.string(forKey: "switch.geminiApiKey") ?? "" {
        didSet {
            UserDefaults.standard.set(geminiApiKey, forKey: "switch.geminiApiKey")
        }
    }
    @Published public var showApiConfig: Bool = false
    
    public init() {}
}

public struct WidgetStudioView: View {
    @ObservedObject private var studio = WidgetStudioService.shared
    @StateObject private var state = WidgetStudioViewState()
    
    private let promptSuggestions: [(label: String, prompt: String)] = [
        ("🔋 Battery Health", "Live Apple Silicon battery health monitor with cycle count, health percentage, temperature and low power mode toggle"),
        ("💱 Currency Converter", "Live currency converter calculating USD to INR exchange rates with instant calculator input"),
        ("💧 Water Tracker", "Daily hydration tracker with 2000ml goal progress bar, remaining glasses, and +250ml log buttons"),
        ("⚡ Hardware Pulse", "MacBook real-time hardware telemetry monitoring live CPU load, fan status, and RAM memory pressure"),
        ("💾 Disk & Storage", "Mac storage cleaner widget showing free SSD space in GB with quick Empty Trash action"),
        ("🚀 App Launcher", "Speed launcher widget with quick buttons to open Safari, Terminal, Notes, and Visual Studio Code"),
        ("🎵 Media Controls", "Compact desktop music controller with track name, play/pause and skip buttons"),
        ("🌍 World Clocks", "Global time tracker showing current time in Cupertino, London, Tokyo, and New Delhi"),
        ("📝 Scratchpad", "Quick desktop memo notepad to jot down urgent thoughts with one-click copy button"),
        ("⏳ Pomodoro Focus", "25-minute Pomodoro focus timer with session countdown, break switch, and start/pause"),
        ("📈 Crypto Markets", "Crypto market ticker showing Bitcoin, Ethereum, and Solana live prices and 24h delta"),
        ("✅ Quick Tasks", "Clean interactive todo checklist where I can type new tasks and check them off")
    ]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.28, green: 0.76, blue: 0.52), Color(red: 0.20, green: 0.55, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Widget Studio")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text("Type a prompt to generate and place interactive widgets on your Mac desktop")
                        .font(.system(size: 11.5))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Button(action: {
                    studio.toggleAllWidgets(!studio.isAnyWidgetActive)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: studio.isAnyWidgetActive ? "eye.fill" : "eye.slash.fill")
                        Text(studio.isAnyWidgetActive ? "Hide All" : "Show All")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(studio.isAnyWidgetActive ? Color(red: 0.28, green: 0.76, blue: 0.52) : .gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .background(Color.white.opacity(0.03))
            
            Divider().background(Color.white.opacity(0.08))
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Prompt Input Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PROMPT GENERATOR")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.gray)
                            .tracking(0.8)
                        
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                            
                            VStack(alignment: .leading, spacing: 8) {
                                TextField(
                                    "Describe the widget you want (e.g. Minimalist crypto ticker with BTC and ETH, or Neon analog clock)...",
                                    text: $state.promptText,
                                    axis: .vertical
                                )
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .lineLimit(3...4)
                                .padding(12)
                                
                                HStack {
                                    // Theme Picker
                                    HStack(spacing: 6) {
                                        Text("Theme:")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.gray)
                                        
                                        Picker("", selection: $state.selectedTheme) {
                                            Text("Frosted Glass").tag("glass")
                                            Text("Cyberpunk Neon").tag("neon")
                                            Text("Sunset Acrylic").tag("sunset")
                                            Text("Minimalist").tag("minimal")
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                        .frame(width: 130)
                                    }
                                    
                                    // Cloud AI Key Button
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            state.showApiConfig.toggle()
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: state.geminiApiKey.isEmpty ? "sparkle" : "sparkles")
                                                .foregroundColor(state.geminiApiKey.isEmpty ? .gray : Color(red: 0.28, green: 0.76, blue: 0.52))
                                            Text(state.geminiApiKey.isEmpty ? "Cloud AI (Optional)" : "Gemini API Active")
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundColor(state.geminiApiKey.isEmpty ? .gray : .white)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Optionally connect Google Gemini API for cloud LLM widget generation. On-device engine works without key.")
                                    
                                    Spacer()
                                    
                                    // Generate Button
                                    Button(action: generateWidget) {
                                        HStack(spacing: 6) {
                                            if state.isGenerating {
                                                ProgressView()
                                                    .scaleEffect(0.6)
                                            } else {
                                                Image(systemName: "sparkles")
                                            }
                                            Text("Generate & Place on Desktop")
                                        }
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(Color(red: 0.05, green: 0.08, blue: 0.12))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            LinearGradient(
                                                colors: [Color(red: 0.28, green: 0.76, blue: 0.52), Color(red: 0.35, green: 0.85, blue: 0.65)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(state.promptText.trimmingCharacters(in: .whitespaces).isEmpty || state.isGenerating)
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 10)
                                
                                if state.showApiConfig {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: "key.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                                            Text("Google Gemini API Key (Optional — On-Device Semantic Synthesis runs instantly without key)")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.85))
                                            Spacer()
                                        }
                                        
                                        HStack(spacing: 8) {
                                            SecureField("Paste AIzaSy... (Saved locally)", text: $state.geminiApiKey)
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.white)
                                                .padding(6)
                                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                                            
                                            if !state.geminiApiKey.isEmpty {
                                                Button("Clear") {
                                                    state.geminiApiKey = ""
                                                }
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 10)
                                }
                            }
                        }
                        
                        // Inspiration Chips
                        VStack(alignment: .leading, spacing: 6) {
                            Text("QUICK INSPIRATIONS (CLICK TO FILL)")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.gray.opacity(0.8))
                                .tracking(0.5)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
                                ForEach(promptSuggestions, id: \.label) { item in
                                    Button(action: {
                                        state.promptText = item.prompt
                                    }) {
                                        Text(item.label)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white.opacity(0.85))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .frame(maxWidth: .infinity)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    if let toast = state.successToast {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.28, green: 0.76, blue: 0.52))
                            Text(toast)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.28, green: 0.76, blue: 0.52).opacity(0.15)))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    // Active Desktop Widgets Section
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("ACTIVE DESKTOP WIDGETS (\(studio.widgets.count))")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(.gray)
                                .tracking(0.8)
                            Spacer()
                        }
                        
                        if studio.widgets.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "macwindow.badge.plus")
                                    .font(.system(size: 28))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("No custom widgets yet")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Choose an inspiration above or type a prompt to generate your first live desktop widget.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
                        } else {
                            VStack(spacing: 8) {
                                ForEach(studio.widgets) { widget in
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(widget.isVisible ? Color(red: 0.28, green: 0.76, blue: 0.52) : Color.gray.opacity(0.4))
                                                .frame(width: 8, height: 8)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(widget.name)
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.white)
                                                
                                                Text(widget.isPinnedToDesktop ? "📌 Pinned to Wallpaper" : "🪟 Floating")
                                                    .font(.system(size: 9.5, weight: .medium))
                                                    .foregroundColor(.gray)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.white.opacity(0.06))
                                                    .cornerRadius(4)
                                            }
                                            
                                            Text(widget.prompt)
                                                .font(.system(size: 11))
                                                .foregroundColor(.gray)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer()
                                        
                                        // Pin/Float toggle
                                        Button(action: {
                                            studio.togglePin(id: widget.id)
                                        }) {
                                            Image(systemName: widget.isPinnedToDesktop ? "pin.fill" : "pin.slash")
                                                .font(.system(size: 11))
                                                .foregroundColor(widget.isPinnedToDesktop ? .accentColor : .gray)
                                                .padding(6)
                                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
                                        }
                                        .buttonStyle(.plain)
                                        .help(widget.isPinnedToDesktop ? "Pinned to Desktop (under windows)" : "Floating (above windows)")
                                        
                                        // Visibility toggle
                                        Button(action: {
                                            studio.toggleWidgetVisibility(id: widget.id)
                                        }) {
                                            Image(systemName: widget.isVisible ? "eye.fill" : "eye.slash.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(widget.isVisible ? Color(red: 0.28, green: 0.76, blue: 0.52) : .gray)
                                                .padding(6)
                                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
                                        }
                                        .buttonStyle(.plain)
                                        .help(widget.isVisible ? "Hide widget" : "Show widget on desktop")
                                        
                                        // Delete button
                                        Button(action: {
                                            studio.deleteWidget(id: widget.id)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundColor(.red.opacity(0.8))
                                                .padding(6)
                                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Delete widget")
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.94)
            }
        )
    }
    
    private func generateWidget() {
        let text = state.promptText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        state.isGenerating = true
        let apiKey = state.geminiApiKey.trimmingCharacters(in: .whitespaces)
        
        Task {
            let created = await studio.createAndSpawnWidgetAsync(
                prompt: text,
                theme: state.selectedTheme,
                apiKey: apiKey.isEmpty ? nil : apiKey
            )
            
            await MainActor.run {
                state.isGenerating = false
                state.promptText = ""
                state.successToast = "✨ Generated & Placed '\(created.name)' on your desktop! You can drag it anywhere."
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation {
                        state.successToast = nil
                    }
                }
            }
        }
    }
}
