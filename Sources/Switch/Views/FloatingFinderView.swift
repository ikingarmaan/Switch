import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Models

public struct FloatingFinderItem: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let formattedSize: String
    public let modifiedDate: Date?
    public let formattedDate: String
    public let isHidden: Bool
    public let icon: NSImage
    
    public static func == (lhs: FloatingFinderItem, rhs: FloatingFinderItem) -> Bool {
        lhs.id == rhs.id && lhs.size == rhs.size && lhs.modifiedDate == rhs.modifiedDate
    }
}

public enum FloatingFinderSortOption: String, CaseIterable, Identifiable, Sendable {
    case name = "Name"
    case date = "Date Modified"
    case size = "Size"
    case kind = "Kind"
    
    public var id: String { rawValue }
}

// MARK: - View Model

@MainActor
public final class FloatingFinderViewModel: ObservableObject {
    public static let shared = FloatingFinderViewModel()
    
    @Published public var currentURL: URL
    @Published public var items: [FloatingFinderItem] = []
    @Published public var history: [URL] = []
    @Published public var historyIndex: Int = 0
    @Published public var searchQuery: String = ""
    @Published public var isGridView: Bool = false
    @Published public var sortOption: FloatingFinderSortOption = .name
    @Published public var sortAscending: Bool = true
    @Published public var showHidden: Bool = false
    @Published public var isCollapsed: Bool = false
    @Published public var selectedItemId: String? = nil
    @Published public var statusMessage: String = ""
    @Published public var isSyncing: Bool = false
    
    private let keyLastPath = "switch.floatingFinder.lastPath"
    private let keyViewMode = "switch.floatingFinder.isGridView"
    
