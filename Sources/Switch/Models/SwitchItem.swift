import Foundation
import SwiftUI

public final class SwitchItem: ObservableObject, Identifiable {
    public let type: SwitchType
    public let title: String
    @Published public var subtitle: String?
    public let iconName: String
    @Published public var isOn: Bool
    @Published public var isLoading: Bool
    @Published public var isHovered: Bool = false
    public let isActionOnly: Bool
    
    public var id: SwitchType { type }
    
    public init(
        type: SwitchType,
        title: String? = nil,
        subtitle: String? = nil,
        iconName: String? = nil,
        isOn: Bool = false,
        isLoading: Bool = false,
        isActionOnly: Bool? = nil
    ) {
        self.type = type
        self.title = title ?? type.title
        self.subtitle = subtitle
        self.iconName = iconName ?? type.iconName
        self.isOn = isOn
        self.isLoading = isLoading
        self.isActionOnly = isActionOnly ?? type.isActionOnly
    }
}
