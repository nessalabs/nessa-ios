import Foundation

public struct ChatMessageRetentionPolicy: Equatable, Sendable {
    public let ttl: TimeInterval

    public init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    public static let oneHour = ChatMessageRetentionPolicy(ttl: 60 * 60)

    public func expirationDate(for createdAt: Date) -> Date {
        createdAt.addingTimeInterval(ttl)
    }
}

public protocol ChatMessagePersisting: Sendable {
    func loadActiveMessages(now: Date) throws -> [StoredChatMessage]
    func save(_ message: StoredChatMessage) throws
    func deleteMessages(ids: Set<UUID>) throws
    func deleteMessages(conversationID: String) throws
    func deleteMessages(area: String) throws
    func deleteExpired(before date: Date) throws
    func deleteAll() throws
}

public final class InMemoryChatMessageRepository: ChatMessagePersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [UUID: StoredChatMessage]

    public init(messages: [StoredChatMessage] = []) {
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    }

    public func loadActiveMessages(now: Date) throws -> [StoredChatMessage] {
        lock.withLock {
            messages.values
                .filter { !$0.isExpired(now: now) }
                .sorted { left, right in
                    if left.createdAt == right.createdAt {
                        return left.id.uuidString < right.id.uuidString
                    }
                    return left.createdAt < right.createdAt
                }
        }
    }

    public func save(_ message: StoredChatMessage) throws {
        lock.withLock {
            messages[message.id] = message
        }
    }

    public func deleteMessages(ids: Set<UUID>) throws {
        lock.withLock {
            for id in ids {
                messages[id] = nil
            }
        }
    }

    public func deleteMessages(conversationID: String) throws {
        lock.withLock {
            messages = messages.filter { $0.value.conversationID != conversationID }
        }
    }

    public func deleteMessages(area: String) throws {
        lock.withLock {
            messages = messages.filter { $0.value.area != area }
        }
    }

    public func deleteExpired(before date: Date) throws {
        lock.withLock {
            messages = messages.filter { !$0.value.isExpired(now: date) }
        }
    }

    public func deleteAll() throws {
        lock.withLock {
            messages.removeAll()
        }
    }
}
