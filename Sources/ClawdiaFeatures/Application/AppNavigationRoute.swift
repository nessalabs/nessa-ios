import Foundation

public enum AppNavigationRoute: Hashable, Sendable {
    case area(AreaFilter)
    case chat(ChatPreview)
    case nostrIntegration
}
