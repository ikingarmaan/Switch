import Foundation
import AppKit
import Vision
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public extension Notification.Name {
    static let folderTidyDidChange = Notification.Name("SwitchFolderTidyDidChange")
}

public enum FileCategory: String, CaseIterable, Sendable {
    case document
    case image
    case video
    case audio
    case archive
    case code
    case installer
    case data
    case miscellaneous
    
    public var defaultFolderName: String {
        switch self {
        case .document: return "Documents"
        case .image: return "Photos"
        case .video: return "Movies"
        case .audio: return "Music"
        case .archive: return "Archives"
        case .code: return "Code"
        case .installer: return "Installers"
        case .data: return "Data"
        case .miscellaneous: return "Random"
        }
    }
    
    public var matchingKeywords: [String] {
        switch self {
        case .video:
            return ["movie", "film", "video", "vid", "cinema", "show", "recording", "clip"]
        case .image:
            return ["photo", "image", "picture", "pic", "wallpaper", "wallpap", "screenshot", "graphic", "art", "camera", "gallery", "img"]
        case .document:
            return ["doc", "document", "pdf", "paper", "sheet", "slide", "book", "invoice", "receipt", "resume", "work", "office", "text", "note"]
        case .audio:
            return ["music", "audio", "song", "sound", "podcast", "track", "album"]
        case .archive:
            return ["archive", "zip", "compressed", "tar", "rar", "backup"]
        case .code:
            return ["code", "script", "project", "dev", "repo", "program", "source", "src"]
        case .installer:
            return ["installer", "app", "software", "setup", "dmg", "pkg"]
        case .data:
            return ["data", "dataset", "table", "database", "sql"]
        case .miscellaneous:
            return ["misc", "miscellaneous", "other", "random", "dump", "temp"]
        }
    }
}

public struct TidyMoveRecord: Codable, Sendable {
    public let originalPath: String
    public let destinationPath: String
    public let timestamp: Date
}

public final class FolderTidyService: ObservableObject, @unchecked Sendable {
    public static let shared = FolderTidyService()
    
    @Published public private(set) var isOrganizing: Bool = false
    @Published public private(set) var statusSubtitle: String = "1-Click Tidy • Ready"
    @Published public private(set) var lastTidiedCount: Int = 0
    @Published public private(set) var canUndo: Bool = false
    
    private var lastMoveRecords: [TidyMoveRecord] = []
    private let historyDefaultsKey = "switch.foldertidy.lastmoves"
    
    private init() {
        loadHistory()
    }
    
    // MARK: - Extension to Category Mapping
    
