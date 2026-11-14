import Foundation

/// All transcript rows share the same Contract shape. Media identifiers represent occurrences,
/// so a turn containing the same photo twice still has two separately navigable cards.
enum ExactBubbleProjection {
  static func notice(_ kind: String, id: String, text: String, scope: Int) -> [String: Any] {
    ["id": id, "kind": kind, "text": text, "first": false, "scope": scope,
     "outgoing": false, "reaction": "", "photos": [], "parentID": "", "parentText": "",
     "parentAuthor": "", "parentOutgoing": false, "replyCount": 0]
  }

  static func message(_ message: ConversationMessage, parent: ConversationMessage?, replies: Int,
    reaction: String?, scope: Int) -> [String: Any]
  {
    let kind: String
    var photos: [[String: Any]] = []
    switch message.content {
    case .text: kind = "text"
    case .file: kind = "file"
    case .photos(let attachments):
      kind = "photo"
      photos = attachments.indices.map { ["id": "\(message.turnID):image:\($0)", "index": $0] }
    }
    var row = notice(kind, id: message.id, text: message.summary, scope: scope)
    row["outgoing"] = message.outgoing
    row["reaction"] = reaction ?? ""
    row["photos"] = photos
    row["replyCount"] = replies
    // As in the phone's original reply UI, only the outgoing response quotes its parent.
    if message.outgoing, let parent {
      row["parentID"] = parent.id
      row["parentText"] = parent.summary
      row["parentAuthor"] = parent.author
      row["parentOutgoing"] = parent.outgoing
    }
    return row
  }

  /// Resolve an app-authored occurrence in this chat. Never accept arbitrary digests/URLs
  /// from the view as permission to request an image from a phone session.
  static func attachment(_ id: String, in turns: [NessaTurn]) -> NessaStoredAttachment? {
    guard let split = id.range(of: ":image:", options: .backwards),
      let index = Int(id[split.upperBound...]), index >= 0,
      let images = turns.first(where: { $0.id == id[..<split.lowerBound] })?.attachments,
      images.indices.contains(index) else { return nil }
    return images[index]
  }
}
