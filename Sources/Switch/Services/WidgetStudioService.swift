import Cocoa
import SwiftUI
import Combine

public extension Notification.Name {
    static let widgetStudioStateDidChange = Notification.Name("SwitchWidgetStudioStateDidChange")
}

public final class WidgetStudioService: ObservableObject, @unchecked Sendable {
    public static let shared = WidgetStudioService()
    
    @Published public private(set) var widgets: [CustomWidget] = []
    @Published public private(set) var isAnyWidgetActive: Bool = false
    
    private var activePanels: [UUID: WidgetPanel] = [:]
    private var studioWindow: NSWindow?
    
    private var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = base.appendingPathComponent("Switch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("custom_widgets.json")
    }
    
    public var statusSubtitle: String {
        let activeCount = widgets.filter { $0.isVisible }.count
        if activeCount > 0 {
            return "\(activeCount) active on desktop"
        } else if !widgets.isEmpty {
            return "\(widgets.count) created · Off"
        } else {
            return "Prompt to Widget Studio"
        }
    }
    
    private init() {
        loadWidgets()
        // Spawn active widgets on startup
        for widget in widgets where widget.isVisible {
            spawnPanel(for: widget)
        }
        updateActiveState()
    }
    
    // MARK: - Widget Creation & Spawning
    
    public func createAndSpawnWidget(prompt: String, theme: String = "glass") -> CustomWidget {
        let gen = WidgetGenerator.shared.generate(from: prompt, theme: theme)
        
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        // Offset each new widget slightly so they cascade nicely
        let cascadeOffset = CGFloat((widgets.count % 5) * 30)
        let initialX = screen.maxX - gen.width - 50 - cascadeOffset
        let initialY = screen.maxY - gen.height - 60 - cascadeOffset
        
        let widget = CustomWidget(
            name: gen.name,
            prompt: prompt,
            category: gen.category,
            width: gen.width,
            height: gen.height,
            xPosition: initialX,
            yPosition: initialY,
            isPinnedToDesktop: false,
            isVisible: true,
            theme: theme
        )
        
        widgets.insert(widget, at: 0)
        saveWidgets()
        
        spawnPanel(for: widget)
        updateActiveState()
        return widget
    }
    
    private func spawnPanel(for widget: CustomWidget) {
        if let existing = activePanels[widget.id] {
            existing.orderFront(nil)
            return
        }
        
        let panel = WidgetPanel(widget: widget)
        activePanels[widget.id] = panel
        panel.orderFront(nil)
    }
    
    public func toggleWidgetVisibility(id: UUID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].isVisible.toggle()
        
        if widgets[index].isVisible {
            spawnPanel(for: widgets[index])
        } else {
            activePanels[id]?.close()
            activePanels.removeValue(forKey: id)
        }
        
        saveWidgets()
        updateActiveState()
    }
    
    public func closeWidget(id: UUID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].isVisible = false
        activePanels[id]?.close()
        activePanels.removeValue(forKey: id)
        saveWidgets()
        updateActiveState()
    }
    
    public func deleteWidget(id: UUID) {
        activePanels[id]?.close()
        activePanels.removeValue(forKey: id)
        widgets.removeAll { $0.id == id }
        saveWidgets()
        updateActiveState()
    }
    
    public func togglePin(id: UUID) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].isPinnedToDesktop.toggle()
        activePanels[id]?.updatePinState(widgets[index].isPinnedToDesktop)
        saveWidgets()
    }
    
    private var savePositionWorkItem: DispatchWorkItem?
    
    public func updateWidgetPosition(id: UUID, x: CGFloat, y: CGFloat) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].xPosition = x
        widgets[index].yPosition = y
        
        savePositionWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveWidgets()
        }
        savePositionWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }
    
    public func toggleAllWidgets(_ enable: Bool) {
        for i in 0..<widgets.count {
            widgets[i].isVisible = enable
            if enable {
                spawnPanel(for: widgets[i])
            } else {
                activePanels[widgets[i].id]?.close()
                activePanels.removeValue(forKey: widgets[i].id)
            }
        }
        
        // If user enabled but had 0 widgets, generate a default clock widget to give an immediate amazing experience
        if enable && widgets.isEmpty {
            _ = createAndSpawnWidget(prompt: "Frosted glass live clock and greeting", theme: "glass")
        }
        
        saveWidgets()
        updateActiveState()
    }
    
    private func updateActiveState() {
        self.isAnyWidgetActive = widgets.contains { $0.isVisible }
        NotificationCenter.default.post(name: .widgetStudioStateDidChange, object: isAnyWidgetActive)
    }
    
    // MARK: - Persistence
    
    private func saveWidgets() {
        do {
            let data = try JSONEncoder().encode(widgets)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save custom widgets: \(error)")
        }
    }
    
    private func loadWidgets() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            self.widgets = try JSONDecoder().decode([CustomWidget].self, from: data)
        } catch {
            print("Failed to load custom widgets: \(error)")
        }
    }
    
    // MARK: - Studio Window
    
    public func openStudio() {
        if let window = studioWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 720, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Widget Studio"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        
        window.contentView = NSHostingView(rootView: WidgetStudioView())
        self.studioWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
