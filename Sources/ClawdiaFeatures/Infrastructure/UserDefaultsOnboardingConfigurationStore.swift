import Foundation

public final class UserDefaultsOnboardingConfigurationStore: OnboardingConfigurationStoring {
    private let userDefaults: UserDefaults
    private let completionKey: String
    private let selectedAreasKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        completionKey: String = "clawdia.onboarding.didComplete",
        selectedAreasKey: String = "clawdia.onboarding.selectedAreas"
    ) {
        self.userDefaults = userDefaults
        self.completionKey = completionKey
        self.selectedAreasKey = selectedAreasKey
    }

    public func loadConfiguration() -> OnboardingConfiguration {
        let rawAreas = userDefaults.stringArray(forKey: selectedAreasKey) ?? []
        let selectedAreas = Set(rawAreas.compactMap(LifeArea.init(rawValue:)))
        return OnboardingConfiguration(
            didComplete: userDefaults.bool(forKey: completionKey),
            selectedAreas: selectedAreas
        )
    }

    public func saveConfiguration(_ configuration: OnboardingConfiguration) {
        userDefaults.set(configuration.didComplete, forKey: completionKey)
        userDefaults.set(configuration.selectedAreas.map(\.rawValue).sorted(), forKey: selectedAreasKey)
    }
}
