import Foundation

public struct NessaConversation: Decodable, Identifiable, Sendable, Equatable {
  public var id: String { conversationId }
  public let conversationId: String
  public let title: String?
  public let preview: String?
  public let updatedAtMs: Double
  public let running: Bool
}

public struct NessaConversationList: Decodable, Sendable, Equatable {
  public let conversations: [NessaConversation]
  public let complete: Bool
}

public struct NessaConversationView: Decodable, Sendable, Equatable {
  public let conversationId: String
  public let messages: [NessaTurn]
  public let permissions: [NessaPermission]
  public let truncated: Bool
  public let interactionViewError: String?
  public let runtime: NessaRuntime?
}

public struct NessaTurn: Decodable, Identifiable, Sendable, Equatable {
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

public struct NessaPart: Decodable, Sendable, Equatable {
  public let offset: Int
  public let kind: String
  public let text: String
  public let messageId: String?
}

public struct NessaPermission: Decodable, Identifiable, Sendable, Equatable {
  public var id: String { executionId + ":" + permissionId }
  public let executionId: String
  public let permissionId: String
  public let title: String
  public let toolName: String
  public let argumentsJson: String
  public let options: [Option]
  public struct Option: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let effect: String
  }
}

public struct NessaRuntime: Decodable, Sendable, Equatable {
  public let agent: String
  public var model: String? = nil
}

public struct MessageFragment: Identifiable, Sendable, Equatable {
  public let id: String
  public var text: String
}
