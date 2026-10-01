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
    @Published public var isHoveringChecklist: Bool = false
    @Published public var isHoveringFormat: Bool = false
    @Published public var showFormatBar: Bool = false
    @Published public var newItemText: String = ""
    
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
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            window?.makeKeyAndOrderFront(nil)
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
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            window.makeKeyAndOrderFront(nil)
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
                // Card Background Gradient & Highlight
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
                        // Optional Formatting Drawer
                        if viewState.showFormatBar {
                            formatBar(note: note)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        Divider()
                            .background(note.color.borderColor.opacity(0.6))
                        
                        // Main Note Body: Checklist vs Freeform Text
                        if note.isChecklistMode {
                            checklistBody(note: note)
                        } else {
                            textEditorBody(note: note)
                        }
                        
                        // Footer Bar (Stats & Resize handle)
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
            
            HStack(spacing: 5) {
                // Close / Delete
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
                
                Spacer(minLength: 2)
                
                // Color Palette Swatches (7 vibrant dots)
                if !note.isCollapsed {
                    HStack(spacing: 4) {
                        ForEach(StickyNoteColor.allCases) { color in
                            Button(action: {
                                service.updateNoteColor(id: note.id, color: color)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(color.dotColor)
                                        .frame(width: 10, height: 10)
                                    
                                    if note.color == color {
                                        Circle()
                                            .stroke(note.color.textColor.opacity(0.85), lineWidth: 1.5)
                                            .frame(width: 14, height: 14)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(color.title)
                        }
                    }
                    .padding(.horizontal, 2)
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
                
                Spacer(minLength: 2)
                
                // Checklist Mode Toggle Button
                Button(action: {
                    service.toggleChecklistMode(id: note.id)
                }) {
                    ZStack {
                        Circle()
                            .fill(note.isChecklistMode ? Color.green.opacity(0.85) : (viewState.isHoveringChecklist ? note.color.headerButtonBg.opacity(1.8) : note.color.headerButtonBg))
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: note.isChecklistMode ? "checklist.checked" : "checklist")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(note.isChecklistMode ? .white : note.color.textColor.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .help(note.isChecklistMode ? "Switch to Plain Text Note" : "Switch to To-Do Checklist")
                .onHover { viewState.isHoveringChecklist = $0 }
                
                // Format Bar Toggle Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        viewState.showFormatBar.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewState.showFormatBar ? Color.blue.opacity(0.85) : (viewState.isHoveringFormat ? note.color.headerButtonBg.opacity(1.8) : note.color.headerButtonBg))
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: "textformat")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(viewState.showFormatBar ? .white : note.color.textColor.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
                .help(viewState.showFormatBar ? "Hide Formatting Toolbar" : "Show Alignment & Font Size Toolbar")
                .onHover { viewState.isHoveringFormat = $0 }
                
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
            .padding(.horizontal, 8)
        }
        .frame(height: 34)
    }
    
    // MARK: - Formatting & Alignment Bar
    private func formatBar(note: StickyNote) -> some View {
        HStack(spacing: 8) {
            // Text Alignment Controls (Left, Center, Right)
            HStack(spacing: 2) {
                ForEach(StickyNoteTextAlignment.allCases) { align in
                    Button(action: {
                        service.setTextAlignment(id: note.id, alignment: align)
                    }) {
                        Image(systemName: align.icon)
                            .font(.system(size: 10, weight: note.textAlignment == align ? .bold : .regular))
                            .foregroundColor(note.textAlignment == align ? .white : note.color.textColor.opacity(0.7))
                            .frame(width: 22, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(note.textAlignment == align ? Color.blue.opacity(0.85) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(align.title)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(note.color.headerButtonBg)
            )
            
            Divider()
                .frame(height: 14)
                .background(note.color.borderColor.opacity(0.5))
            
            // Font Size Controls (S, M, L)
            HStack(spacing: 2) {
                ForEach(StickyNoteFontSize.allCases) { size in
                    Button(action: {
                        service.setFontSize(id: note.id, fontSize: size)
                    }) {
                        Text(size.label)
                            .font(.system(size: 9, weight: note.fontSize == size ? .bold : .medium, design: .rounded))
                            .foregroundColor(note.fontSize == size ? .white : note.color.textColor.opacity(0.75))
                            .frame(width: 18, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(note.fontSize == size ? Color.blue.opacity(0.85) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Font size: \(size.title)")
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(note.color.headerButtonBg)
            )
            
            Spacer()
            
            // Quick Helpers: Insert Bullet & Timestamp
            HStack(spacing: 4) {
                Button(action: {
                    service.insertBulletPoint(id: note.id)
                }) {
                    Text("• Bullet")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(note.color.textColor.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(note.color.headerButtonBg)
                        )
                }
                .buttonStyle(.plain)
                .help("Add bullet point")
                
                Button(action: {
                    service.insertCurrentDate(id: note.id)
                }) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundColor(note.color.textColor.opacity(0.8))
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(note.color.headerButtonBg)
                        )
                }
                .buttonStyle(.plain)
                .help("Insert current date & time")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(note.color.headerButtonBg.opacity(0.5))
    }
    
    // MARK: - Freeform Text Editor Body
    private func textEditorBody(note: StickyNote) -> some View {
        ZStack(alignment: note.textAlignment == .center ? .top : (note.textAlignment == .right ? .topTrailing : .topLeading)) {
            if note.content.isEmpty {
                Text("Type your note, reminder, or idea...")
                    .font(.system(size: note.fontSize.pointSize, weight: .regular, design: .rounded))
                    .foregroundColor(note.color.textColor.opacity(0.42))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            
            TextEditor(text: Binding(
                get: { note.content },
                set: { newText in
                    service.updateNoteContent(id: note.id, content: newText)
                }
            ))
            .font(.system(size: note.fontSize.pointSize, weight: .regular, design: .rounded))
            .multilineTextAlignment(note.textAlignment.textAlignment)
            .foregroundColor(note.color.textColor)
            .accentColor(note.color.textColor)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    // MARK: - Checklist / To-Do Mode Body
    private func checklistBody(note: StickyNote) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(note.checklistItems) { item in
                    HStack(spacing: 7) {
                        // Checkbox Button
                        Button(action: {
                            service.updateChecklistItem(noteId: note.id, itemId: item.id, isCompleted: !item.isCompleted)
                            NSSound(named: "Tink")?.play()
                        }) {
                            ZStack {
                                if item.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(Color.green)
                                } else {
                                    Circle()
                                        .strokeBorder(note.color.textColor.opacity(0.45), lineWidth: 1.5)
                                        .frame(width: 14, height: 14)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(item.isCompleted ? "Mark incomplete" : "Mark completed")
                        
                        // Editable Item Text
                        TextField(
                            "Task...",
                            text: Binding(
                                get: { item.title },
                                set: { newTitle in
                                    service.updateChecklistItem(noteId: note.id, itemId: item.id, title: newTitle)
                                }
                            )
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: note.fontSize.pointSize, weight: .regular, design: .rounded))
                        .multilineTextAlignment(note.textAlignment.textAlignment)
                        .strikethrough(item.isCompleted, color: note.color.textColor.opacity(0.55))
                        .foregroundColor(item.isCompleted ? note.color.textColor.opacity(0.40) : note.color.textColor)
                        .onSubmit {
                            service.addChecklistItem(noteId: note.id, afterItemId: item.id)
                        }
                        
                        // Delete Task Button
                        Button(action: {
                            service.deleteChecklistItem(noteId: note.id, itemId: item.id)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundColor(note.color.textColor.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .help("Delete task")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(item.isCompleted ? note.color.headerButtonBg.opacity(0.3) : Color.clear)
                    )
                }
                
                // Add Item Row
                HStack(spacing: 6) {
                    Button(action: {
                        service.addChecklistItem(noteId: note.id)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text("Add Task")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(note.color.textColor.opacity(0.7))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(note.color.headerButtonBg)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Clear completed button
                    let completedCount = note.checklistItems.filter { $0.isCompleted }.count
                    if completedCount > 0 {
                        Button(action: {
                            service.clearCompletedChecklistItems(noteId: note.id)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                Text("Clear Done (\(completedCount))")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                            .foregroundColor(note.color.textColor.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .help("Clear all checked tasks")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer Bar
    private func footerBar(note: StickyNote) -> some View {
        HStack {
            if note.isChecklistMode {
                let total = note.checklistItems.count
                let done = note.checklistItems.filter { $0.isCompleted }.count
                if total > 0 && done == total {
                    Text("All done! 🎉")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.green)
                } else {
                    Text("\(done) of \(total) done")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(note.color.secondaryTextColor)
                }
            } else {
                let words = note.content.split(whereSeparator: \.isWhitespace).count
                Text(words > 0 ? "\(words) \(words == 1 ? "word" : "words")" : formattedTimestamp(date: note.updatedAt))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(note.color.secondaryTextColor)
            }
            
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
        
        if note.isChecklistMode {
            let lines = note.checklistItems.map { item in
                (item.isCompleted ? "[✓] " : "[ ] ") + item.title
            }
            pb.setString(lines.joined(separator: "\n"), forType: .string)
        } else {
            pb.setString(note.content, forType: .string)
        }
        
        viewState.isCopiedFeedback = true
        NSSound(named: "Tink")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            viewState.isCopiedFeedback = false
        }
    }
    
    private func collapsedPreviewText(note: StickyNote) -> String {
        if note.isChecklistMode {
            let firstIncomplete = note.checklistItems.first(where: { !$0.isCompleted })?.title
            let firstAny = note.checklistItems.first?.title
            let candidate = (firstIncomplete?.isEmpty == false ? firstIncomplete : firstAny) ?? "Checklist"
            return "☑️ " + candidate
        } else {
            let trimmed = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Sticky Note"
            }
            let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
            return firstLine
        }
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
