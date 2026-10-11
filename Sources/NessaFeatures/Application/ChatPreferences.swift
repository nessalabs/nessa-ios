import Foundation

/// Local persistence port; keys are scoped by gateway and device instance.
@MainActor public protocol ChatPreferences {
  func strings(forKey key: String) -> [String]?
  func mapping(forKey key: String) -> [String: String]?
  func save(_ value: [String], forKey key: String)
  func save(_ value: [String: String], forKey key: String)
}
