import Foundation

public enum NostrDesktopPairingAcknowledgement {
    public static let kind = 24_133
    public static let schema = "com.clawdia.nostr.pairing_ack.v1"

    public static func draft(
        phonePublicKey: String,
        desktopPublicKey: String,
        clientID: String,
        displayName: String,
        createdAt: Date = Date()
    ) throws -> NostrEventDraft {
        let content = NostrDesktopPairingAcknowledgementContent(
            schema: schema,
            clientID: clientID.lowercased(),
            displayName: displayName
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(content)
        guard let contentJSON = String(data: data, encoding: .utf8) else {
            throw NostrRelayClientMessageError.utf8EncodingFailed
        }
        return NostrEventDraft(
            pubkey: phonePublicKey.lowercased(),
            createdAt: Int(createdAt.timeIntervalSince1970),
            kind: kind,
            tags: [
                ["p", desktopPublicKey.lowercased()],
                ["clawdia", "pairing_ack"],
                ["client", clientID.lowercased()]
            ],
            content: contentJSON
        )
    }
}

private struct NostrDesktopPairingAcknowledgementContent: Encodable {
    let schema: String
    let clientID: String
    let displayName: String

    private enum CodingKeys: String, CodingKey {
        case schema
        case clientID = "client_id"
        case displayName = "display_name"
    }
}
