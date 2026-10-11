import Foundation

/// The only production wiring point: UI and application code never construct adapters.
@MainActor public struct NessaDependencies {
  public enum Mode { case live, development }
  public let mode: Mode
  public let service: MessagingService
  public let credentials: any NessaCredentialStoring
  public let preferences: any ChatPreferences
  public init(
    mode: Mode, repository: any MessagingRepository, directory: (any AgentDirectory)? = nil,
    credentials: any NessaCredentialStoring, preferences: any ChatPreferences
  ) {
    self.mode = mode
    self.service = MessagingService(
      repository: repository, directory: directory ?? (repository as? any AgentDirectory))
    self.credentials = credentials
    self.preferences = preferences
  }
  public static func live() -> Self {
    Self(
      mode: .live, repository: NessaGatewayClient(), credentials: NessaCredentialStore(),
      preferences: UserDefaultsChatPreferences())
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
      environment["NESSA_MODE"] == "live" ? .live() : .development()
    #else
      .live()
    #endif
  }
  public func makeMessagesViewModel() -> MessagesViewModel {
    MessagesViewModel(service: service, credentials: credentials, preferences: preferences)
  }
}
