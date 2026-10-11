import Foundation

@MainActor public final class InMemoryChatPreferences: ChatPreferences {
  private var arrays: [String: [String]] = [:]
  private var dictionaries: [String: [String: String]] = [:]
  public init() {}
  public func strings(forKey key: String) -> [String]? { arrays[key] }
  public func mapping(forKey key: String) -> [String: String]? { dictionaries[key] }
  public func save(_ value: [String], forKey key: String) { arrays[key] = value }
  public func save(_ value: [String: String], forKey key: String) { dictionaries[key] = value }
}

public struct InMemoryCredentialStore: NessaCredentialStoring {
  public init() {}
  public func load() -> String? { nil }
  public func save(_ credential: String) {}
}