    private lazy var byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useAll]
        return f
    }()
    
    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()
    
    public init() {
        if let savedPath = UserDefaults.standard.string(forKey: keyLastPath),
           FileManager.default.fileExists(atPath: savedPath) {
            self.currentURL = URL(fileURLWithPath: savedPath)
        } else {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            self.currentURL = desktop ?? FileManager.default.homeDirectoryForCurrentUser
        }
        
        self.isGridView = UserDefaults.standard.bool(forKey: keyViewMode)
        self.history = [currentURL]
        self.historyIndex = 0
        
        loadCurrentDirectory(addToHistory: false)
    }
    
    public var canGoBack: Bool {
        historyIndex > 0
    }
    
    public var canGoForward: Bool {
        historyIndex < (history.count - 1)
    }
    
    public var canGoUp: Bool {
        currentURL.path != "/"
    }
    
    public var pathComponents: [(name: String, url: URL)] {
        var comps: [(name: String, url: URL)] = []
        var u = currentURL
        let root = URL(fileURLWithPath: "/")
        
        while u.path != root.path {
            comps.insert((name: u.lastPathComponent, url: u), at: 0)
            u = u.deletingLastPathComponent()
        }
        comps.insert((name: "Mac", url: root), at: 0)
        return comps
    }
    
    public var filteredItems: [FloatingFinderItem] {
        let list: [FloatingFinderItem]
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list = items
        } else {
            let q = searchQuery.lowercased()
            list = items.filter { $0.name.lowercased().contains(q) }
        }
        
        return list.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            
            let cmp: Bool
            switch sortOption {
            case .name:
                cmp = a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .date:
                let d1 = a.modifiedDate ?? Date.distantPast
                let d2 = b.modifiedDate ?? Date.distantPast
                cmp = d1 > d2
            case .size:
                cmp = a.size > b.size
            case .kind:
                cmp = a.url.pathExtension.localizedStandardCompare(b.url.pathExtension) == .orderedAscending
            }
            return sortAscending ? cmp : !cmp
        }
    }
    
    public var totalItemsSummary: String {
        let count = filteredItems.count
        let totalBytes = filteredItems.reduce(0) { $0 + $1.size }
        let sizeStr = byteFormatter.string(fromByteCount: totalBytes)
        return "\(count) \(count == 1 ? "item" : "items") · \(sizeStr)"
    }
    
    // MARK: - Navigation Actions
    
    public func navigateTo(url: URL, addToHistory: Bool = true) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            if addToHistory {
                if historyIndex < history.count - 1 {
                    history.removeSubrange((historyIndex + 1)...)
                }
                history.append(url)
                historyIndex = history.count - 1
            }
            currentURL = url
            UserDefaults.standard.set(url.path, forKey: keyLastPath)
            loadCurrentDirectory(addToHistory: false)
        } else {
            openItem(url: url)
        }
    }
    
    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        currentURL = history[historyIndex]
        UserDefaults.standard.set(currentURL.path, forKey: keyLastPath)
        loadCurrentDirectory(addToHistory: false)
    }
    
    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        currentURL = history[historyIndex]
        UserDefaults.standard.set(currentURL.path, forKey: keyLastPath)
        loadCurrentDirectory(addToHistory: false)
    }
    
    public func goUp() {
        guard canGoUp else { return }
        let parent = currentURL.deletingLastPathComponent()
        navigateTo(url: parent)
    }
    
    public func jumpTo(folder: FileManager.SearchPathDirectory) {
        if let target = FileManager.default.urls(for: folder, in: .userDomainMask).first {
            navigateTo(url: target)
        }
    }
    
    public func jumpToHome() {
        navigateTo(url: FileManager.default.homeDirectoryForCurrentUser)
    }
    
    public func toggleViewMode() {
        isGridView.toggle()
        UserDefaults.standard.set(isGridView, forKey: keyViewMode)
    }
    
    // MARK: - Directory Loading
    
    public func loadCurrentDirectory(addToHistory: Bool = true) {
        let target = currentURL
        
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey,
            .effectiveIconKey
        ]
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: target,
                includingPropertiesForKeys: keys,
                options: showHidden ? [] : [.skipsHiddenFiles]
            )
            
            var loaded: [FloatingFinderItem] = []
            
            for u in fileURLs {
                let name = u.lastPathComponent
                guard !name.isEmpty else { continue }
                if !showHidden && (name.hasPrefix(".") || name == ".DS_Store") {
                    continue
                }
                
                let rv = try? u.resourceValues(forKeys: Set(keys))
                let isDir = rv?.isDirectory ?? false
                let size = Int64(rv?.fileSize ?? 0)
                let date = rv?.contentModificationDate
                let isHidden = rv?.isHidden ?? false
                let icon = NSWorkspace.shared.icon(forFile: u.path)
                
                let sizeFormatted = isDir ? "Folder" : byteFormatter.string(fromByteCount: size)
                let dateFormatted = date != nil ? dateFormatter.string(from: date!) : "--"
                
                loaded.append(FloatingFinderItem(
                    url: u,
                    name: name,
                    isDirectory: isDir,
                    size: size,
                    formattedSize: sizeFormatted,
                    modifiedDate: date,
                    formattedDate: dateFormatted,
                    isHidden: isHidden,
                    icon: icon
                ))
            }
            
            self.items = loaded
            self.selectedItemId = nil
        } catch {
            self.items = []
            self.statusMessage = "Cannot open folder: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Finder Native Interop
    
    public func syncWithNativeFinder() {
        isSyncing = true
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                return POSIX path of (target of front Finder window as alias)
            else
                return ""
            end if
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            var resolvedURL: URL?
            if let appleScript = NSAppleScript(source: script) {
                let output = appleScript.executeAndReturnError(&error)
                let path = (output.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                    resolvedURL = URL(fileURLWithPath: path)
                }
            }
            
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let u = resolvedURL {
                    self?.navigateTo(url: u)
                }
            }
        }
    }
    
    public func openInNativeFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([currentURL])
    }
    
    public func openItem(url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            navigateTo(url: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func quickLook(url: URL) {
        _ = Shell.run("qlmanage -p '\(url.path)' &")
    }
    
    public func copyPath(url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
    
    public func openInTerminal(url: URL) {
        let dir = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        _ = Shell.run("open -a Terminal '\(dir.path)'")
    }
    
    public func moveToTrash(url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            loadCurrentDirectory(addToHistory: false)
        } catch {
            self.statusMessage = "Error trashing item: \(error.localizedDescription)"
        }
    }
    
    public func createNewFolder(name: String = "untitled folder") {
        var folderName = name
        var count = 2
        var destination = currentURL.appendingPathComponent(folderName)
        
        while FileManager.default.fileExists(atPath: destination.path) {
            folderName = "\(name) \(count)"
            destination = currentURL.appendingPathComponent(folderName)
            count += 1
        }
        
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            loadCurrentDirectory(addToHistory: false)
            self.selectedItemId = destination.path
        } catch {
            self.statusMessage = "Could not create folder: \(error.localizedDescription)"
        }
    }
}

// MARK: - Views

public struct FloatingFinderView: View {
    @ObservedObject public var vm: FloatingFinderViewModel
    @ObservedObject public var service = FloatingFinderService.shared
    
    public init(vm: FloatingFinderViewModel) {
        self.vm = vm
    }
    
    public var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Bar
                FloatingFinderHeaderBar(vm: vm, service: service)
                
                if !vm.isCollapsed {
                    // Breadcrumb Path Navigation
                    FloatingFinderBreadcrumbBar(vm: vm)
                    
                    Divider().opacity(0.3)
                    
                    // Main File View Area
                    if vm.filteredItems.isEmpty {
                        FloatingFinderEmptyState(query: vm.searchQuery)
                    } else if vm.isGridView {
                        FloatingFinderGridView(vm: vm)
                    } else {
                        FloatingFinderListView(vm: vm)
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Bottom Status Footer
                    FloatingFinderFooterBar(vm: vm, service: service)
                }
            }
        }
        .frame(minWidth: 380, minHeight: vm.isCollapsed ? 48 : 420)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Header Bar

