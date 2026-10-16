import Foundation
import CoreGraphics

public final class WidgetGenerator: @unchecked Sendable {
    public static let shared = WidgetGenerator()
    
    private init() {}
    
    public func generate(from prompt: String, theme: String = "glass") -> (name: String, category: String, width: CGFloat, height: CGFloat) {
        let p = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if p.contains("clock") || p.contains("time") || p.contains("analog") || p.contains("digital") || p.contains("date") {
            return ("Clock & Date", "clock", 300, 150)
        } else if p.contains("crypto") || p.contains("bitcoin") || p.contains("btc") || p.contains("eth") || p.contains("stock") || p.contains("market") {
            return ("Crypto Markets", "crypto", 300, 190)
        } else if p.contains("pomodoro") || p.contains("timer") || p.contains("focus") || p.contains("stopwatch") {
            return ("Pomodoro Focus", "pomodoro", 280, 160)
        } else if p.contains("system") || p.contains("gauge") || p.contains("cpu") || p.contains("ram") || p.contains("battery") || p.contains("monitor") {
            return ("System Gauges", "gauges", 300, 160)
        } else if p.contains("todo") || p.contains("task") || p.contains("checklist") || p.contains("note") || p.contains("scratchpad") {
            return ("Quick Tasks", "todo", 300, 200)
        } else if p.contains("weather") || p.contains("forecast") || p.contains("temp") || p.contains("rain") || p.contains("sun") {
            return ("Atmosphere & Weather", "weather", 300, 140)
        } else if p.contains("habit") || p.contains("streak") || p.contains("tracker") || p.contains("goal") {
            return ("Daily Habit Streak", "habit", 300, 150)
        } else if p.contains("calc") || p.contains("math") || p.contains("calculator") {
            return ("Glass Calculator", "calc", 250, 250)
        } else if p.contains("countdown") || p.contains("days until") || p.contains("event") || p.contains("deadline") {
            return ("Event Countdown", "countdown", 300, 140)
        } else if p.contains("quote") || p.contains("motivation") || p.contains("affirmation") || p.contains("wisdom") {
            return ("Daily Inspiration", "quote", 300, 140)
        } else {
            let title = prompt.capitalized
            let shortTitle = title.count > 20 ? String(title.prefix(18)) + "…" : title
            return (shortTitle, "custom", 300, 150)
        }
    }
}
