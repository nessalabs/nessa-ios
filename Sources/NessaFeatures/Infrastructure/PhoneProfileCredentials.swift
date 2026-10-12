import Foundation
import Security

/// Typed platform seam; no update operation exists for an immutable profile credential.
protocol PhoneProfileKeychain: Sendable {
  func read(reference: String) throws -> Data?
  func insert(_ data: Data, reference: String) throws
}
enum PhoneProfileKeychainIdentity { static let service = "app.nessa.ios.gateway.profiles" }

private struct SecurityProfileKeychain: PhoneProfileKeychain {
  private let service = PhoneProfileKeychainIdentity.service
  private func query(_ reference: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: reference,
    ]
  }
  func read(reference: String) throws -> Data? {
    var options = query(reference)
    options[kSecReturnData as String] = true
    options[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(options as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    try check(status)
    guard let data = result as? Data else { throw PhoneProfileCredentialError.corrupt }
    return data
  }
  func insert(_ data: Data, reference: String) throws {
    var options = query(reference)
    options[kSecValueData as String] = data
    options[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let status = SecItemAdd(options as CFDictionary, nil)
    if status != errSecDuplicateItem { try check(status) }
  }
  private func check(_ status: OSStatus) throws {
    if status == errSecInteractionNotAllowed { throw PhoneProfileCredentialError.locked }
    guard status == errSecSuccess else { throw PhoneProfileCredentialError.unavailable(status) }
  }
}
public actor PhoneProfileCredentials: PhoneProfileCredentialStoring {
  private let keychain: any PhoneProfileKeychain
  public init() { keychain = SecurityProfileKeychain() }
  init(keychain: any PhoneProfileKeychain) { self.keychain = keychain }
  public func load(reference: String) throws -> String {
    guard let data = try keychain.read(reference: reference) else {
      throw PhoneProfileCredentialError.missing
    }
    guard let value = String(data: data, encoding: .utf8), !value.isEmpty else {
      throw PhoneProfileCredentialError.corrupt
    }
    return value
  }
  public func insertOrVerify(_ credential: String, reference: String) throws {
    guard !credential.isEmpty else { throw PhoneProfileCredentialError.corrupt }
    let data = Data(credential.utf8)
    if let prior = try keychain.read(reference: reference) {
      guard String(data: prior, encoding: .utf8) != nil, !prior.isEmpty else {
        throw PhoneProfileCredentialError.corrupt
      }
      guard prior == data else { throw PhoneProfileCredentialError.conflict }
      return
    }
    try keychain.insert(data, reference: reference)
    guard let stored = try keychain.read(reference: reference) else {
      throw PhoneProfileCredentialError.missing
    }
    guard String(data: stored, encoding: .utf8) != nil, !stored.isEmpty else {
      throw PhoneProfileCredentialError.corrupt
    }
    guard stored == data else { throw PhoneProfileCredentialError.conflict }
  }
}