private struct FloatingFinderHeaderBar: View {
    @ObservedObject var vm: FloatingFinderViewModel
    @ObservedObject var service: FloatingFinderService
    
    var body: some View {
        HStack(spacing: 8) {
            // Traffic Light Simulators / Window Control
            HStack(spacing: 6) {
                Button(action: {
                    service.setEnabled(false)
                }) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.38, blue: 0.35))
                        .frame(width: 12, height: 12)
                        .overlay(Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundColor(.black.opacity(0.6)).opacity(0))
                }
                .buttonStyle(.plain)
                .help("Close Floating Finder")
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        vm.isCollapsed.toggle()
                    }
                }) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.74, blue: 0.22))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .help(vm.isCollapsed ? "Expand Window" : "Collapse to Bar")
                
                Button(action: {
                    service.openNewFinderWindow()
                }) {
                    Circle()
                        .fill(Color(red: 0.16, green: 0.82, blue: 0.54))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .help("Open in Native Finder")
            }
            .padding(.trailing, 4)
            
            // Back / Forward / Up Controls
            HStack(spacing: 2) {
                Button(action: { vm.goBack() }) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!vm.canGoBack)
                .opacity(vm.canGoBack ? 1.0 : 0.35)
                .help("Back")
                
                Button(action: { vm.goForward() }) {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!vm.canGoForward)
                .opacity(vm.canGoForward ? 1.0 : 0.35)
                .help("Forward")
                
                Button(action: { vm.goUp() }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!vm.canGoUp)
                .opacity(vm.canGoUp ? 1.0 : 0.35)
                .help("Enclosing Folder")
            }
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
            
            // Current Title
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13))
                Text(vm.currentURL.lastPathComponent.isEmpty ? "Macintosh HD" : vm.currentURL.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Quick Jumps (Desktop, Downloads, Home)
            HStack(spacing: 3) {
                QuickJumpButton(icon: "house.fill", label: "Home") {
                    vm.jumpToHome()
                }
                QuickJumpButton(icon: "desktopcomputer", label: "Desktop") {
                    vm.jumpTo(folder: .desktopDirectory)
                }
                QuickJumpButton(icon: "arrow.down.circle.fill", label: "Downloads") {
                    vm.jumpTo(folder: .downloadsDirectory)
                }
                QuickJumpButton(icon: "doc.fill", label: "Documents") {
                    vm.jumpTo(folder: .documentDirectory)
                }
            }
            
            Divider().frame(height: 16).opacity(0.3)
            
            // Sync with Native Finder Button
            Button(action: {
                vm.syncWithNativeFinder()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(vm.isSyncing ? 360 : 0))
                    Text("Sync")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.18))
                .foregroundColor(.accentColor)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Sync current folder with active native Finder window")
            
            // Native Finder Reveal Button
            Button(action: {
                vm.openInNativeFinder()
            }) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Open in Native Finder")
            
            // View Mode Toggle (List vs Grid)
            Button(action: {
                vm.toggleViewMode()
            }) {
                Image(systemName: vm.isGridView ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help(vm.isGridView ? "Switch to List View" : "Switch to Grid View")
            
            // Opacity & Layer Menu
            Menu {
                Section("Floating Level") {
                    Button(action: { service.setLevel(.floating) }) {
                        HStack {
                            Text("Floating (Above Apps · Level 3)")
                            if service.currentLevel == .floating { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { service.setLevel(.topmost) }) {
                        HStack {
                            Text("Topmost (Above Panels · Level 8)")
                            if service.currentLevel == .topmost { Image(systemName: "checkmark") }
                        }
                    }
                }
                
                Section("Window Transparency") {
                    Button(action: { service.setOpacity(1.0) }) {
                        HStack {
                            Text("100% Solid")
                            if service.opacity == 1.0 { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { service.setOpacity(0.9) }) {
                        HStack {
                            Text("90% Subtle Glass")
                            if service.opacity == 0.9 { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { service.setOpacity(0.8) }) {
                        HStack {
                            Text("80% Translucent Glass")
                            if service.opacity == 0.8 { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { service.setOpacity(0.7) }) {
                        HStack {
                            Text("70% Ghost View")
                            if service.opacity == 0.7 { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                }
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.08))
                .cornerRadius(5)
            }
            .menuStyle(.borderlessButton)
            .help("Transparency & Floating Options")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.18))
    }
}

private struct QuickJumpButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.06))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

// MARK: - Breadcrumb Path Bar

private struct FloatingFinderBreadcrumbBar: View {
    @ObservedObject var vm: FloatingFinderViewModel
    
    var body: some View {
        HStack(spacing: 6) {
            // Path segments
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(vm.pathComponents.enumerated()), id: \.offset) { idx, comp in
                        HStack(spacing: 3) {
                            if idx > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            
                            Button(action: {
                                vm.navigateTo(url: comp.url)
                            }) {
                                Text(comp.name)
                                    .font(.system(size: 11, weight: idx == vm.pathComponents.count - 1 ? .bold : .regular))
                                    .foregroundColor(idx == vm.pathComponents.count - 1 ? .primary : .secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(idx == vm.pathComponents.count - 1 ? 0.08 : 0.0))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Spacer()
            
            // Search Input Field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                TextField("Search folder...", text: $vm.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 110)
                
                if !vm.searchQuery.isEmpty {
                    Button(action: { vm.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
            
            // New Folder button
            Button(action: {
                vm.createNewFolder()
            }) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Create New Folder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.08))
    }
}

// MARK: - List View

private struct FloatingFinderListView: View {
    @ObservedObject var vm: FloatingFinderViewModel
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(vm.filteredItems) { item in
                    FloatingFinderListRow(item: item, vm: vm)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct FloatingFinderListRow: View {
    let item: FloatingFinderItem
    @ObservedObject var vm: FloatingFinderViewModel
    
    var isSelected: Bool {
        vm.selectedItemId == item.id
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 18, height: 18)
            
            Text(item.name)
                .font(.system(size: 12, weight: item.isDirectory ? .semibold : .regular))
                .foregroundColor(item.isHidden ? .secondary.opacity(0.7) : .primary)
                .lineLimit(1)
            
            Spacer()
            
            Text(item.formattedSize)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
            
            Text(item.formattedDate)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            vm.openItem(url: item.url)
        }
        .onTapGesture {
            vm.selectedItemId = item.id
        }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button(item.isDirectory ? "Open Folder" : "Open") {
                vm.openItem(url: item.url)
            }
            Button("Reveal in Native Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Quick Look Preview") {
                vm.quickLook(url: item.url)
            }
            Divider()
            Button("Copy Path") {
                vm.copyPath(url: item.url)
            }
            Button("Open in Terminal") {
                vm.openInTerminal(url: item.url)
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                vm.moveToTrash(url: item.url)
            }
        }
    }
}

// MARK: - Grid View

private struct FloatingFinderGridView: View {
    @ObservedObject var vm: FloatingFinderViewModel
    
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 8)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(vm.filteredItems) { item in
                    FloatingFinderGridCell(item: item, vm: vm)
                }
            }
            .padding(12)
        }
    }
}

private struct FloatingFinderGridCell: View {
    let item: FloatingFinderItem
    @ObservedObject var vm: FloatingFinderViewModel
    
    var isSelected: Bool {
        vm.selectedItemId == item.id
    }
    
    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 38, height: 38)
            
            Text(item.name)
                .font(.system(size: 11, weight: item.isDirectory ? .semibold : .regular))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 80)
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.04))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            vm.openItem(url: item.url)
        }
        .onTapGesture {
            vm.selectedItemId = item.id
        }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button(item.isDirectory ? "Open Folder" : "Open") {
                vm.openItem(url: item.url)
            }
            Button("Reveal in Native Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Quick Look Preview") {
                vm.quickLook(url: item.url)
            }
            Divider()
            Button("Copy Path") {
                vm.copyPath(url: item.url)
            }
            Button("Open in Terminal") {
                vm.openInTerminal(url: item.url)
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                vm.moveToTrash(url: item.url)
            }
        }
    }
}

// MARK: - Empty State

private struct FloatingFinderEmptyState: View {
    let query: String
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: query.isEmpty ? "folder" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text(query.isEmpty ? "This folder is empty" : "No items matching '\(query)'")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Footer Bar

private struct FloatingFinderFooterBar: View {
    @ObservedObject var vm: FloatingFinderViewModel
    @ObservedObject var service: FloatingFinderService
    
    var body: some View {
        HStack(spacing: 8) {
            // Live Pin Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 0.16, green: 0.82, blue: 0.54))
                    .frame(width: 7, height: 7)
                Text("Always on Top (\(service.currentLevel.shortLabel))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(red: 0.16, green: 0.82, blue: 0.54))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(red: 0.16, green: 0.82, blue: 0.54).opacity(0.12))
            .cornerRadius(4)
            
            Spacer()
            
            // Total items and size
            Text(vm.totalItemsSummary)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            
            Divider().frame(height: 12).opacity(0.3)
            
            // Native Finder Open Button
            Button(action: {
                vm.openInNativeFinder()
            }) {
                HStack(spacing: 3) {
                    Text("Native Finder")
                        .font(.system(size: 10, weight: .medium))
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 8))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reveal this directory in native macOS Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.18))
    }
}

