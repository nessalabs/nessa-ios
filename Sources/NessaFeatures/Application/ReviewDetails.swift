import Foundation

/// What each waiting review asks, read once per review. A view lists its reviews by key
/// alone, and a key is new for every review opened, so a review read once never changes:
/// a chat's every later view (each streamed reply is one) reuses it rather than reading it
/// again. A read that failed is tried again only after `retryAfter`, so a review that can't
/// be read is not read on every frame, yet one a dropped connection cut off still shows.
actor ReviewDetails {
  private enum Entry {
    case reading(Task<NessaPermission?, Never>)
    case read(NessaPermission)
    case failed(at: Date)
  }
  private var entries: [String: Entry] = [:]
  private let retryAfter: TimeInterval
  init(retryAfter: TimeInterval = 5) { self.retryAfter = retryAfter }

  /// `view` with each review it lists read in full, in the order it lists them. One that
  /// could not be read is left out: the view still shows, without its card.
  func resolve(_ view: NessaConversationView, with reader: any PermissionReviewReading) async
    -> NessaConversationView
  {
    let chat = view.conversationId
    let listed = Set(view.reviews.map { Self.key(chat, $0.review) })
    // A review the chat no longer lists was answered or withdrawn.
    for key in entries.keys where key.hasPrefix(chat + "\u{0}") && !listed.contains(key) {
      entries.removeValue(forKey: key)
    }
    var permissions: [NessaPermission] = []
    for entry in view.reviews {
      if let permission = await read(entry.review, in: chat, with: reader) {
        permissions.append(permission)
      }
    }
    var resolved = view
    resolved.permissions = permissions
    return resolved
  }

  private func read(_ review: String, in chat: String, with reader: any PermissionReviewReading)
    async -> NessaPermission?
  {
    let key = Self.key(chat, review)
    switch entries[key] {
    case .read(let permission): return permission
    case .reading(let task): return await task.value
    case .failed(let at) where Date().timeIntervalSince(at) < retryAfter: return nil
    case .failed, nil: break
    }
    let task = Task { try? await reader.permissionReview(review, conversationID: chat) }
    entries[key] = .reading(task)
    let permission = await task.value
    // Left alone if the chat stopped listing it meanwhile.
    if case .reading = entries[key] {
      entries[key] = permission.map(Entry.read) ?? .failed(at: Date())
    }
    return permission
  }

  private static func key(_ chat: String, _ review: String) -> String { chat + "\u{0}" + review }
}
