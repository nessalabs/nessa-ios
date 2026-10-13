import Foundation

/// The only production wiring point: UI and application code never construct adapters.
@MainActor public struct NessaDependencies {
  public enum Mode { case live, development }
  public let mode: Mode
  public let service: MessagingService
  public let credentials: any NessaCredentialStoring
  public let preferences: any ChatPreferences
  public let retainedSessions: (any RetainedSessionFactory)?
  public let phoneSync: (any PhoneSyncRunning)?
  private let snapshots: PhoneSnapshotSession
  private let recovery: ConnectionRecovery
  private let speechFactory: @MainActor () -> any SpeechTranscribing
  let launchConnection: (address: String, credential: String)?
  public init(
    mode: Mode, repository: any MessagingRepository, directory: (any AgentDirectory)? = nil,
    credentials: any NessaCredentialStoring, preferences: any ChatPreferences,
    launchConnection: (address: String, credential: String)? = nil,
    speechFactory: (@MainActor () -> any SpeechTranscribing)? = nil,
    snapshots: PhoneSnapshotSession? = nil, recovery: ConnectionRecovery? = nil,
    retainedSessions: (any RetainedSessionFactory)? = nil,
    phoneSync: (any PhoneSyncRunning)? = nil
  ) {
    self.mode = mode
    self.service = MessagingService(
      repository: repository, directory: directory ?? (repository as? any AgentDirectory))
    self.credentials = credentials
    self.preferences = preferences
    self.retainedSessions = retainedSessions
    let snapshotOwner =
      snapshots
      ?? PhoneSnapshotSession(
        store: mode == .live ? PhoneSnapshotStore() : InMemoryPhoneSnapshotStore())
    self.snapshots = snapshotOwner
    if let phoneSync {
      self.phoneSync = phoneSync
    } else if mode == .live, let retainedSessions,
      let identity = repository as? any AuthenticatedGatewaySessionProviding,
      let pairing = repository as? any GatewayPairingManaging
    {
      let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nessa/PhoneProfiles", isDirectory: true)
      let profiles = PhoneProfileStore(root: root)
      let profileCredentials = PhoneProfileCredentials()
      let locations = PhoneNativeLocations(root: root)
      self.phoneSync = PhoneSyncRuntime(
        profiles: profiles, credentials: profileCredentials,
        factory: {
          PhoneProfileCoordinator(
            profiles: profiles, credentials: profileCredentials, locations: locations,
            identity: identity, pairing: pairing, factory: retainedSessions,
            withdrawal: snapshotOwner)
        })
    } else {
      self.phoneSync = nil
    }
    self.recovery = recovery ?? ConnectionRecovery(waiting: SystemRecoveryWait())
    self.launchConnection = launchConnection
    self.speechFactory =
      speechFactory ?? {
        if mode == .development { return MockSpeechTranscriber() }
        return AppleSpeechTranscriber()
      }
  }
  public static func live() -> Self {
    Self(
      mode: .live, repository: liveRepository(), credentials: NessaCredentialStore(),
      preferences: UserDefaultsChatPreferences(), retainedSessions: NativeRetainedSessionFactory())
  }
  public static func development(repository: any MessagingRepository = MockRepository()) -> Self {
    Self(
      mode: .development, repository: repository, credentials: InMemoryCredentialStore(),
      preferences: InMemoryChatPreferences())
  }
  public static func configured(environment: [String: String] = ProcessInfo.processInfo.environment)
    -> Self
  {
    #if DEBUG
      if environment["NESSA_MODE"] == "live" {
        let launchConnection: (address: String, credential: String)?
        if let address = environment["NESSA_TEST_GATEWAY_URL"],
          let credential = environment["NESSA_TEST_CREDENTIAL"], !credential.isEmpty
        {
          launchConnection = (address, credential)
        } else {
          launchConnection = nil
        }
        return Self(
          mode: .live, repository: liveRepository(),
          credentials: NessaCredentialStore(), preferences: UserDefaultsChatPreferences(),
          launchConnection: launchConnection, retainedSessions: NativeRetainedSessionFactory())
      }
      return .development()
    #else
      return .live()
    #endif
  }
  public func makeMessagesViewModel() -> MessagesViewModel {
    MessagesViewModel(
      service: service, credentials: credentials, preferences: preferences,
      snapshots: snapshots, recovery: recovery, phoneSync: phoneSync)
  }
  private static func liveRepository() -> NessaGatewayClient {
    NessaGatewayClient(journal: PhoneCommandJournal(store: PhoneCommandStore()))
  }
  public func makeDictationViewModel() -> DictationViewModel {
    DictationViewModel(transcriber: speechFactory())
  }
}
