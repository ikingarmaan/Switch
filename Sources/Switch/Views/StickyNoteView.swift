import SwiftUI
import AppKit

// MARK: - View State (No @State macros to prevent Swift compiler macro issues)
public final class StickyNoteViewState: ObservableObject {
    @Published public var isCopiedFeedback: Bool = false
    @Published public var isHoveringDelete: Bool = false
    @Published public var isHoveringCollapse: Bool = false
    @Published public var isHoveringPin: Bool = false
    @Published public var isHoveringAdd: Bool = false
    @Published public var isHoveringCopy: Bool = false
    
    public init() {}
}

// MARK: - Native Window Drag Area
public struct WindowDragAreaView: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> DragNSView {
        DragNSView()
    }
    
    public func updateNSView(_ nsView: DragNSView, context: Context) {}
    
    public final class DragNSView: NSView {
        public override var mouseDownCanMoveWindow: Bool { true }
        
        public override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Native Bottom-Right Resize Grip
public struct ResizeGripViewRepresentable: NSViewRepresentable {
    public init() {}
    
    public func makeNSView(context: Context) -> ResizeGripNSView {
        ResizeGripNSView()
    }
    
    public func updateNSView(_ nsView: ResizeGripNSView, context: Context) {}
    
    public final class ResizeGripNSView: NSView {
        private var initialFrame: NSRect = .zero
        private var initialMouseLocation: NSPoint = .zero
        
        public override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }
        
        public override func mouseDown(with event: NSEvent) {
            guard let window = window else { return }
            initialFrame = window.frame
            initialMouseLocation = NSEvent.mouseLocation
        }
        
        public override func mouseDragged(with event: NSEvent) {
            guard let window = window else { return }
            let currentMouse = NSEvent.mouseLocation
            let deltaX = currentMouse.x - initialMouseLocation.x
            let deltaY = currentMouse.y - initialMouseLocation.y
            
            let newWidth = max(200, initialFrame.width + deltaX)
            let newHeight = max(160, initialFrame.height - deltaY)
            let newY = initialFrame.origin.y + (initialFrame.height - newHeight)
            
            window.setFrame(NSRect(x: initialFrame.origin.x, y: newY, width: newWidth, height: newHeight), display: true)
        }
        
        public override func mouseUp(with event: NSEvent) {
            guard let window = window else { return }
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        }
    }
}

// MARK: - Native AppKit Text View for Multi-line Note Editing
public struct StickyNoteTextView: NSViewRepresentable {
    public var text: String
    public var textColor: NSColor
    public var placeholderText: String
    public var onTextChange: (String) -> Void
    
    public init(
        text: String,
        textColor: NSColor,
        placeholderText: String = "Type your note, reminder, or idea...",
        onTextChange: @escaping (String) -> Void
    ) {
        self.text = text
        self.textColor = textColor
        self.placeholderText = placeholderText
        self.onTextChange = onTextChange
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let textView = CustomStickyNSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        textView.placeholderText = placeholderText
        textView.textContainerInset = NSSize(width: 8, height: 4)
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }
    
    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let textView = scrollView.documentView as? CustomStickyNSTextView {
            if textView.string != text && !context.coordinator.isEditing {
                textView.string = text
            }
            textView.textColor = textColor
            textView.insertionPointColor = textColor
            textView.placeholderText = placeholderText
            textView.needsDisplay = true
        }
    }
    
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: StickyNoteTextView
        weak var textView: CustomStickyNSTextView?
        var isEditing = false
        
        init(_ parent: StickyNoteTextView) {
            self.parent = parent
        }
        
        public func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }
        
        public func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.onTextChange(tv.string)
        }
        
        public func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let tv = textView else { return }
            parent.onTextChange(tv.string)
        }
    }
}

public final class CustomStickyNSTextView: NSTextView {
    public var placeholderText: String = ""
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && !placeholderText.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 13.5),
                .foregroundColor: (textColor ?? NSColor.textColor).withAlphaComponent(0.42)
            ]
            let rect = NSRect(x: 12, y: 4, width: bounds.width - 24, height: bounds.height)
            placeholderText.draw(in: rect, withAttributes: attrs)
        }
    }
}

// MARK: - Colorful Sticky Note View
public struct StickyNoteView: View {
    public let noteId: UUID
    @ObservedObject public var service = StickyNotesService.shared
    @StateObject private var viewState = StickyNoteViewState()
    
    public init(noteId: UUID) {
        self.noteId = noteId
    }
    
    private var note: StickyNote? {
        service.notes.first(where: { $0.id == noteId })
    }
    
