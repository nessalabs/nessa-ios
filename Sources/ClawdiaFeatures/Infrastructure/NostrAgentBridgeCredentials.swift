import Foundation
import Security

public struct NostrAgentBridgeCredentials: Codable, Equatable, Sendable {
    public let phonePrivateKeyHex: String
    public let desktopPublicKeyHex: String
    public let relayURLStrings: [String]
    public let desktopDisplayName: String?

    public init(
        phonePrivateKeyHex: String,
        desktopPublicKeyHex: String,
        relayURLs: [URL],
        desktopDisplayName: String? = nil
    ) throws {
        _ = try NostrAgentKeypair(privateKeyHex: phonePrivateKeyHex)
        guard Self.isLowercaseHex(desktopPublicKeyHex, byteCount: 32) else {
            throw NostrAgentBridgeCredentialsError.invalidDesktopPublicKey
        }
        self.phonePrivateKeyHex = phonePrivateKeyHex.lowercased()
        self.desktopPublicKeyHex = desktopPublicKeyHex.lowercased()
        self.relayURLStrings = relayURLs.map(\.absoluteString)
        self.desktopDisplayName = desktopDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public func bridgeConfiguration() throws -> NostrAgentBridgeConfiguration {
        let phonePublicKey = try NostrAgentKeypair(privateKeyHex: phonePrivateKeyHex).publicKeyHex
        let relayURLs = try relayURLStrings.map { relayURLString in
            guard let url = URL(string: relayURLString),
                  ["ws", "wss"].contains(url.scheme?.lowercased() ?? "") else {
                throw NostrAgentBridgeCredentialsError.invalidRelayURL(relayURLString)
            }
            return url
        }
        return NostrAgentBridgeConfiguration(
            phonePublicKey: phonePublicKey,
            desktopPublicKey: desktopPublicKeyHex,
            relayURLs: relayURLs
        )
    }

    private static func isLowercaseHex(_ value: String, byteCount: Int) -> Bool {
        let normalized = value.lowercased()
        guard normalized.count == byteCount * 2 else {
            return false
        }
        return normalized.allSatisfy { character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
        }
    }
}

public enum NostrAgentBridgeCredentialsError: Error, Equatable {
    case invalidDesktopPublicKey
    case invalidRelayURL(String)
}

public protocol NostrAgentBridgeCredentialStoring {
    func loadCredentials() throws -> NostrAgentBridgeCredentials?
    func saveCredentials(_ credentials: NostrAgentBridgeCredentials) throws
    func deleteCredentials() throws
}

public struct KeychainNostrAgentBridgeCredentialStore: NostrAgentBridgeCredentialStoring {
    private let service: String
    private let account: String

    public init(service: String = "com.clawdia.mobile.nostr-agent-bridge", account: String = "default") {
        self.service = service
        self.account = account
    }

    public func loadCredentials() throws -> NostrAgentBridgeCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainNostrAgentBridgeCredentialStoreError.unhandledStatus(status)
        }
        return try JSONDecoder().decode(NostrAgentBridgeCredentials.self, from: data)
    }

    public func saveCredentials(_ credentials: NostrAgentBridgeCredentials) throws {
        try deleteCredentials()
        var query = baseQuery()
        query[kSecValueData as String] = try JSONEncoder().encode(credentials)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainNostrAgentBridgeCredentialStoreError.unhandledStatus(status)
        }
    }

    public func deleteCredentials() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainNostrAgentBridgeCredentialStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public enum KeychainNostrAgentBridgeCredentialStoreError: Error, Equatable {
    case unhandledStatus(OSStatus)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
