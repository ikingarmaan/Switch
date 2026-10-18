import Foundation

public final class SubtitleParser: Sendable {
    public static let shared = SubtitleParser()
    
    private init() {}
    
    // MARK: - Parse Subtitle File
    
    public func parse(fileURL: URL) -> [SubtitleCue] {
        let content = (try? String(contentsOf: fileURL, encoding: .utf8))
            ?? (try? String(contentsOf: fileURL, encoding: .isoLatin1))
            ?? (try? String(contentsOf: fileURL, encoding: .windowsCP1252))
        guard let validContent = content else {
            return []
        }
        
        let ext = fileURL.pathExtension.lowercased()
        if ext == "vtt" {
            return parseVTT(content: validContent)
        } else {
            return parseSRT(content: validContent)
        }
    }
    
    // MARK: - SRT Parser
    
    public func parseSRT(content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        
        for block in blocks {
            let lines = block.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard !lines.isEmpty else { continue }
            
            var timeLineIndex: Int?
            for (idx, line) in lines.enumerated() {
                if line.contains("-->") {
                    timeLineIndex = idx
                    break
                }
            }
            
            guard let tIndex = timeLineIndex else { continue }
            let timeString = lines[tIndex]
            let timeComponents = timeString.components(separatedBy: "-->")
            guard timeComponents.count == 2 else { continue }
            
            let start = parseTimestamp(timeComponents[0].trimmingCharacters(in: .whitespaces))
            // Remove any trailing position metadata (e.g. "X1:0 Y1:0 ...")
            let endStr = timeComponents[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]
            let end = parseTimestamp(endStr)
            
            guard end > start else { continue }
            
            let textLines = lines[(tIndex + 1)...]
            let rawText = textLines.joined(separator: "\n")
            let cleanedText = cleanSubtitleText(rawText)
            
            guard !cleanedText.isEmpty else { continue }
            
            let cue = SubtitleCue(id: cues.count + 1, startTime: start, endTime: end, text: cleanedText)
            cues.append(cue)
        }
        
        return cues
    }
    
    // MARK: - WebVTT Parser
    
    public func parseVTT(content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->")
                if parts.count == 2 {
                    let start = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces))
                    let endStr = parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]
                    let end = parseTimestamp(endStr)
                    
                    var textLines: [String] = []
                    i += 1
                    while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        textLines.append(lines[i].trimmingCharacters(in: .whitespaces))
                        i += 1
                    }
                    
                    let cleaned = cleanSubtitleText(textLines.joined(separator: "\n"))
                    if !cleaned.isEmpty && end > start {
                        cues.append(SubtitleCue(id: cues.count + 1, startTime: start, endTime: end, text: cleaned))
                    }
                }
            }
            i += 1
        }
        
        return cues
    }
    
    // MARK: - Timestamp Parsing
    
    private func parseTimestamp(_ raw: String) -> TimeInterval {
        // Formats:
        // 00:01:23,456 or 00:01:23.456 or 01:23.456
        let formatted = raw.replacingOccurrences(of: ",", with: ".")
        let parts = formatted.components(separatedBy: ":")
        
        if parts.count == 3 {
            let h = Double(parts[0]) ?? 0
            let m = Double(parts[1]) ?? 0
            let s = Double(parts[2]) ?? 0
            return (h * 3600.0) + (m * 60.0) + s
        } else if parts.count == 2 {
            let m = Double(parts[0]) ?? 0
            let s = Double(parts[1]) ?? 0
            return (m * 60.0) + s
        } else if parts.count == 1 {
            return Double(parts[0]) ?? 0
        }
        return 0
    }
    
    // MARK: - Text Cleaning
    
    private func cleanSubtitleText(_ text: String) -> String {
        var str = text
        // Remove HTML tags like <i>, </i>, <b>, </b>, <font ...>, </font>
        str = str.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Remove ASS/SSA style tags like {\an8}, {\pos(x,y)}
        str = str.replacingOccurrences(of: "\\{[^\\}]+\\}", with: "", options: .regularExpression)
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Auto-Discover Subtitle Files for a Video
    
    public func findSubtitles(for videoURL: URL) -> [URL] {
        guard videoURL.isFileURL else { return [] }
        let directory = videoURL.deletingLastPathComponent()
        let videoBaseName = videoURL.deletingPathExtension().lastPathComponent.lowercased()
        
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        
        let subtitleExtensions = ["srt", "vtt", "ass", "sub"]
        var matches: [URL] = []
        
        for file in files {
            let ext = file.pathExtension.lowercased()
            guard subtitleExtensions.contains(ext) else { continue }
            
            let subName = file.deletingPathExtension().lastPathComponent.lowercased()
            // Match exact name, or name starting with video base name (e.g. Movie.en.srt, Movie_hin.srt)
            if subName == videoBaseName || subName.starts(with: videoBaseName) {
                matches.append(file)
            }
        }
        
        return matches
    }
    
    // MARK: - Fast Binary Search Cue Lookup
    
    public func cue(in cues: [SubtitleCue], at timestamp: TimeInterval, delay: TimeInterval = 0) -> SubtitleCue? {
        guard !cues.isEmpty else { return nil }
        let adjustedTime = timestamp - delay
        
        // Binary search for candidate cue
        var low = 0
        var high = cues.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]
            
            if adjustedTime >= cue.startTime && adjustedTime <= cue.endTime {
                return cue
            } else if adjustedTime < cue.startTime {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        
        return nil
    }
}