    public var body: some View {
        if let note = note {
            ZStack {
                // Card Background Gradient & Glass Highlight
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [note.color.topColor, note.color.bottomColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(note.color.borderColor, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 5)
                
                VStack(spacing: 0) {
                    // Header Bar (Draggable anywhere)
                    headerBar(note: note)
                    
                    if !note.isCollapsed {
                        Divider()
                            .background(note.color.borderColor.opacity(0.6))
                        
                        // Text Area
                        StickyNoteTextView(
                            text: note.content,
                            textColor: note.color.nsTextColor,
                            placeholderText: "Type your note, reminder, or idea...",
                            onTextChange: { newText in
                                service.updateNoteContent(id: note.id, content: newText)
                            }
                        )
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                        
                        // Footer Bar (Time & Resize handle)
                        footerBar(note: note)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyView()
        }
    }
    
    // MARK: - Header Bar
    private func headerBar(note: StickyNote) -> some View {
        ZStack {
            // Drag Area Background
            WindowDragAreaView()
            
            HStack(spacing: 6) {
                // Left Controls: Close / Delete
                Button(action: {
                    service.deleteNote(id: note.id)
                }) {
                    ZStack {
                        Circle()
                            .fill(viewState.isHoveringDelete ? Color.red.opacity(0.85) : note.color.headerButtonBg)
                            .frame(width: 18, height: 18)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(viewState.isHoveringDelete ? .white : note.color.textColor.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .help("Delete Note")
                .onHover { viewState.isHoveringDelete = $0 }
                
                // Collapse / Expand
                Button(action: {
                    service.toggleCollapse(id: note.id)
                }) {
                    ZStack {
                        Circle()
                            .fill(viewState.isHoveringCollapse ? note.color.headerButtonBg.opacity(1.8) : note.color.headerButtonBg)
                            .frame(width: 18, height: 18)
                        
                        Image(systemName: note.isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(note.color.textColor.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .help(note.isCollapsed ? "Expand Note" : "Collapse Note")
                .onHover { viewState.isHoveringCollapse = $0 }
                
                Spacer(minLength: 4)
                
                // Color Palette Swatches (7 vibrant dots)
                if !note.isCollapsed {
                    HStack(spacing: 5) {
                        ForEach(StickyNoteColor.allCases) { color in
                            Button(action: {
                                service.updateNoteColor(id: note.id, color: color)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(color.dotColor)
                                        .frame(width: 11, height: 11)
                                    
                                    if note.color == color {
                                        Circle()
                                            .stroke(note.color.textColor.opacity(0.85), lineWidth: 1.5)
                                            .frame(width: 15, height: 15)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(color.title)
                        }
                    }
                    .padding(.horizontal, 4)
                } else {
                    // Collapsed preview text snippet
                    Text(collapsedPreviewText(note: note))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(note.color.textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2) {
                            service.toggleCollapse(id: note.id)
                        }
                }
                
                Spacer(minLength: 4)
                
                // Pin to Desktop (Home Page) vs Float on Top
                Button(action: {
                    service.togglePinToDesktop(id: note.id)
                }) {
                    ZStack {
                        Circle()
                            .fill(note.isPinnedToDesktop ? Color(red: 0.10, green: 0.45, blue: 0.90) : (viewState.isHoveringPin ? note.color.headerButtonBg.opacity(1.8) : note.color.headerButtonBg))
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: note.isPinnedToDesktop ? "house.fill" : "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(note.isPinnedToDesktop ? .white : note.color.textColor.opacity(0.75))
                    }
                }
                .buttonStyle(.plain)
                .help(note.isPinnedToDesktop ? "Pinned to Desktop (Home Page) • Click to Float on Top" : "Floating on Top • Click to Pin to Desktop")
                .onHover { viewState.isHoveringPin = $0 }
                
                // Add new note adjacent
                Button(action: {
                    service.createNote(color: note.color)
                }) {
                    ZStack {
                        Circle()
                            .fill(viewState.isHoveringAdd ? note.color.headerButtonBg.opacity(1.8) : note.color.headerButtonBg)
                            .frame(width: 18, height: 18)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(note.color.textColor.opacity(0.85))
                    }
                }
                .buttonStyle(.plain)
                .help("Add New Sticky Note")
                .onHover { viewState.isHoveringAdd = $0 }
                
                // Copy text to clipboard
                Button(action: {
                    copyNoteText(note: note)
                }) {
                    ZStack {
                        Circle()
                            .fill(viewState.isHoveringCopy ? note.color.headerButtonBg.opacity(1.8) : note.color.headerButtonBg)
                            .frame(width: 18, height: 18)
                        
                        Image(systemName: viewState.isCopiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(viewState.isCopiedFeedback ? Color.green : note.color.textColor.opacity(0.75))
                    }
                }
                .buttonStyle(.plain)
                .help("Copy Note Content")
                .onHover { viewState.isHoveringCopy = $0 }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 34)
    }
    
    // MARK: - Footer Bar
    private func footerBar(note: StickyNote) -> some View {
        HStack {
            Text(formattedTimestamp(date: note.updatedAt))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(note.color.secondaryTextColor)
            
            Spacer()
            
            // Resize grip icon & interactive drag handle
            ResizeGripViewRepresentable()
                .frame(width: 14, height: 14)
                .overlay(
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(note.color.secondaryTextColor.opacity(0.7))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 22)
    }
    
    // MARK: - Helpers
    private func copyNoteText(note: StickyNote) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(note.content, forType: .string)
        
        viewState.isCopiedFeedback = true
        NSSound(named: "Tink")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            viewState.isCopiedFeedback = false
        }
    }
    
    private func collapsedPreviewText(note: StickyNote) -> String {
        let trimmed = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Sticky Note"
        }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        return firstLine
    }
    
    private func formattedTimestamp(date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Saved just now"
        } else if elapsed < 3600 {
            return "Saved \(elapsed / 60)m ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Saved at \(formatter.string(from: date))"
        }
    }
}
