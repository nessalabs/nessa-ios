import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(HealthKit)
import HealthKit
#endif

public final class SystemIPhoneDataConnectionProvider: NSObject, IPhoneDataConnectionProviding, @unchecked Sendable {
    #if canImport(CoreLocation)
    private var locationManager: CLLocationManager?
    #endif
    private let iCloudIdentityToken: @Sendable () -> Any?

    public init(iCloudIdentityToken: @escaping @Sendable () -> Any?) {
        self.iCloudIdentityToken = iCloudIdentityToken
        super.init()
    }

    public override convenience init() {
        self.init(iCloudIdentityToken: { FileManager.default.ubiquityIdentityToken })
    }

    public func loadConnections() async -> [IPhoneDataConnection] {
        await [
            iCloudConnection(),
            healthConnection(),
            locationConnection()
        ]
    }

    public func requestConnection(_ kind: IPhoneDataConnectionKind) async -> IPhoneDataConnection {
        switch kind {
        case .iCloud:
            return await iCloudConnection()
        case .health:
            return await requestHealthConnection()
        case .location:
            return await requestLocationConnection()
        }
    }

    private func iCloudConnection() async -> IPhoneDataConnection {
        let hasIdentityToken = iCloudIdentityToken() != nil
        return IPhoneDataConnection(
            kind: .iCloud,
            status: hasIdentityToken ? .connected : .unavailable,
            includeInDesktopAnalysis: hasIdentityToken
        )
    }

    private func healthConnection() async -> IPhoneDataConnection {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return IPhoneDataConnection(kind: .health, status: .unavailable, includeInDesktopAnalysis: false)
        }
        return IPhoneDataConnection(kind: .health, status: .notDetermined, includeInDesktopAnalysis: false)
        #else
        return IPhoneDataConnection(kind: .health, status: .unavailable, includeInDesktopAnalysis: false)
        #endif
    }

    private func requestHealthConnection() async -> IPhoneDataConnection {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return IPhoneDataConnection(kind: .health, status: .unavailable, includeInDesktopAnalysis: false)
        }
        let healthStore = HKHealthStore()
        let readTypes = Self.healthReadTypes()
        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, _ in
                continuation.resume(returning: IPhoneDataConnection(
                    kind: .health,
                    status: success ? .connected : .denied,
                    includeInDesktopAnalysis: success
                ))
            }
        }
        #else
        return IPhoneDataConnection(kind: .health, status: .unavailable, includeInDesktopAnalysis: false)
        #endif
    }

    private func locationConnection() async -> IPhoneDataConnection {
        #if canImport(CoreLocation)
        let status = Self.currentLocationAuthorizationStatus()
        return IPhoneDataConnection(
            kind: .location,
            status: Self.locationConnectionStatus(from: status),
            includeInDesktopAnalysis: Self.isLocationAuthorized(status)
        )
        #else
        return IPhoneDataConnection(kind: .location, status: .unavailable, includeInDesktopAnalysis: false)
        #endif
    }

    @MainActor
    private func requestLocationConnection() async -> IPhoneDataConnection {
        #if canImport(CoreLocation)
        let manager = locationManager ?? CLLocationManager()
        locationManager = manager
        #if os(iOS)
        manager.requestWhenInUseAuthorization()
        #endif
        let status = Self.currentLocationAuthorizationStatus(manager: manager)
        return IPhoneDataConnection(
            kind: .location,
            status: status == .notDetermined ? .requesting : Self.locationConnectionStatus(from: status),
            includeInDesktopAnalysis: Self.isLocationAuthorized(status)
        )
        #else
        return IPhoneDataConnection(kind: .location, status: .unavailable, includeInDesktopAnalysis: false)
        #endif
    }

    #if canImport(CoreLocation)
    private static func locationConnectionStatus(from status: CLAuthorizationStatus) -> IPhoneDataConnectionStatus {
        switch status {
        case .authorizedAlways:
            return .connected
        #if os(iOS)
        case .authorizedWhenInUse:
            return .connected
        #endif
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
    }

    private static func isLocationAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        if status == .authorizedAlways {
            return true
        }
        #if os(iOS)
        if status == .authorizedWhenInUse {
            return true
        }
        #endif
        return false
    }

    private static func currentLocationAuthorizationStatus(manager: CLLocationManager = CLLocationManager()) -> CLAuthorizationStatus {
        #if os(macOS)
        return manager.authorizationStatus
        #else
        return CLLocationManager.authorizationStatus()
        #endif
    }
    #endif

    #if canImport(HealthKit)
    private static func healthReadTypes() -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        [
            HKQuantityTypeIdentifier.activeEnergyBurned,
            .basalEnergyBurned,
            .bodyMass,
            .distanceWalkingRunning,
            .flightsClimbed,
            .heartRate,
            .oxygenSaturation,
            .respiratoryRate,
            .restingHeartRate,
            .stepCount
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }
            .forEach { types.insert($0) }

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }
    #endif
}
