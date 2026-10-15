import Foundation

/// Owned by the socket actor. Registers a server ID before its response resumes a caller.
struct GatewaySubscriptions {
  typealias Stream = AsyncThrowingStream<ConversationUpdate, Error>
  private struct Entry {
    let requestID: String
    let conversationID: String?
    var continuation: Stream.Continuation?
  }
  private var pending: [String: Entry] = [:]
  private var live: [String: Entry] = [:]
  var count: Int { pending.count + live.count }
  var registrations: [String] { Array(pending.keys) }
  func awaiting(_ requestID: String) -> Bool { pending[requestID] != nil }
  /// The phone owns one inbox and one visible thread; a replacement retires that slot.
  func replacement(for conversationID: String?) -> String? {
    (Array(pending.values) + Array(live.values)).first {
      (conversationID == nil) == ($0.conversationID == nil)
    }?.requestID
  }

  mutating func prepare(
    _ requestID: String, conversationID: String?,
    cancelled: @escaping @Sendable () -> Void
  ) throws -> Stream {
    // The phone follows one inbox and one visible thread; retain at most two frames.
    guard count < 2 else { throw NessaGatewayError.rejected("Too many live subscriptions.") }
    let (stream, continuation) = Stream.makeStream(bufferingPolicy: .bufferingNewest(1))
    continuation.onTermination = { _ in cancelled() }
    pending[requestID] = Entry(
      requestID: requestID, conversationID: conversationID,
      continuation: continuation)
    return stream
  }
  /// Returns the server subscription to clean up when the caller already canceled.
  mutating func activate(_ requestID: String, data: Data) throws -> String? {
    struct Registered: Decodable { let subscriptionId: String }
    let id = try JSONDecoder().decode(Registered.self, from: data).subscriptionId
    guard !id.isEmpty, id.utf8.count <= 128, live[id] == nil,
      let entry = pending.removeValue(forKey: requestID)
    else { throw NessaGatewayError.invalidFrame }
    if entry.continuation == nil { return id }
    live[id] = entry
    return nil
  }
  mutating func cancel(_ requestID: String) -> String? {
    if var entry = pending[requestID] {
      let continuation = entry.continuation
      entry.continuation = nil
      pending[requestID] = entry
      continuation?.finish()
      return nil
    }
    guard let pair = live.first(where: { $0.value.requestID == requestID }) else { return nil }
    live.removeValue(forKey: pair.key)?.continuation?.finish()
    return pair.key
  }
  mutating func fail(_ requestID: String, error: Error) {
    pending.removeValue(forKey: requestID)?.continuation?.finish(throwing: error)
  }
  mutating func finishAll(_ error: Error) {
    let entries = Array(pending.values) + Array(live.values)
    pending.removeAll()
    live.removeAll()
    for entry in entries { entry.continuation?.finish(throwing: error) }
  }
  /// Foreign/retired IDs are ignored. A malformed publication closes only its own feed.
  mutating func receive(_ name: String, payload: Data) -> String? {
    struct Identity: Decodable { let subscriptionId: String }
    guard let identity = try? JSONDecoder().decode(Identity.self, from: payload),
      let entry = live[identity.subscriptionId]
    else { return nil }
    do {
      switch name {
      case "conversation.view":
        struct Viewed: Decodable {
          let cursor: ConversationCursor
          let view: NessaConversationView
        }
        let frame = try JSONDecoder().decode(Viewed.self, from: payload)
        guard frame.view.conversationId == entry.conversationID else {
          throw NessaGatewayError.invalidFrame
        }
        entry.continuation?.yield(.view(frame.cursor, frame.view))
      case "conversation.listed":
        struct Listed: Decodable { let list: NessaConversationList }
        guard entry.conversationID == nil else { throw NessaGatewayError.invalidFrame }
        let frame = try JSONDecoder().decode(Listed.self, from: payload)
        entry.continuation?.yield(.list(frame.list))
      case "conversation.subscriptionEnded":
        struct Ended: Decodable {
          let reason: ConversationFeedEnded.Reason
          let code: String?
        }
        let end = try JSONDecoder().decode(Ended.self, from: payload)
        live.removeValue(forKey: identity.subscriptionId)
        entry.continuation?.finish(
          throwing: ConversationFeedEnded(reason: end.reason, code: end.code))
      default: return nil
      }
      return nil
    } catch {
      live.removeValue(forKey: identity.subscriptionId)
      entry.continuation?.finish(throwing: error)
      return identity.subscriptionId
    }
  }
}
