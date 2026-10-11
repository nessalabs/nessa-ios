import Foundation

@MainActor public final class UserDefaultsChatPreferences: ChatPreferences {
  private let defaults: UserDefaults
  public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
  public func strings(forKey key: String) -> [String]? { defaults.stringArray(forKey: key) }
  public func mapping(forKey key: String) -> [String: String]? {
    defaults.dictionary(forKey: key) as? [String: String]
  }
  public func save(_ value: [String], forKey key: String) { defaults.set(value, forKey: key) }
  public func save(_ value: [String: String], forKey key: String) {
    defaults.set(value, forKey: key)
  }
}
