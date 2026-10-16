import Foundation
import CoreGraphics

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
        theme: String = "glass"
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
    }
}
