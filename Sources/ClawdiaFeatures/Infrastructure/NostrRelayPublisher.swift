import Foundation

public struct NostrRelayPublishReceipt: Equatable, Sendable {
    public let relayURL: URL
    public let eventID: String
    public let accepted: Bool
    public let message: String

    public init(relayURL: URL, eventID: String, accepted: Bool, message: String) {
        self.relayURL = relayURL
        self.eventID = eventID
        self.accepted = accepted
        self.message = message
    }
}

public protocol NostrRelayPublishing: Sendable {
    func publish(_ event: NostrPreparedRelayEvent) async -> [NostrRelayPublishReceipt]
}

public struct NostrWebSocketRelayPublisher: NostrRelayPublishing {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func publish(_ event: NostrPreparedRelayEvent) async -> [NostrRelayPublishReceipt] {
        guard !event.relayURLs.isEmpty else {
            return []
        }
        return await withTaskGroup(of: NostrRelayPublishReceipt.self) { group in
            for relayURL in event.relayURLs {
                group.addTask {
                    await publish(event, to: relayURL)
                }
            }

            var receipts: [NostrRelayPublishReceipt] = []
            for await receipt in group {
                receipts.append(receipt)
            }
            return receipts.sorted { $0.relayURL.absoluteString < $1.relayURL.absoluteString }
        }
    }

    private func publish(_ event: NostrPreparedRelayEvent, to relayURL: URL) async -> NostrRelayPublishReceipt {
        let task = session.webSocketTask(with: relayURL)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
        }

        do {
            try await task.send(.string(event.relayClientMessageJSON()))
            let response = try await task.receive()
            switch response {
            case .string(let json):
                if let receipt = NostrRelayResponseParser.receipt(from: json, relayURL: relayURL) {
                    return receipt
                }
                return NostrRelayPublishReceipt(relayURL: relayURL, eventID: event.id, accepted: false, message: "unexpected relay response")
            case .data:
                return NostrRelayPublishReceipt(relayURL: relayURL, eventID: event.id, accepted: false, message: "unexpected binary relay response")
            @unknown default:
                return NostrRelayPublishReceipt(relayURL: relayURL, eventID: event.id, accepted: false, message: "unknown relay response")
            }
        } catch {
            return NostrRelayPublishReceipt(relayURL: relayURL, eventID: event.id, accepted: false, message: String(describing: error))
        }
    }
}

public final class NostrPublishingAgentMessageSender: NostrAgentMessageSending {
    private let encryptedSender: NostrEncryptedAgentMessageSender
    private let relayPublisher: any NostrRelayPublishing
    private let receiptHandler: @Sendable ([NostrRelayPublishReceipt]) -> Void

    public init(
        phonePrivateKeyHex: String,
        relayPublisher: any NostrRelayPublishing = NostrWebSocketRelayPublisher(),
        entropy: any NostrEntropySource = SystemNostrEntropySource(),
        receiptHandler: @escaping @Sendable ([NostrRelayPublishReceipt]) -> Void = { _ in }
    ) throws {
        self.encryptedSender = try NostrEncryptedAgentMessageSender(phonePrivateKeyHex: phonePrivateKeyHex, entropy: entropy)
        self.relayPublisher = relayPublisher
        self.receiptHandler = receiptHandler
    }

    public func send(_ event: NostrOutboxEvent) throws -> NostrPreparedRelayEvent {
        let prepared = try encryptedSender.send(event)
        let relayPublisher = relayPublisher
        let receiptHandler = receiptHandler
        Task {
            let receipts = await relayPublisher.publish(prepared)
            receiptHandler(receipts)
        }
        return prepared
    }
}

public enum NostrRelayResponseParser {
    public static func receipt(from json: String, relayURL: URL) -> NostrRelayPublishReceipt? {
        guard let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [Any],
              values.count >= 4,
              values[0] as? String == "OK",
              let eventID = values[1] as? String,
              let accepted = values[2] as? Bool,
              let message = values[3] as? String else {
            return nil
        }
        return NostrRelayPublishReceipt(relayURL: relayURL, eventID: eventID, accepted: accepted, message: message)
    }
}
