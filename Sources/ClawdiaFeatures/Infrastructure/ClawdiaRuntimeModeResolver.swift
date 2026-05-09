import Foundation

public enum ClawdiaRuntimeMode: String, Equatable, Sendable {
    case production
    case development

    public var allowsDevelopmentSurfaces: Bool {
        self == .development
    }
}

public enum ClawdiaRuntimeModeResolver {
    public static let launchArgument = "--clawdia-dev-mode"
    public static let environmentKey = "CLAWDIA_IOS_MODE"
    public static let userDefaultsKey = "clawdia.devModeEnabled"

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        userDefaults: UserDefaults = .standard
    ) -> ClawdiaRuntimeMode {
        if arguments.contains(launchArgument) {
            return .development
        }
        if userDefaults.bool(forKey: userDefaultsKey) {
            return .development
        }
        if let rawMode = environment[environmentKey]?.lowercased(),
           ["dev", "development"].contains(rawMode) {
            return .development
        }
        return .production
    }
}
