import Foundation

public struct NostrDesktopPairingPayload: Equatable, Sendable {
    public static let scheme = "clawdia"
    public static let host = "pair"
    public static let path = "/nostr"

    public let desktopPublicKeyHex: String
    public let relayURLs: [URL]
    public let desktopName: String?

    public init(desktopPublicKeyHex: String, relayURLs: [URL], desktopName: String? = nil) throws {
        guard Self.isHex(desktopPublicKeyHex, byteCount: 32) else {
            throw NostrDesktopPairingPayloadError.invalidDesktopPublicKey
        }
        guard !relayURLs.isEmpty, relayURLs.allSatisfy(Self.isRelayURL) else {
            throw NostrDesktopPairingPayloadError.invalidRelayURL
        }
        self.desktopPublicKeyHex = desktopPublicKeyHex.lowercased()
        self.relayURLs = relayURLs
        self.desktopName = desktopName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public static func parse(_ rawValue: String) throws -> Self {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host,
              components.path == path else {
            throw NostrDesktopPairingPayloadError.invalidFormat
        }
        let queryItems = components.queryItems ?? []
        guard let desktopPublicKeyHex = queryItems.first(where: { $0.name == "desktop_pubkey" })?.value else {
            throw NostrDesktopPairingPayloadError.invalidDesktopPublicKey
        }
        let relayURLs = queryItems
            .filter { $0.name == "relay" }
            .compactMap(\.value)
            .compactMap(URL.init(string:))
        let desktopName = queryItems.first(where: { $0.name == "name" })?.value
        return try Self(desktopPublicKeyHex: desktopPublicKeyHex, relayURLs: relayURLs, desktopName: desktopName)
    }

    public func pairingURI() throws -> String {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = Self.path
        components.queryItems = [
            URLQueryItem(name: "desktop_pubkey", value: desktopPublicKeyHex)
        ] + relayURLs.map { URLQueryItem(name: "relay", value: $0.absoluteString) }
        if let desktopName {
            components.queryItems?.append(URLQueryItem(name: "name", value: desktopName))
        }
        guard let uri = components.url?.absoluteString else {
            throw NostrDesktopPairingPayloadError.invalidFormat
        }
        return uri
    }

    private static func isRelayURL(_ url: URL) -> Bool {
        ["ws", "wss"].contains(url.scheme?.lowercased() ?? "")
    }

    private static func isHex(_ value: String, byteCount: Int) -> Bool {
        let normalized = value.lowercased()
        guard normalized.count == byteCount * 2 else {
            return false
        }
        return normalized.allSatisfy { character in
            ("0"..."9").contains(character) || ("a"..."f").contains(character)
        }
    }
}

public enum NostrDesktopPairingPayloadError: Error, Equatable {
    case invalidDesktopPublicKey
    case invalidFormat
    case invalidRelayURL
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