    public func category(for url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "epub", "odt", "ppt", "pptx", "key", "xls", "xlsx", "numbers":
            return .document
        case "png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "svg", "tiff", "tif", "bmp", "psd", "ai", "raw", "cr2", "nef", "ico":
            return .image
        case "mp4", "mov", "mkv", "avi", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "3gp":
            return .video
        case "mp3", "wav", "m4a", "flac", "aac", "ogg", "wma", "aiff", "alac":
            return .audio
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "sitx":
            return .archive
        case "swift", "py", "js", "ts", "html", "css", "c", "cpp", "h", "java", "go", "rs", "rb", "php", "sh", "json", "yaml", "yml", "xml", "sql", "kt":
            return .code
        case "dmg", "pkg", "iso":
            return .installer
        case "csv", "tsv", "parquet", "sqlite", "db":
            return .data
        default:
            return .miscellaneous
        }
    }
    
    // MARK: - Primary Action: Tidy Up All Main Folders
    
    public func tidyUpAll() {
        guard !isOrganizing else { return }
        
        let fileManager = FileManager.default
        var targets: [URL] = []
        
        if let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first {
            targets.append(desktop)
        }
        if let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            targets.append(downloads)
        }
        
        runTidy(on: targets)
    }
    
    public func tidyDesktopOnly() {
        guard !isOrganizing else { return }
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            runTidy(on: [desktop])
        }
    }
    
    public func tidyDownloadsOnly() {
        guard !isOrganizing else { return }
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            runTidy(on: [downloads])
        }
    }
    
    // MARK: - Execution Engine
    
    private func runTidy(on directories: [URL]) {
        self.isOrganizing = true
        self.statusSubtitle = "Analyzing & Organizing..."
        notifyChange()
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let fileManager = FileManager.default
            var currentBatchMoves: [TidyMoveRecord] = []
            var totalMoved = 0
            
            for directory in directories {
                guard let items = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                
                // 1. Separate existing top-level directories vs regular files
                // CRITICAL RULE: DO NOT move existing directories into another folder!
                var existingFolders: [URL] = []
                var filesToOrganize: [URL] = []
                
                for item in items {
                    let vals = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isRegularFileKey])
                    let isDir = vals?.isDirectory == true
                    let isPackage = vals?.isPackage == true
                    
                    if isDir && !isPackage {
                        // It's a real folder! Keep it in place.
                        existingFolders.append(item)
                    } else if vals?.isRegularFile == true || isPackage {
                        // Skip temporary / in-progress downloads
                        let ext = item.pathExtension.lowercased()
                        if ext == "download" || ext == "crdownload" || ext == "part" {
                            continue
                        }
                        // Skip system files or Desktop symlinks
                        if item.lastPathComponent.hasPrefix(".") {
                            continue
                        }
                        filesToOrganize.append(item)
                    }
                }
                
                // 2. Process each loose file
                for fileURL in filesToOrganize {
                    let cat = self.category(for: fileURL)
                    
                    // A. Intelligent Renaming for Documents & Images
                    var finalFilename = fileURL.lastPathComponent
                    if cat == .document || cat == .image {
                        if let intelligentName = self.analyzeContentAndSuggestName(for: fileURL, category: cat) {
                            finalFilename = intelligentName
                        }
                    }
                    
                    // B. Identify Destination Folder:
                    // Check if there is already a matching folder in this directory!
                    let destinationFolder = self.resolveDestinationFolder(
                        category: cat,
                        in: directory,
                        existingFolders: &existingFolders
                    )
                    
                    // Avoid moving into itself
                    if destinationFolder.standardizedFileURL == directory.standardizedFileURL {
                        continue
                    }
                    
                    // C. Resolve unique collision-free destination URL
                    let destURL = self.uniqueDestination(in: destinationFolder, filename: finalFilename)
                    
                    do {
                        try fileManager.moveItem(at: fileURL, to: destURL)
                        currentBatchMoves.append(TidyMoveRecord(
                            originalPath: fileURL.path,
                            destinationPath: destURL.path,
                            timestamp: Date()
                        ))
                        totalMoved += 1
                    } catch {
                        // Continue organizing remaining files if one fails
                        continue
                    }
                }
            }
            
            let movedCount = totalMoved
            let batch = currentBatchMoves
            
            await MainActor.run {
                self.isOrganizing = false
                self.lastTidiedCount = movedCount
                
                if !batch.isEmpty {
                    self.lastMoveRecords = batch
                    self.canUndo = true
                    self.saveHistory()
                    self.statusSubtitle = "Tidied \(movedCount) files • Clean"
                    NSSound(named: "Glass")?.play()
                } else {
                    self.statusSubtitle = "Folders Already Clean"
                }
                self.notifyChange()
            }
        }
    }
    
    // MARK: - Folder Matching
    
    private func resolveDestinationFolder(
        category: FileCategory,
        in parentDir: URL,
        existingFolders: inout [URL]
    ) -> URL {
        let keywords = category.matchingKeywords
        
        // 1. Look for an existing folder matching category keywords
        for folder in existingFolders {
            let name = folder.lastPathComponent.lowercased()
            for kw in keywords {
                if name.contains(kw) {
                    return folder
                }
            }
        }
        
        // 2. If no matching folder exists, create the standard category folder
        let folderName = category.defaultFolderName
        let newFolderURL = parentDir.appendingPathComponent(folderName, isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: newFolderURL.path) {
            try? FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: true)
            existingFolders.append(newFolderURL)
        }
        
        return newFolderURL
    }
    
    // MARK: - Intelligent Document & Image Content Analysis
    
    private func analyzeContentAndSuggestName(for fileURL: URL, category: FileCategory) -> String? {
        let originalExt = fileURL.pathExtension.lowercased()
        
        if category == .document {
            return analyzeDocumentContent(fileURL: fileURL, ext: originalExt)
        } else if category == .image {
            return analyzeImageContent(fileURL: fileURL, ext: originalExt)
        }
        return nil
    }
    
    // MARK: - Document Analyzer (PDFKit & Text Parsing)
    
    private func analyzeDocumentContent(fileURL: URL, ext: String) -> String? {
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: fileURL) else { return nil }
            
            // Check PDF metadata title
            if let metaTitle = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
                let trimmed = metaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 4 && trimmed.count <= 60 && !trimmed.lowercased().hasPrefix("untitled") {
                    return sanitizeFilename(trimmed, ext: ext)
                }
            }
            
            // Extract text from page 1 & 2
            var fullText = ""
            let maxPages = min(pdf.pageCount, 2)
            for i in 0..<maxPages {
                if let page = pdf.page(at: i), let pageString = page.string {
                    fullText += " " + pageString
                }
            }
            
            let lower = fullText.lowercased()
            
            // Detect common document types
            if lower.contains("resume") || lower.contains("curriculum vitae") {
                if let name = extractCandidateName(from: fullText) {
                    return sanitizeFilename("Resume_\(name)", ext: ext)
                }
                return sanitizeFilename("Resume_Document", ext: ext)
            }
            
            if lower.contains("invoice") || lower.contains("tax invoice") || lower.contains("receipt") {
                let vendor = extractVendorName(from: fullText) ?? "Receipt"
                let num = extractInvoiceNumber(from: fullText)
                let name = num != nil ? "Invoice_\(vendor)_\(num!)" : "Invoice_\(vendor)"
                return sanitizeFilename(name, ext: ext)
            }
            
            if lower.contains("agreement") || lower.contains("contract") || lower.contains("nda") {
                return sanitizeFilename("Agreement_Contract", ext: ext)
            }
            
            if lower.contains("bank statement") || lower.contains("account statement") {
                return sanitizeFilename("Bank_Statement", ext: ext)
            }
            
            if lower.contains("boarding pass") || lower.contains("flight ticket") {
                return sanitizeFilename("Flight_Boarding_Pass", ext: ext)
            }
            
            // General title: extract first prominent line
            if let firstHeading = extractProminentHeading(from: fullText) {
                return sanitizeFilename(firstHeading, ext: ext)
            }
            
        } else if ext == "txt" || ext == "md" || ext == "rtf" {
            // Read first few lines of text
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let lines = content.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                for line in lines.prefix(10) {
                    // Check for markdown headers # Title
                    if line.hasPrefix("#") {
                        let header = line.trimmingCharacters(in: CharacterSet(charactersIn: "# " ))
                        if header.count >= 3 {
                            return sanitizeFilename(header, ext: ext)
                        }
                    }
                    if line.count >= 4 && line.count <= 45 && !line.hasPrefix("//") && !line.hasPrefix("/*") {
                        return sanitizeFilename(line, ext: ext)
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Image Analyzer (Vision Framework OCR & ML Classifier)
    
    private func analyzeImageContent(fileURL: URL, ext: String) -> String? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        
        var recognizedLines: [String] = []
        var imageClassLabels: [String] = []
        
        let textRequest = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations.prefix(6) {
                if let top = obs.topCandidates(1).first {
                    let str = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !str.isEmpty {
                        recognizedLines.append(str)
                    }
                }
            }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        
        let classifyRequest = VNClassifyImageRequest { request, _ in
            guard let observations = request.results as? [VNClassificationObservation] else { return }
            for obs in observations where obs.confidence > 0.35 {
                let rawId = obs.identifier
                // Strip hierarchical taxonomies (e.g. "animal > dog > golden retriever")
                let label = rawId.components(separatedBy: ">").last?.trimmingCharacters(in: .whitespaces) ?? rawId
                if label.count >= 3 && !label.lowercased().contains("sky") && !label.lowercased().contains("room") {
                    imageClassLabels.append(label.capitalized)
                }
                if imageClassLabels.count >= 2 { break }
            }
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([textRequest, classifyRequest])
        
        // 1. If text is present, classify by text semantics
        let fullRecognized = recognizedLines.joined(separator: " ")
        let lower = fullRecognized.lowercased()
        
        if !recognizedLines.isEmpty {
            if lower.contains("error") || lower.contains("exception") || lower.contains("traceback") || lower.contains("failed") {
                return sanitizeFilename("Screenshot_Error_Log", ext: ext)
            }
            if lower.contains("invoice") || lower.contains("receipt") || lower.contains("order total") || lower.contains("subtotal") {
                let vendor = extractVendorName(from: fullRecognized) ?? "Receipt"
                return sanitizeFilename("Invoice_\(vendor)", ext: ext)
            }
            if lower.contains("boarding pass") || lower.contains("flight") || lower.contains("gate") {
                return sanitizeFilename("Ticket_Boarding_Pass", ext: ext)
            }
            if lower.contains("certificate") || lower.contains("awarded to") {
                return sanitizeFilename("Certificate_Award", ext: ext)
            }
            
            // Clean up the first 1-2 recognized lines into a descriptive title
            if let firstLine = recognizedLines.first, firstLine.count >= 4 {
                let words = firstLine.components(separatedBy: .whitespaces).filter { $0.count > 1 }
                if !words.isEmpty {
                    let snippet = words.prefix(4).joined(separator: "_")
                    return sanitizeFilename("Image_\(snippet)", ext: ext)
                }
            }
        }
        
        // 2. If it's a photo without text, use the Vision ML scene/object classification
        if !imageClassLabels.isEmpty {
            let label = imageClassLabels.joined(separator: "_")
            return sanitizeFilename("Photo_\(label)", ext: ext)
        }
        
        return nil
    }
    
    // MARK: - Text Extraction Helpers
    
    private func extractCandidateName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && $0.count <= 35 }
        
        // Usually candidate name is on the top 3 lines
        for line in lines.prefix(3) {
            let lower = line.lowercased()
            if !lower.contains("resume") && !lower.contains("curriculum") && !lower.contains("@") && !lower.contains("phone") {
                let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if words.count >= 1 && words.count <= 3 {
                    return words.joined(separator: "_")
                }
            }
        }
        return nil
    }
    
    private func extractVendorName(from text: String) -> String? {
        let knownVendors = ["Amazon", "Apple", "Google", "Uber", "Swiggy", "Zomato", "Starbucks", "Walmart", "Netflix", "Microsoft", "Airbnb", "Hostinger", "GitHub", "Cloudflare", "DigitalOcean"]
        for vendor in knownVendors {
            if text.localizedCaseInsensitiveContains(vendor) {
                return vendor
            }
        }
        return nil
    }
    
    private func extractInvoiceNumber(from text: String) -> String? {
        let pattern = #"(?i)(?:invoice|receipt|order)\s*(?:#|no\.?|num)?\s*([A-Za-z0-9\-]{4,12})"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let r = Range(match.range(at: 1), in: text) {
                    return String(text[r])
                }
            }
        }
        return nil
    }
    
    private func extractProminentHeading(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 4 && $0.count <= 50 }
        
        for line in lines.prefix(5) {
            if !line.contains("@") && !line.contains("http") && !line.contains("www.") {
                return line
            }
        }
        return nil
    }
    
    // MARK: - Sanitization & Collision Resolution
    
    private func sanitizeFilename(_ raw: String, ext: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|\n\r\t")
        var cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_.- "))
        
        if cleaned.isEmpty {
            cleaned = "Document"
        }
        let truncated = String(cleaned.prefix(42)).trimmingCharacters(in: CharacterSet(charactersIn: "_.- "))
        return "\(truncated).\(ext)"
    }
    
    private func uniqueDestination(in folder: URL, filename: String) -> URL {
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        
        var candidate = folder.appendingPathComponent(filename)
        var counter = 1
        
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(nameWithoutExt)_\(counter)" : "\(nameWithoutExt)_\(counter).\(ext)"
            candidate = folder.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }
    
    // MARK: - Undo Last Tidy
    
    public func undoLastTidy() {
        guard canUndo && !lastMoveRecords.isEmpty else { return }
        
        let fileManager = FileManager.default
        var restoredCount = 0
        
        // Revert in reverse order
        for record in lastMoveRecords.reversed() {
            let destURL = URL(fileURLWithPath: record.destinationPath)
            let originalURL = URL(fileURLWithPath: record.originalPath)
            
            if fileManager.fileExists(atPath: destURL.path) {
                // Ensure parent directory exists
                let parent = originalURL.deletingLastPathComponent()
                try? fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                
                let safeOriginal = uniqueDestination(in: parent, filename: originalURL.lastPathComponent)
                do {
                    try fileManager.moveItem(at: destURL, to: safeOriginal)
                    restoredCount += 1
                } catch {
                    continue
                }
            }
        }
        
        self.lastMoveRecords = []
        self.canUndo = false
        clearHistory()
        self.statusSubtitle = restoredCount > 0 ? "Restored \(restoredCount) files" : "Undo Complete"
        NSSound(named: "Purr")?.play()
        notifyChange()
    }
    
    // MARK: - Persistence & Notifications
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(lastMoveRecords) {
            UserDefaults.standard.set(data, forKey: historyDefaultsKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyDefaultsKey),
           let records = try? JSONDecoder().decode([TidyMoveRecord].self, from: data) {
            self.lastMoveRecords = records
            self.canUndo = !records.isEmpty
        }
    }
    
    private func clearHistory() {
        UserDefaults.standard.removeObject(forKey: historyDefaultsKey)
    }
    
    private func notifyChange() {
        NotificationCenter.default.post(name: .folderTidyDidChange, object: isOrganizing)
    }
    
    // MARK: - Folder Openers
    
    public func openFolder(type: FileManager.SearchPathDirectory) {
        if let url = FileManager.default.urls(for: type, in: .userDomainMask).first {
            NSWorkspace.shared.open(url)
        }
    }
}
