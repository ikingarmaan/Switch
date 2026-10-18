import Foundation
import CoreGraphics

// MARK: - Subtitle Cue & Track Models

public struct SubtitleCue: Identifiable, Sendable, Equatable {
    public let id: Int
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String
    
    public init(id: Int, startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

public struct SubtitleTrack: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let language: String?
    public let isExternal: Bool
    public let cues: [SubtitleCue]
    
    public init(id: String, name: String, language: String? = nil, isExternal: Bool = false, cues: [SubtitleCue] = []) {
        self.id = id
        self.name = name
        self.language = language
        self.isExternal = isExternal
        self.cues = cues
    }
}

// MARK: - Audio Track Model

public struct MediaAudioTrack: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let language: String?
    
    public init(id: String, name: String, language: String? = nil) {
        self.id = id
        self.name = name
        self.language = language
    }
}

// MARK: - Bookmark & Chapter Model

public struct MediaBookmark: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: TimeInterval
    public var title: String
    public let createdAt: Date
    
    public init(id: UUID = UUID(), timestamp: TimeInterval, title: String, createdAt: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.createdAt = createdAt
    }
    
    public var formattedTimestamp: String {
        let totalSeconds = Int(timestamp)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Playlist Item Model

public struct PlaylistItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public var title: String
    public var duration: TimeInterval
    public var lastPlaybackPosition: TimeInterval
    
    public init(id: UUID = UUID(), url: URL, title: String? = nil, duration: TimeInterval = 0, lastPlaybackPosition: TimeInterval = 0) {
        self.id = id
        self.url = url
        self.title = title ?? url.deletingPathExtension().lastPathComponent
        self.duration = duration
        self.lastPlaybackPosition = lastPlaybackPosition
    }
    
    public var isStream: Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "http" || scheme == "https" || scheme == "rtmp" || scheme == "rtsp"
    }
}

// MARK: - Aspect Ratio Mode

public enum VideoAspectRatioMode: String, CaseIterable, Identifiable, Sendable {
    case original = "Default (Original)"
    case fit = "Fit to Screen"
    case fill = "Fill Window"
    case ratio16_9 = "16:9 (Widescreen)"
    case ratio4_3 = "4:3 (Classic TV)"
    case ratio21_9 = "21:9 (Ultrawide Cinema)"
    
    public var id: String { rawValue }
    
    public var numericRatio: CGFloat? {
        switch self {
        case .original, .fit, .fill: return nil
        case .ratio16_9: return 16.0 / 9.0
        case .ratio4_3: return 4.0 / 3.0
        case .ratio21_9: return 21.0 / 9.0
        }
    }
}

