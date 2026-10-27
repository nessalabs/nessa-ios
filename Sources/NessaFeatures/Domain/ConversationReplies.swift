import Foundation

public struct ConversationMessage: Identifiable, Equatable, Sendable {
  public enum Content: Equatable, Sendable {
    case text(String)
    case photos([NessaStoredAttachment])
    case file(NessaFileAttachment)
  }
  public let id: String
  public let turnID: String
  public let author: String
  public let outgoing: Bool
  public let content: Content
  public var summary: String {
    switch content {
    case .text(let text): text
    case .photos(let images): images.count == 1 ? "Photo" : "\(images.count) photos"
    case .file(let file): file.name
    }
  }
  public var reply: MessageReply { MessageReply(id: id, author: author, text: summary) }
}

/// Resolve reply relationships once per conversation snapshot, independently of rendering.
public struct ConversationReplies: Sendable {
  public let messages: [ConversationMessage]
  private let byID: [String: ConversationMessage]
  private let byTurn: [String: [ConversationMessage]]
  private let targets: [String: String]
  private let roots: [String: String]
  private let threads: [String: [ConversationMessage]]
  private let counts: [String: Int]

  public init(turns: [NessaTurn], targets savedTargets: [String: String], agentName: String) {
    var messages: [ConversationMessage] = []
    var targets = savedTargets
    for turn in turns {
      var userText = turn.userText
      if let context = MessageReply.splitContext(userText) {
        if targets[turn.id] == nil {
          // Migrate only unambiguous quotes produced by the earlier reply UI.
          let candidates = messages.filter { String($0.summary.prefix(500)) == context.quote }
          if candidates.count == 1 { targets[turn.id] = candidates[0].id }
        }
        if targets[turn.id] != nil { userText = context.body }
      }
      if let images = turn.attachments, !images.isEmpty {
        messages.append(
          ConversationMessage(
            id: turn.id + ":photos", turnID: turn.id, author: "You", outgoing: true,
            content: .photos(images)))
      }
      for (index, file) in (turn.files ?? []).enumerated() {
        messages.append(
          ConversationMessage(
            id: turn.id + ":file:\(index)", turnID: turn.id, author: "You", outgoing: true,
            content: .file(file)))
      }
      for (index, file) in (turn.uploads ?? []).enumerated() {
        messages.append(
          ConversationMessage(
            id: turn.id + ":upload:\(index)", turnID: turn.id, author: "You", outgoing: true,
            content: .file(NessaFileAttachment(name: file.name, mimeType: file.mimeType))))
      }
      if !userText.isEmpty {
        messages.append(
          ConversationMessage(
            id: turn.id + ":user", turnID: turn.id, author: "You", outgoing: true,
            content: .text(userText)))
      }
      for fragment in turn.displayBubbles {
        messages.append(
          ConversationMessage(
            id: turn.id + ":" + fragment.id, turnID: turn.id, author: agentName, outgoing: false,
            content: .text(fragment.text)))
      }
    }
    var byID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    for turn in turns {
      if let target = targets[turn.id], byID[target] == nil,
        let context = MessageReply.splitContext(turn.userText)
      {
        let outgoing =
          target.hasSuffix(":user") || target.hasSuffix(":photos")
          || (target.contains(":file:") || target.contains(":upload:"))
        byID[target] = ConversationMessage(
          id: target, turnID: "", author: outgoing ? "You" : agentName,
          outgoing: outgoing, content: .text(context.quote))
      }
    }
    var roots: [String: String] = [:]
    for message in messages {
      var cursor = message.id
      var visited: Set<String> = [cursor]
      while let current = byID[cursor], let target = targets[current.turnID], byID[target] != nil {
        guard visited.insert(target).inserted else { break }
        if let cached = roots[target] {
          cursor = cached
          break
        }
        cursor = target
      }
      roots[message.id] = cursor
    }
    var threads: [String: [ConversationMessage]] = [:]
    var replyTurns: [String: Set<String>] = [:]
    for message in messages {
      guard let root = roots[message.id], root != message.id else { continue }
      threads[root, default: []].append(message)
      replyTurns[root, default: []].insert(message.turnID)
    }
    self.messages = messages
    self.byID = byID
    self.byTurn = Dictionary(grouping: messages, by: \.turnID)
    self.targets = targets
    self.roots = roots
    self.threads = threads
    self.counts = replyTurns.mapValues(\.count)
  }

  public func message(_ id: String) -> ConversationMessage? { byID[id] }
  public func messages(in turn: String) -> [ConversationMessage] { byTurn[turn] ?? [] }
  public func parent(of message: ConversationMessage) -> ConversationMessage? {
    guard let target = targets[message.turnID] else { return nil }
    return byID[target]
  }
  public func root(for id: String) -> ConversationMessage? { byID[roots[id] ?? id] }
  public func replies(to id: String) -> [ConversationMessage] { threads[roots[id] ?? id] ?? [] }
  public func count(for id: String) -> Int { counts[id] ?? 0 }
}
