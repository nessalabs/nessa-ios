import Foundation

public struct OnboardingConfiguration: Equatable, Sendable {
    public let didComplete: Bool
    public let selectedAreas: Set<LifeArea>

    public init(didComplete: Bool = false, selectedAreas: Set<LifeArea> = LifeArea.defaultOnboardingSelection) {
        self.didComplete = didComplete
        self.selectedAreas = selectedAreas.isEmpty ? LifeArea.defaultOnboardingSelection : selectedAreas
    }

    public static let fresh = OnboardingConfiguration()
}

public protocol OnboardingConfigurationStoring {
    func loadConfiguration() -> OnboardingConfiguration
    func saveConfiguration(_ configuration: OnboardingConfiguration)
}

public final class InMemoryOnboardingConfigurationStore: OnboardingConfigurationStoring {
    private var configuration: OnboardingConfiguration

    public init(configuration: OnboardingConfiguration = .fresh) {
        self.configuration = configuration
    }

    public func loadConfiguration() -> OnboardingConfiguration {
        configuration
    }

    public func saveConfiguration(_ configuration: OnboardingConfiguration) {
        self.configuration = configuration
    }
}
