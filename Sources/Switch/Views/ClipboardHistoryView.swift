import SwiftUI
import AppKit

public enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case text = "Text"
    case images = "Images"
    
    public var id: String { rawValue }
}

final class ClipboardHistoryViewState: ObservableObject {
    @Published var searchText: String = ""
    @Published var selectedFilter: ClipboardFilter = .all
    @Published var hoveredItemId: UUID? = nil
    @Published var copiedItemId: UUID? = nil
}

// MARK: - Native Window Drag View (Drag and Drop Window Anywhere)
struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView {
        DragNSView()
    }
    
    func updateNSView(_ nsView: DragNSView, context: Context) {}
    
    final class DragNSView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Native Search Field with Auto-Focus & Escape Handling
struct SearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.textColor = .white
        field.font = .systemFont(ofSize: 11, weight: .regular)
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }
    
    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchFieldRepresentable
        init(_ parent: SearchFieldRepresentable) { self.parent = parent }
        
        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                parent.text = field.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                ClipboardService.shared.closeWindow()
                return true
            }
            return false
        }
    }
}

// MARK: - Compact Modern Black & White Clipboard View
public struct ClipboardHistoryView: View {
    @ObservedObject var service: ClipboardService
    @StateObject private var viewState = ClipboardHistoryViewState()
    
    public init(service: ClipboardService) {
        self.service = service
    }
    
    private var filteredItems: [ClipboardItem] {
        service.items.filter { item in
            switch viewState.selectedFilter {
            case .all:
                break
            case .text:
                guard item.type == .text else { return false }
            case .images:
                guard item.type == .image else { return false }
            }
            
            if !viewState.searchText.isEmpty {
                switch item.type {
                case .text:
                    guard let text = item.textContent,
                          text.localizedCaseInsensitiveContains(viewState.searchText)
                    else { return false }
                case .image:
                    let dims = "\(Int(item.imageWidth ?? 0))x\(Int(item.imageHeight ?? 0))"
                    if !dims.contains(viewState.searchText) && !"image".localizedCaseInsensitiveContains(viewState.searchText) {
                        return false
                    }
                }
            }
            
            return true
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Header (Draggable Anywhere)
            VStack(spacing: 5) {
                // Drag handle pill at the very top
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 26, height: 3)
                    .padding(.top, 4)
                
                // Integrated Search & Controls
                HStack(spacing: 5) {
                    // Search box
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.45))
                        
                        SearchFieldRepresentable(
                            text: $viewState.searchText,
                            placeholder: "Search..."
                        )
                        .frame(height: 18)
                        
                        if !viewState.searchText.isEmpty {
                            Button(action: { viewState.searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(Color.white.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.6)
                    )
                    
                    // Filter segmented pill (All, Txt, Img)
                    HStack(spacing: 1.5) {
                        filterTab(.all, title: "All")
                        filterTab(.text, title: "Txt")
                        filterTab(.images, title: "Img")
                    }
                    .padding(1.5)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
                    
                    // Close button
                    Button(action: {
                        service.closeWindow()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.6))
                            .frame(width: 17, height: 17)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Close window (Esc)")
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 6)
            .background(
                WindowDragView()
            )
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // MARK: - Items List (Ultra Compact)
            if filteredItems.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(Color.white.opacity(0.2))
                    
                    Text(viewState.searchText.isEmpty ? "Clipboard is empty" : "No matches found")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.55))
                    
