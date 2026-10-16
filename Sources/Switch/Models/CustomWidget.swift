import Foundation
import CoreGraphics

public struct WidgetMetric: Codable, Equatable, Sendable {
    public var label: String
    public var value: String
    public var subtext: String?
    public var icon: String?
    public var colorHex: String?
    
    public init(label: String, value: String, subtext: String? = nil, icon: String? = nil, colorHex: String? = nil) {
        self.label = label
        self.value = value
        self.subtext = subtext
        self.icon = icon
        self.colorHex = colorHex
    }
}

public struct WidgetActionButton: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var icon: String?
    public var actionType: String // "increment", "decrement", "reset", "launchApp", "togglePlay", "openSettings"
    public var payload: String?
    
    public init(id: String = UUID().uuidString, label: String, icon: String? = nil, actionType: String, payload: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.actionType = actionType
        self.payload = payload
    }
}

public struct WidgetToggleItem: Codable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var isOn: Bool
    public var icon: String?
    
    public init(id: String = UUID().uuidString, label: String, isOn: Bool = false, icon: String? = nil) {
        self.id = id
        self.label = label
        self.isOn = isOn
        self.icon = icon
    }
}

public struct WidgetComponent: Codable, Equatable, Sendable {
    public enum ComponentType: String, Codable, Sendable {
        case header
        case metricsGrid
        case progressBar
        case actionButtons
        case toggleList
        case liveSystemStat
        case textNote
        case currencyCalc
        case worldClocks
        case quickApps
        case quote
    }
    
    public var type: ComponentType
    public var title: String?
    public var subtitle: String?
    public var icon: String?
    
    // For metricsGrid
    public var metrics: [WidgetMetric]?
    
    // For progressBar
    public var progressValue: Double?
    public var progressMax: Double?
    public var progressUnit: String?
    public var progressColorHex: String?
    
    // For actionButtons
    public var buttons: [WidgetActionButton]?
    
    // For toggleList
    public var toggles: [WidgetToggleItem]?
    
    // For liveSystemStat
    public var systemStatType: String? // "battery", "cpu", "ram", "storage", "network"
    
    // For textNote
    public var noteText: String?
    
    // For currencyCalc
    public var currencyFrom: String?
    public var currencyTo: String?
    public var currencyRate: Double?
    
    // For worldClocks
    public var clockCities: [String]?
    
    // For quickApps
    public var appNames: [String]?
    
    public init(
        type: ComponentType,
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        metrics: [WidgetMetric]? = nil,
        progressValue: Double? = nil,
        progressMax: Double? = nil,
        progressUnit: String? = nil,
        progressColorHex: String? = nil,
        buttons: [WidgetActionButton]? = nil,
        toggles: [WidgetToggleItem]? = nil,
        systemStatType: String? = nil,
        noteText: String? = nil,
        currencyFrom: String? = nil,
        currencyTo: String? = nil,
        currencyRate: Double? = nil,
        clockCities: [String]? = nil,
        appNames: [String]? = nil
    ) {
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.metrics = metrics
        self.progressValue = progressValue
        self.progressMax = progressMax
        self.progressUnit = progressUnit
        self.progressColorHex = progressColorHex
        self.buttons = buttons
        self.toggles = toggles
        self.systemStatType = systemStatType
        self.noteText = noteText
        self.currencyFrom = currencyFrom
        self.currencyTo = currencyTo
        self.currencyRate = currencyRate
        self.clockCities = clockCities
        self.appNames = appNames
    }
}

public struct CustomWidget: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var prompt: String
    public var category: String
    public var width: CGFloat
    public var height: CGFloat
    public var xPosition: CGFloat
    public var yPosition: CGFloat
    public var isPinnedToDesktop: Bool
    public var isVisible: Bool
    public var createdAt: Date
    public var theme: String
    public var components: [WidgetComponent]?
    
    public init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        category: String = "custom",
        width: CGFloat = 300,
        height: CGFloat = 200,
        xPosition: CGFloat = 100,
        yPosition: CGFloat = 100,
        isPinnedToDesktop: Bool = false,
        isVisible: Bool = true,
        createdAt: Date = Date(),
        theme: String = "glass",
        components: [WidgetComponent]? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.category = category
        self.width = width
        self.height = height
        self.xPosition = xPosition
        self.yPosition = yPosition
        self.isPinnedToDesktop = isPinnedToDesktop
        self.isVisible = isVisible
        self.createdAt = createdAt
        self.theme = theme
        self.components = components
    }
}
