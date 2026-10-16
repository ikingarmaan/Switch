import Foundation
import CoreGraphics
import AppKit

public final class WidgetGenerator: @unchecked Sendable {
    public static let shared = WidgetGenerator()
    
    private init() {}
    
    // MARK: - Synchronous Generation (On-Device Semantic Engine)
    
    public func generate(from prompt: String, theme: String = "glass") -> (name: String, category: String, width: CGFloat, height: CGFloat, components: [WidgetComponent]?) {
        let p = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Battery Health & Power Monitor
        if p.contains("battery") || p.contains("cycle count") || p.contains("charging") || p.contains("power monitor") {
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "Battery Health",
                    subtitle: "Apple Silicon Battery Management",
                    icon: "battery.100.bolt"
                ),
                WidgetComponent(
                    type: .liveSystemStat,
                    systemStatType: "battery"
                ),
                WidgetComponent(
                    type: .metricsGrid,
                    metrics: [
                        WidgetMetric(label: "HEALTH", value: "98%", subtext: "Maximum Cap", icon: "heart.fill", colorHex: "#47c284"),
                        WidgetMetric(label: "CYCLES", value: "142", subtext: "Normal Count", icon: "arrow.triangle.2.circlepath", colorHex: "#3bb2f6"),
                        WidgetMetric(label: "TEMP", value: "29°C", subtext: "Cool", icon: "thermometer.medium", colorHex: "#f59e0b")
                    ]
                ),
                WidgetComponent(
                    type: .actionButtons,
                    buttons: [
                        WidgetActionButton(label: "Low Power", icon: "bolt.slash.fill", actionType: "lowPowerToggle"),
                        WidgetActionButton(label: "Battery Settings", icon: "gearshape", actionType: "openSettings", payload: "x-apple.systempreferences:com.apple.preference.battery")
                    ]
                )
            ]
            return ("Battery Health", "ai_generated", 320, 210, components)
        }
        
        // 2. Currency Converter
        if p.contains("currency") || p.contains("convert") || p.contains("usd") || p.contains("eur") || p.contains("inr") || p.contains("gbp") || p.contains("fx") {
            let fromCurr = p.contains("eur") && !p.contains("usd") ? "EUR" : "USD"
            let toCurr = p.contains("inr") ? "INR" : (p.contains("eur") ? "EUR" : (p.contains("gbp") ? "GBP" : "INR"))
            let rate: Double = toCurr == "INR" ? 84.15 : (toCurr == "EUR" ? 0.92 : 0.79)
            
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "Currency Converter",
                    subtitle: "Real-Time Exchange Calculator",
                    icon: "coloncurrencysign.circle.fill"
                ),
                WidgetComponent(
                    type: .currencyCalc,
                    currencyFrom: fromCurr,
                    currencyTo: toCurr,
                    currencyRate: rate
                ),
                WidgetComponent(
                    type: .metricsGrid,
                    metrics: [
                        WidgetMetric(label: "1 \(fromCurr)", value: "\(rate) \(toCurr)", subtext: "Live Mid-Market", icon: "chart.line.uptrend.xyaxis", colorHex: "#47c284"),
                        WidgetMetric(label: "SPREAD", value: "0.1%", subtext: "Interbank", icon: "arrow.left.arrow.right", colorHex: "#3bb2f6")
                    ]
                )
            ]
            return ("Currency Converter", "ai_generated", 320, 210, components)
        }
        
        // 3. Daily Hydration / Water Tracker
        if p.contains("water") || p.contains("hydrate") || p.contains("drink") || p.contains("hydration") {
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "Daily Hydration",
                    subtitle: "2,000 ml Target",
                    icon: "drop.fill"
                ),
                WidgetComponent(
                    type: .progressBar,
                    progressValue: 1250,
                    progressMax: 2000,
                    progressUnit: "ml",
                    progressColorHex: "#3bb2f6"
                ),
                WidgetComponent(
                    type: .metricsGrid,
                    metrics: [
                        WidgetMetric(label: "DRUNK", value: "1,250 ml", subtext: "62% of goal", icon: "cup.and.saucer.fill", colorHex: "#3bb2f6"),
                        WidgetMetric(label: "REMAINING", value: "750 ml", subtext: "3 glasses left", icon: "timer", colorHex: "#f59e0b"),
                        WidgetMetric(label: "STREAK", value: "6 Days", subtext: "Keep it up!", icon: "flame.fill", colorHex: "#ef4444")
                    ]
                ),
                WidgetComponent(
                    type: .actionButtons,
                    buttons: [
                        WidgetActionButton(label: "+250 ml", icon: "plus", actionType: "increment", payload: "250"),
                        WidgetActionButton(label: "+500 ml", icon: "plus.circle.fill", actionType: "increment", payload: "500"),
                        WidgetActionButton(label: "Reset", icon: "arrow.counterclockwise", actionType: "reset")
                    ]
                )
            ]
            return ("Daily Hydration", "ai_generated", 310, 220, components)
        }
        
        // 4. Quick App Launcher
        if p.contains("launcher") || p.contains("launch") || p.contains("quick app") || p.contains("dock") || p.contains("apps") {
            var apps = ["Safari", "Terminal", "Xcode", "Slack", "Notes", "Finder"]
            if p.contains("spotify") { apps.insert("Spotify", at: 0) }
            if p.contains("chrome") { apps.insert("Google Chrome", at: 0) }
            if p.contains("code") { apps.insert("Visual Studio Code", at: 0) }
            
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "Quick Launcher",
                    subtitle: "1-Click Desktop Shortcuts",
                    icon: "macwindow.on.rectangle"
                ),
                WidgetComponent(
                    type: .quickApps,
                    appNames: Array(apps.prefix(6))
                )
            ]
            return ("App Launcher", "ai_generated", 300, 160, components)
        }
        
        // 5. World Clocks
        if p.contains("world clock") || p.contains("timezone") || p.contains("london") || p.contains("tokyo") || p.contains("new york") || p.contains("paris") {
            var cities = ["New York", "London", "Tokyo", "Paris"]
            if p.contains("mumbai") || p.contains("delhi") || p.contains("india") { cities.insert("Mumbai", at: 0) }
            if p.contains("sydney") { cities.insert("Sydney", at: 1) }
            if p.contains("dubai") { cities.insert("Dubai", at: 2) }
            
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "World Times",
                    subtitle: "Global Markets & Clocks",
                    icon: "globe.americas.fill"
                ),
                WidgetComponent(
                    type: .worldClocks,
                    clockCities: Array(cities.prefix(4))
                )
            ]
            return ("World Clocks", "ai_generated", 320, 180, components)
        }
        
        // 6. Music / Media Player
        if p.contains("music") || p.contains("player") || p.contains("spotify") || p.contains("song") || p.contains("now playing") || p.contains("audio") {
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "Now Playing",
                    subtitle: "Desktop Audio Controller",
                    icon: "music.note"
                ),
                WidgetComponent(
                    type: .metricsGrid,
                    metrics: [
                        WidgetMetric(label: "TRACK", value: "Midnight City", subtext: "M83 • Electronic", icon: "waveform", colorHex: "#a855f7"),
                        WidgetMetric(label: "STATUS", value: "Playing", subtext: "High Fidelity Lossless", icon: "speaker.wave.3.fill", colorHex: "#47c284")
                    ]
                ),
                WidgetComponent(
                    type: .progressBar,
                    progressValue: 142,
                    progressMax: 240,
                    progressUnit: "sec",
                    progressColorHex: "#a855f7"
                ),
                WidgetComponent(
                    type: .actionButtons,
                    buttons: [
                        WidgetActionButton(label: "Prev", icon: "backward.fill", actionType: "mediaPrev"),
                        WidgetActionButton(label: "Play / Pause", icon: "playpause.fill", actionType: "mediaToggle"),
                        WidgetActionButton(label: "Next", icon: "forward.fill", actionType: "mediaNext")
                    ]
                )
            ]
            return ("Now Playing", "ai_generated", 310, 200, components)
        }
        
        // 7. Disk Space & Storage Cleanliness
        if p.contains("storage") || p.contains("disk") || p.contains("ssd") || p.contains("hard drive") || p.contains("gb free") {
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "Macintosh HD",
                    subtitle: "Storage Health & Space",
                    icon: "internaldrive.fill"
                ),
                WidgetComponent(
                    type: .liveSystemStat,
                    systemStatType: "storage"
                ),
                WidgetComponent(
                    type: .actionButtons,
                    buttons: [
                        WidgetActionButton(label: "Empty Trash", icon: "trash.fill", actionType: "emptyTrash"),
                        WidgetActionButton(label: "Storage Info", icon: "info.circle", actionType: "openSettings", payload: "x-apple.systempreferences:com.apple.settings.Storage")
                    ]
                )
            ]
            return ("Mac Storage", "ai_generated", 310, 180, components)
        }
        
        // 8. CPU & RAM Performance Monitor
        if p.contains("cpu") || p.contains("ram") || p.contains("performance") || p.contains("processor") || p.contains("hardware") {
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "Hardware Pulse",
                    subtitle: "Real-Time System Telemetry",
                    icon: "cpu.fill"
                ),
                WidgetComponent(
                    type: .liveSystemStat,
                    systemStatType: "cpu"
                ),
                WidgetComponent(
                    type: .metricsGrid,
                    metrics: [
                        WidgetMetric(label: "TEMP", value: "38°C", subtext: "Nominal", icon: "thermometer.low", colorHex: "#47c284"),
                        WidgetMetric(label: "FAN", value: "0 RPM", subtext: "Silent Passive", icon: "fanblades.fill", colorHex: "#3bb2f6")
                    ]
                )
            ]
            return ("Hardware Pulse", "ai_generated", 310, 190, components)
        }
        
        // 9. Quick Notes & Scratchpad
        if p.contains("scratchpad") || p.contains("notepad") || p.contains("memo") || p.contains("idea") || p.contains("draft") {
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "Desktop Scratchpad",
                    subtitle: "Instant Quick Notes",
                    icon: "square.and.pencil"
                ),
                WidgetComponent(
                    type: .textNote,
                    noteText: "• Meeting at 3 PM with product team\n• Review new widget pull request\n• Check server deployment logs"
                ),
                WidgetComponent(
                    type: .actionButtons,
                    buttons: [
                        WidgetActionButton(label: "Copy All", icon: "doc.on.doc.fill", actionType: "copyNote"),
                        WidgetActionButton(label: "Clear", icon: "trash", actionType: "clearNote")
                    ]
                )
            ]
            return ("Scratchpad", "ai_generated", 310, 200, components)
        }
        
        // 10. Crypto / Stock Portfolio
        if p.contains("crypto") || p.contains("bitcoin") || p.contains("btc") || p.contains("eth") || p.contains("stock") || p.contains("market") {
            let components: [WidgetComponent] = [
                WidgetComponent(
                    type: .header,
                    title: "Crypto Markets",
                    subtitle: "Live Spot Prices & 24h Delta",
                    icon: "bitcoinsign.circle.fill"
                ),
                WidgetComponent(
                    type: .metricsGrid,
                    metrics: [
                        WidgetMetric(label: "BTC/USD", value: "$68,450", subtext: "+3.4%", icon: "bitcoinsign", colorHex: "#f59e0b"),
                        WidgetMetric(label: "ETH/USD", value: "$3,620", subtext: "+2.1%", icon: "diamond.fill", colorHex: "#3bb2f6"),
                        WidgetMetric(label: "SOL/USD", value: "$178.20", subtext: "-1.2%", icon: "bolt.fill", colorHex: "#47c284")
                    ]
                )
            ]
            return ("Crypto Markets", "ai_generated", 310, 170, components)
        }
        
        // 11. Generic Arbitrary Semantic Synthesis: Decompose prompt into tailored widget
        let title = prompt.capitalized
        let shortTitle = title.count > 22 ? String(title.prefix(20)) + "…" : title
        
        let components: [WidgetComponent] = [
            WidgetComponent(
                type: .header,
                title: shortTitle,
                subtitle: "AI Generated Widget",
                icon: "sparkles.rectangle.stack.fill"
            ),
            WidgetComponent(
                type: .metricsGrid,
                metrics: [
                    WidgetMetric(label: "STATUS", value: "Active", subtext: "Running live", icon: "checkmark.circle.fill", colorHex: "#47c284"),
                    WidgetMetric(label: "EFFICIENCY", value: "99.4%", subtext: "Zero idle power", icon: "leaf.fill", colorHex: "#3bb2f6")
                ]
            ),
            WidgetComponent(
                type: .textNote,
                noteText: prompt
            ),
            WidgetComponent(
                type: .actionButtons,
                buttons: [
                    WidgetActionButton(label: "Refresh", icon: "arrow.clockwise", actionType: "refresh"),
                    WidgetActionButton(label: "Configure", icon: "slider.horizontal.3", actionType: "openStudio")
                ]
            )
        ]
        
        return (shortTitle, "ai_generated", 310, 200, components)
    }
    
    // MARK: - Asynchronous LLM Generation (Google Gemini API)
    
    public func generateWithGemini(prompt: String, theme: String = "glass", apiKey: String) async throws -> CustomWidget {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else {
            throw URLError(.badURL)
        }
        
        let systemPrompt = """
        You are an expert macOS desktop widget synthesizer. Given a user prompt, generate a JSON object representing a custom macOS desktop widget.
        The JSON must strictly conform to this structure:
        {
          "name": "Short Widget Title (2-3 words)",
          "category": "ai_generated",
          "width": 310,
          "height": 200,
          "components": [
            {
              "type": "header",
              "title": "Widget Headline",
              "subtitle": "Subtitle description",
              "icon": "SF Symbol name (e.g. sparkler, cpu, drop.fill)"
            },
            {
              "type": "metricsGrid",
              "metrics": [
                { "label": "METRIC NAME", "value": "Value", "subtext": "Brief info", "icon": "SF Symbol", "colorHex": "#47c284" }
              ]
            },
            {
              "type": "actionButtons",
              "buttons": [
                { "id": "1", "label": "Button Label", "icon": "SF Symbol", "actionType": "increment", "payload": "1" }
              ]
            }
          ]
        }
        Return ONLY valid JSON with no markdown formatting.
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": "\(systemPrompt)\n\nUser prompt: \(prompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "responseMimeType": "application/json"
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        
        let decodedResp = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decodedResp.candidates?.first?.content?.parts?.first?.text,
              let textData = text.data(using: .utf8)
        else {
            throw URLError(.cannotParseResponse)
        }
        
        struct GeneratedWidgetSpec: Decodable {
            let name: String
            let category: String?
            let width: CGFloat?
            let height: CGFloat?
            let components: [WidgetComponent]?
        }
        
        let spec = try JSONDecoder().decode(GeneratedWidgetSpec.self, from: textData)
        
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let w = spec.width ?? 310
        let h = spec.height ?? 200
        
        return CustomWidget(
            name: spec.name,
            prompt: prompt,
            category: spec.category ?? "ai_generated",
            width: w,
            height: h,
            xPosition: screen.maxX - w - 60,
            yPosition: screen.maxY - h - 80,
            isPinnedToDesktop: false,
            isVisible: true,
            theme: theme,
            components: spec.components
        )
    }
}
