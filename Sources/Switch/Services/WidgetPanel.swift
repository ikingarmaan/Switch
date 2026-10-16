import Cocoa
import SwiftUI

public final class WidgetPanel: NSPanel {
    public let widgetId: UUID
    public var isPinnedToDesktop: Bool = false
    
    public init(widget: CustomWidget) {
        self.widgetId = widget.id
        self.isPinnedToDesktop = widget.isPinnedToDesktop
        
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1400, height: 900)
        let initialX = widget.xPosition > 0 ? widget.xPosition : (screenFrame.maxX - widget.width - 40)
        let initialY = widget.yPosition > 0 ? widget.yPosition : (screenFrame.maxY - widget.height - 40)
        
        let contentRect = NSRect(x: initialX, y: initialY, width: widget.width, height: widget.height)
        
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = isPinnedToDesktop ? .normal : .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let view = DynamicWidgetView(
            widget: widget,
            onClose: { [weak self] in
                guard let self = self else { return }
                WidgetStudioService.shared.closeWidget(id: self.widgetId)
            },
            onTogglePin: { [weak self] in
                guard let self = self else { return }
                WidgetStudioService.shared.togglePin(id: self.widgetId)
            }
        )
        
        self.contentView = NSHostingView(rootView: view)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMoveNotification(_:)),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }
    
    public func updatePinState(_ pinned: Bool) {
        self.isPinnedToDesktop = pinned
        self.level = pinned ? .normal : .floating
    }
    
    @objc private func windowDidMoveNotification(_ notification: Notification) {
        let origin = self.frame.origin
        WidgetStudioService.shared.updateWidgetPosition(id: widgetId, x: origin.x, y: origin.y)
    }
}
