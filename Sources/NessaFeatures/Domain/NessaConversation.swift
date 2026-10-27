import Foundation

public struct NessaConversation: Codable, Identifiable, Sendable, Equatable {
  public var id: String { conversationId }
  public let conversationId: String
  public let title: String?
  public let preview: String?
  public let updatedAtMs: Double
  public let running: Bool
  /// The channel the conversation belongs to; none for one in the default channel or from a
  /// gateway that lists no channels.
  public var channelId: String? = nil
}

public struct NessaConversationList: Codable, Sendable, Equatable {
  public let conversations: [NessaConversation]
  public let complete: Bool
}

public struct NessaConversationView: Codable, Sendable, Equatable {
  public let conversationId: String
  public let messages: [NessaTurn]
  /// Every review waiting in the chat, oldest first, as the gateway's view lists it: by key
  /// alone. What one asks is read on its own (`conversation.permissionReview`).
  public let reviews: [NessaReviewEntry]
  /// The listed reviews this phone has read in full, in the order `reviews` lists them. A
  /// review not read yet, or answered between the two reads, is not here.
  public var permissions: [NessaPermission]
  public let truncated: Bool
  public let interactionViewError: String?
  public let runtime: NessaRuntime?

  /// `reviews` defaults to the entries `permissions` would be listed by, as a view whose
  /// reviews were all read.
  public init(
    conversationId: String, messages: [NessaTurn], permissions: [NessaPermission],
    truncated: Bool, interactionViewError: String?, runtime: NessaRuntime?,
    reviews: [NessaReviewEntry]? = nil
  ) {
    self.conversationId = conversationId
    self.messages = messages
    self.reviews = reviews ?? permissions.map(NessaReviewEntry.init)
    self.permissions = permissions
    self.truncated = truncated
    self.interactionViewError = interactionViewError
    self.runtime = runtime
  }

  /// The gateway's `permissions` are the review entries; nothing it sends is a full review.
  private enum CodingKeys: String, CodingKey {
    case conversationId, messages, reviews = "permissions", truncated, interactionViewError,
      runtime
  }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    conversationId = try container.decode(String.self, forKey: .conversationId)
    messages = try container.decode([NessaTurn].self, forKey: .messages)
    reviews = try container.decode([NessaReviewEntry].self, forKey: .reviews)
    permissions = []
    truncated = try container.decode(Bool.self, forKey: .truncated)
    interactionViewError = try container.decodeIfPresent(
      String.self, forKey: .interactionViewError)
    runtime = try container.decodeIfPresent(NessaRuntime.self, forKey: .runtime)
  }
  /// Written as the gateway sends it, so a saved view reads back the same way: a review's
  /// content is never kept, since it may be answered by the time the view is read again.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(conversationId, forKey: .conversationId)
    try container.encode(messages, forKey: .messages)
    try container.encode(reviews, forKey: .reviews)
    try container.encode(truncated, forKey: .truncated)
    try container.encodeIfPresent(interactionViewError, forKey: .interactionViewError)
    try container.encodeIfPresent(runtime, forKey: .runtime)
  }
}

/// One review waiting in a chat, as its view lists it: the review's own key (new for every
/// review opened), who asked, and the start of the tool's name.
public struct NessaReviewEntry: Codable, Sendable, Equatable {
  public let review: String
  /// `harness` for the agent, `app` for an MCP App.
  public let origin: String
  public let toolName: String
  public init(review: String, origin: String, toolName: String) {
    self.review = review
    self.origin = origin
    self.toolName = toolName
  }
  /// The entry a view lists `permission` by.
  init(_ permission: NessaPermission) {
    self.init(review: permission.review, origin: "harness", toolName: permission.toolName)
  }
}

public struct NessaTurn: Codable, Identifiable, Sendable, Equatable {
  public var id: String { executionId }
  public let executionId: String
  public let userText: String
  public let status: String
  public let error: String?
  public let parts: [NessaPart]
  public var attachments: [NessaImageAttachment]? = nil
  public var files: [NessaFileAttachment]? = nil
  /// Join only adjacent fragments carrying the same provider message identity.
  public var bubbles: [String] { displayBubbles.map(\.text) }
  /// Whether the agent's reply is still to come: the turn runs, or waits for the agent to
  /// start (a cold start can take a while), so the chat shows it typing either way.
  public var awaitsReply: Bool { status == "running" || status == "queued" }
  public var displayBubbles: [MessageFragment] {
    var result: [MessageFragment] = []
    var previousID: String?
    var previousKind: String?
    for part in parts.sorted(by: { $0.offset < $1.offset }) {
      guard part.kind == "text" || part.kind == "local_notice" else {
        previousID = nil
        previousKind = nil
        continue
      }
      if part.kind == "text", let identity = part.messageId,
        previousID == identity, previousKind == "text", !result.isEmpty
      {
        result[result.count - 1].text += part.text
      } else {
        result.append(
          MessageFragment(id: "\(part.messageId ?? "part"):\(part.offset)", text: part.text))
      }
      previousID = part.messageId
      previousKind = part.kind
    }
    return result.filter { !$0.text.isEmpty }
  }
}

public struct NessaPart: Codable, Sendable, Equatable {
  public let offset: Int
  public let kind: String
  public let text: String
  public let messageId: String?
}

public struct NessaPermission: Codable, Identifiable, Sendable, Equatable {
  public var id: String { executionId + ":" + permissionId }
  /// The key the view lists it under; an answer names it.
  public let review: String
  public let executionId: String
  public let permissionId: String
  public let title: String
  public let toolName: String
  public let argumentsJson: String
  public let options: [Option]
  public struct Option: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let effect: String
  }
}

public struct NessaRuntime: Codable, Sendable, Equatable {
  public let agent: String
  public var model: String? = nil
}

public struct MessageFragment: Identifiable, Sendable, Equatable {
  public let id: String
  public var text: String
}
