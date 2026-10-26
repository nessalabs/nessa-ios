import Foundation

/// The groups the Agents view sorts chats into, in the order it shows them: what waits on the
/// person, what is working, what finished and has not been looked at, and the rest.
public enum AgentsGroup: String, CaseIterable, Sendable {
  case needsYou, working, finished, earlier

  public var title: String {
    switch self {
    case .needsYou: return "Needs you"
    case .working: return "Working"
    case .finished: return "Finished"
    case .earlier: return "Earlier"
    }
  }
}

/// Every chat in exactly one group, each newest first. The one rule: waiting on the person
/// beats working, working beats finished, and finished means unread.
public struct AgentsGlance: Equatable, Sendable {
  public private(set) var groups: [AgentsGroup: [String]] = [:]

  public init(conversations: [NessaConversation], waiting: Set<String>, unread: Set<String>) {
    for conversation in conversations.sorted(by: { $0.updatedAtMs > $1.updatedAtMs }) {
      groups[Self.group(conversation, waiting: waiting, unread: unread), default: []]
        .append(conversation.id)
    }
  }

  public static func group(
    _ conversation: NessaConversation, waiting: Set<String>, unread: Set<String>
  ) -> AgentsGroup {
    if waiting.contains(conversation.id) { return .needsYou }
    if conversation.running { return .working }
    return unread.contains(conversation.id) ? .finished : .earlier
  }

  public func ids(_ group: AgentsGroup) -> [String] { groups[group] ?? [] }
  public func count(_ group: AgentsGroup) -> Int { ids(group).count }
}