                    Text("Copy text or images (⌘C) to save here")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.3))
                    Spacer()
                }
                .frame(maxHeight: .infinity)
                .background(WindowDragView())
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            ClipboardItemRowView(
                                item: item,
                                index: index,
                                isHovered: viewState.hoveredItemId == item.id,
                                isJustCopied: viewState.copiedItemId == item.id,
                                onCopy: {
                                    flashCopied(item)
                                    service.copyItemToPasteboard(item)
                                },
                                onDelete: {
                                    service.deleteItem(id: item.id)
                                }
                            )
                            .onHover { isHovering in
                                if isHovering {
                                    viewState.hoveredItemId = item.id
                                } else if viewState.hoveredItemId == item.id {
                                    viewState.hoveredItemId = nil
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // MARK: - Sleek Minimal Footer
            HStack(spacing: 6) {
                // Capacity & Drag hint
                HStack(spacing: 3) {
                    Text("\(service.items.count)/\(ClipboardService.maxItems)")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.45))
                    
                    Text("•")
                        .foregroundColor(Color.white.opacity(0.2))
                        .font(.system(size: 7))
                    
                    Text("Drag to drop")
                        .font(.system(size: 8.5))
                        .foregroundColor(Color.white.opacity(0.32))
                }
                
                Spacer()
                
                // Auto-Paste quick toggle
                Button(action: {
                    service.setAutoPaste(!service.autoPaste)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: service.autoPaste ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 8))
                            .foregroundColor(service.autoPaste ? .white : Color.white.opacity(0.35))
                        Text("Auto-Paste")
                            .font(.system(size: 8.5, weight: service.autoPaste ? .semibold : .regular))
                            .foregroundColor(service.autoPaste ? .white : Color.white.opacity(0.5))
                    }
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(service.autoPaste ? 0.1 : 0.03))
                    .cornerRadius(3.5)
                }
                .buttonStyle(.plain)
                .help("Automatically paste (⌘V) into active app on selection")
                
                // Auto-Paste on Comment Click toggle
                Button(action: {
                    service.setAutoPasteOnCommentClick(!service.autoPasteOnCommentClick)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: service.autoPasteOnCommentClick ? "text.bubble.fill" : "text.bubble")
                            .font(.system(size: 8))
                            .foregroundColor(service.autoPasteOnCommentClick ? Color(red: 0.38, green: 0.75, blue: 0.98) : Color.white.opacity(0.35))
                        Text("Auto 💬")
                            .font(.system(size: 8.5, weight: service.autoPasteOnCommentClick ? .semibold : .regular))
                            .foregroundColor(service.autoPasteOnCommentClick ? .white : Color.white.opacity(0.5))
                    }
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(service.autoPasteOnCommentClick ? 0.1 : 0.03))
                    .cornerRadius(3.5)
                }
                .buttonStyle(.plain)
                .help("Automatically paste latest copied item when clicking into any comment box")
                
                // Clear button
                if !service.items.isEmpty {
                    Button(action: {
                        service.clearAllHistory()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 8.5))
                            .foregroundColor(Color.white.opacity(0.45))
                            .frame(width: 17, height: 17)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(3.5)
                    }
                    .buttonStyle(.plain)
                    .help("Clear all clipboard history")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(Color.black.opacity(0.25))
        }
        .frame(width: 326, height: 340)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(red: 0.06, green: 0.06, blue: 0.07).opacity(0.90)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
        )
    }
    
    private func filterTab(_ filter: ClipboardFilter, title: String) -> some View {
        Button(action: {
            viewState.selectedFilter = filter
        }) {
            Text(title)
                .font(.system(size: 9, weight: viewState.selectedFilter == filter ? .bold : .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    viewState.selectedFilter == filter
                        ? Color.white
                        : Color.clear
                )
                .foregroundColor(
                    viewState.selectedFilter == filter
                        ? Color.black
                        : Color.white.opacity(0.55)
                )
                .cornerRadius(3.5)
        }
        .buttonStyle(.plain)
    }
    
    private func flashCopied(_ item: ClipboardItem) {
        viewState.copiedItemId = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak viewState] in
            if viewState?.copiedItemId == item.id {
                viewState?.copiedItemId = nil
            }
        }
    }
}

// MARK: - Row View (Draggable, Compact, High-Contrast)
private struct ClipboardItemRowView: View {
    let item: ClipboardItem
    let index: Int
    let isHovered: Bool
    let isJustCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Group {
            if index < 9 {
                Button(action: onCopy) {
                    rowContent
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            } else {
                Button(action: onCopy) {
                    rowContent
                }
                .buttonStyle(.plain)
            }
        }
        .onDrag {
            if item.type == .image, let url = ClipboardService.shared.imageFileURL(for: item) {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: (item.textContent ?? "") as NSString)
            } else {
                return NSItemProvider(object: (item.textContent ?? "") as NSString)
            }
        }
    }
    
    private var rowContent: some View {
        HStack(spacing: 6) {
            // Number shortcut (⌘1 to ⌘9)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(2.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            } else {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 3.5, height: 3.5)
                    .frame(width: 16)
            }
            
            // Icon or Image Thumbnail
            switch item.type {
            case .text:
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 22, height: 22)
                    
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.85))
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.previewTitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(item.previewSubtitle)
                        .font(.system(size: 8))
                        .foregroundColor(Color.white.opacity(0.35))
                        .lineLimit(1)
                }
                
            case .image:
                if let thumb = ClipboardService.shared.thumbnail(for: item) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 22, height: 22)
                        .background(Color.black)
                        .cornerRadius(3.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .frame(width: 22, height: 22)
                        Image(systemName: "photo")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                    }
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.previewTitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(item.previewSubtitle)
                        .font(.system(size: 8))
                        .foregroundColor(Color.white.opacity(0.35))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Trailing Actions or Copied Flash
            if isJustCopied {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 17, height: 17)
                    .background(Color.white)
                    .clipShape(Circle())
            } else if isHovered {
                HStack(spacing: 3) {
                    // Copy button (White pill, black icon)
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.black)
                            .frame(width: 17, height: 17)
                            .background(Color.white)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .help("Copy (or click row)")
                    
                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.75))
                            .frame(width: 17, height: 17)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.09) : Color.clear)
        )
    }
}
