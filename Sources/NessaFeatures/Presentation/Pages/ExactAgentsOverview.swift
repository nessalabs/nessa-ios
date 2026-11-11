import CryptoKit
import Foundation

/// Projects the live phone session into the Agents screen. Mutations resolve their
/// identifiers against the same session again when the person taps an action.
@MainActor
struct ExactAgentsOverview {
  let store: MessagesViewModel

  func snapshot() -> [String: Any] {
    let glance = store.agentsGlance
    let chats = Dictionary(store.visibleConversations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let channels = Dictionary(store.channels.filter { !$0.isDefault }.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    let groups: [[String: Any]] = AgentsGroup.allCases.compactMap { group in
      let rows = glance.ids(group).compactMap { id -> [String: Any]? in
        guard let chat = chats[id] else { return nil }
        let review = group == .needsYou ? store.waitingPermission(in: id) : nil
        let subtitle: String
        switch group {
        case .needsYou: subtitle = "Waiting for your answer"
        case .working: subtitle = "\(store.agentName(for: id)) is working…"
        case .finished, .earlier: subtitle = chat.preview ?? "New conversation"
        }
        let opts = review?.options ?? []
        let primary = opts.first { $0.effect == "allow" }?.id
        let order = opts.filter { $0.effect != "allow" } + opts.filter { $0.effect == "allow" }
        return [
          "id": id, "name": chat.title ?? store.agentName(for: id), "detail": subtitle,
          "channel": chat.channelId.flatMap { channels[$0] } ?? "",
          "reviewStamp": review.map(Self.stamp) ?? "", "title": review?.title ?? "",
          "arguments": review?.argumentsJson ?? "",
          "options": order.map { ["id": $0.id, "label": $0.label, "primary": $0.id == primary] as [String: Any] },
        ]
      }
      guard !rows.isEmpty else { return nil }
      return ["id": group.rawValue, "title": group.title, "rows": rows]
    }
    let pending: [[String: Any]] = store.pendingCreations.map {
      ["id": $0.requestID, "checking": store.checkingCommands.contains($0.requestID)]
    }
    return [
      "groups": groups, "pendingChats": pending, "complete": store.listComplete,
      "pendingUnavailable": store.pendingLoadError != nil, "connected": store.connected,
      "canAct": store.connected && store.conversationAuthorityReady,
      "scope": store.deliveryScopeRevision, "connection": store.connectionRevision,
    ]
  }

  /// An answer applies only to the exact request and offered options the person saw.
  /// This also rejects a changed request that reuses a review key on the same connection.
  private static func stamp(_ review: NessaPermission) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(review) else { return "" }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  func perform(_ request: [String: Any]) async -> String? {
    guard request["scope"] as? Int == store.deliveryScopeRevision,
          request["connection"] as? Int == store.connectionRevision,
          let verb = request["verb"] as? String else { return nil }
    let id = request["id"] as? String ?? ""
    switch verb {
    case "refresh":
      if !store.connected { await store.reconnectLinked(); return nil }
      do { try await store.refreshList() } catch { store.error = error.localizedDescription }
    case "reconnect":
      guard store.pendingLoadError != nil else { return nil }
      await store.reconnectDeliveryState()
    case "check", "retry":
      guard store.pendingCreations.contains(where: { $0.requestID == id }) else { return nil }
      return await store.recoverCommand(id, retry: verb == "retry")
    case "archive", "delete":
      guard store.connected, store.visibleConversations.contains(where: { $0.id == id }),
            !store.archivedChats.contains(id) else { return nil }
      if verb == "archive" {
        await store.setArchived(true, conversationID: id)
      } else if store.conversationAuthorityReady {
        await store.deleteConversations([id])
      }
    case "answer":
      guard store.connected, store.conversationAuthorityReady,
            let review = store.waitingPermission(in: id),
            let stamp = request["stamp"] as? String, !stamp.isEmpty, stamp == Self.stamp(review),
            let optionID = request["option"] as? String,
            let option = review.options.first(where: { $0.id == optionID }) else { return nil }
      await store.answer(review, option: option, in: id)
    default: break
    }
    return nil
  }
}

#if os(iOS)
import Combine

extension ExactPhoneSession {
  public func observeAgents(_ changed: @escaping (String) -> Void) -> AnyCancellable {
    // Subscribers read the post-change state; a streaming turn can publish several
    // related model changes in one run-loop turn.
    messages.objectWillChange.receive(on: RunLoop.main)
      .throttle(for: .milliseconds(32), scheduler: RunLoop.main, latest: true)
      .sink { changed("agents") }
  }

  public var agentsSnapshot: [String: Any] { ExactAgentsOverview(store: messages).snapshot() }

  public func performAgentCommand(_ request: [String: Any]) async -> [String: Any] {
    ["chat": await ExactAgentsOverview(store: messages).perform(request) ?? ""]
  }
}
#endif
