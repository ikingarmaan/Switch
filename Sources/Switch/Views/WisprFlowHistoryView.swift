import SwiftUI

final class WisprFlowHistoryViewState: ObservableObject {
    @Published var searchText: String = ""
    @Published var showingSettings: Bool = false
    @Published var copiedId: UUID? = nil
}

public struct WisprFlowHistoryView: View {
    @ObservedObject private var service = WisprFlowService.shared
    @StateObject private var state = WisprFlowHistoryViewState()
    
    public init() {}
    
    public var filteredItems: [WisprDictationItem] {
        if state.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return service.recentDictations
        }
        return service.recentDictations.filter {
            $0.text.localizedCaseInsensitiveContains(state.searchText)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 10) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(red: 0.65, green: 0.45, blue: 0.98))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wispr Flow Voice Dictation")
                        .font(.system(size: 15, weight: .bold))
                    Text("Hinglish & English AI Voice to Text")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        state.showingSettings.toggle()
                    }
                }) {
                    Image(systemName: state.showingSettings ? "clock.arrow.circlepath" : "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(red: 0.65, green: 0.45, blue: 0.98))
                }
                .buttonStyle(.plain)
                .help(state.showingSettings ? "View History" : "Configure AI Engines & API Keys")
                
                if !service.recentDictations.isEmpty && !state.showingSettings {
                    Button(action: {
                        service.clearHistory()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear History")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
            
            Divider()
            
            if state.showingSettings {
                // Settings Section
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // AI Engine Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SPEECH RECOGNITION ENGINE")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            ForEach(WisprEngine.allCases) { eng in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(eng.title)
                                            .font(.system(size: 12.5, weight: service.engine == eng ? .semibold : .regular))
                                    }
                                    Spacer()
                                    if service.engine == eng {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Color(red: 0.65, green: 0.45, blue: 0.98))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(service.engine == eng ? Color.purple.opacity(0.12) : Color.clear)
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    service.engine = eng
                                }
                            }
                        }
                        
                        Divider()
                        
                        // API Keys
                        VStack(alignment: .leading, spacing: 12) {
                            Text("API KEYS CONFIGURATION")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Google Gemini API Key (Best for Hinglish)")
                                        .font(.system(size: 11.5, weight: .medium))
                                    Spacer()
                                    if !service.geminiApiKey.isEmpty {
                                        Text("Configured ✓")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                    }
                                }
                                SecureField("AIzaSy...", text: $service.geminiApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Groq API Key (Ultra-Fast 200ms Whisper)")
                                        .font(.system(size: 11.5, weight: .medium))
                                    Spacer()
                                    if !service.groqApiKey.isEmpty {
                                        Text("Configured ✓")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                    }
                                }
                                SecureField("gsk_...", text: $service.groqApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("OpenAI API Key")
                                        .font(.system(size: 11.5, weight: .medium))
                                    Spacer()
                                    if !service.openAIApiKey.isEmpty {
                                        Text("Configured ✓")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                    }
                                }
                                SecureField("sk-...", text: $service.openAIApiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            
                            Text("💡 Note: If no API key is provided, Wispr Flow automatically falls back to Apple Native On-Device Speech Recognition (100% offline & free)!")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Dictation Preferences
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PREFERENCES")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            Toggle("Auto-Paste into Active Application (⌘V)", isOn: $service.autoPaste)
                                .font(.system(size: 12))
                            
                            Toggle("Auto-Press Return (Enter) after Paste", isOn: $service.autoPressReturn)
                                .font(.system(size: 12))
                            
                            Toggle("Automatically Remove Filler Words (um, uh, matlab, etc.)", isOn: $service.removeFillerWords)
                                .font(.system(size: 12))
                            
                            Toggle("Smart Punctuation & Capitalization", isOn: $service.autoFormatPunctuation)
                                .font(.system(size: 12))
                            
                            Toggle("Sound Effects on Start / Stop", isOn: $service.soundFeedback)
                                .font(.system(size: 12))
                        }
                    }
                    .padding(16)
                }
            } else {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search transcribed dictations...", text: $state.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !state.searchText.isEmpty {
                        Button(action: { state.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                
                Divider()
                
                // History List
                if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "mic.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(state.searchText.isEmpty ? "No Voice Dictations Yet" : "No matching transcriptions")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Press ⌥ Space or F8 anywhere to start dictating in Hinglish or English!")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredItems) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.language)
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.15))
                                            .foregroundColor(Color(red: 0.65, green: 0.45, blue: 0.98))
                                            .cornerRadius(4)
                                        
                                        Text("·  \(item.engine)")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                        
                                        Spacer()
                                        
                                        Text(item.formattedTime)
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                        
                                        Button(action: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(item.text, forType: .string)
                                            state.copiedId = item.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                if state.copiedId == item.id {
                                                    state.copiedId = nil
                                                }
                                            }
                                        }) {
                                            HStack(spacing: 3) {
                                                Image(systemName: state.copiedId == item.id ? "checkmark" : "doc.on.doc")
                                                Text(state.copiedId == item.id ? "Copied" : "Copy")
                                            }
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundColor(state.copiedId == item.id ? .green : Color(red: 0.35, green: 0.78, blue: 0.98))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Text(item.text)
                                        .font(.system(size: 12.5))
                                        .lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }
}
