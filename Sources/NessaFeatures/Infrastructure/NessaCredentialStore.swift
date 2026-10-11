import Foundation
import Security

public struct NessaCredentialStore: NessaCredentialStoring {
  public init() {}
  public func load() -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
  public func save(_ credential: String) throws {
    let data = Data(credential.utf8)
    let update = [kSecValueData as String: data]
    var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var query = baseQuery
      query[kSecValueData as String] = data
      query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      status = SecItemAdd(query as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw NessaGatewayError.rejected(
        "Could not save the gateway credential in Keychain (\(status)).")
    }
  }
  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.nessa.ios.gateway", kSecAttrAccount as String: "product-v1",
    ]
  }
}
