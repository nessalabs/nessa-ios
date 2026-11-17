import Foundation
import Testing
@testable import NessaFeatures

struct ConversationHistoryNoticeTests {
  private func fixture(earlier: Bool?, truncated: Bool = false) throws -> Data {
    // The gateway supplies only the latest 24 turns of a 200-turn conversation.
    let messages: [[String: Any]] = (177...200).map { index in
      var turn: [String: Any] = ["executionId": "turn-\(index)", "userText": "Question \(index)",
        "status": "completed", "parts": [["offset": 0, "kind": "text", "text": "Answer \(index)"]]]
      if index == 177 { turn["startsAt"] = ["part": 0, "byte": 12] }
      return turn
    }
    var view: [String: Any] = ["conversationId": "long-chat", "messages": messages,
      "permissions": [], "truncated": truncated]
    if let earlier { view["earlier"] = earlier }
    return try JSONSerialization.data(withJSONObject: view)
  }

  @Test func longChatWarnsWhenOlderTurnsAreAvailableButNotLoaded() throws {
    let view = try JSONDecoder().decode(NessaConversationView.self, from: fixture(earlier: true))
    #expect(view.messages.count == 24)
    #expect(view.messages.first?.executionId == "turn-177")
    #expect(view.messages.last?.executionId == "turn-200")
    #expect(!view.truncated)
    #expect(view.earlier)
    #expect(view.hasUndisplayedContent)
    // Retained history must preserve the warning when the phone is offline.
    let retained = try JSONDecoder().decode(NessaConversationView.self, from: JSONEncoder().encode(view))
    #expect(retained.earlier)
    #expect(retained.hasUndisplayedContent)
    #expect(retained.messages == view.messages)
  }

  @Test func completeAndLegacyViewsDoNotWarn() throws {
    for earlier: Bool? in [nil, false] {
      let view = try JSONDecoder().decode(NessaConversationView.self, from: fixture(earlier: earlier))
      #expect(!view.earlier)
      #expect(!view.hasUndisplayedContent)
    }
  }

  @Test func locallyCreatedViewsDefaultToCompleteHistory() {
    let view = NessaConversationView(conversationId: "new-chat", messages: [], permissions: [],
      truncated: false, interactionViewError: nil, runtime: nil)
    #expect(!view.earlier)
    #expect(!view.hasUndisplayedContent)
  }

  @Test func irrecoverablyTruncatedViewsStillWarn() throws {
    let view = try JSONDecoder().decode(NessaConversationView.self, from: fixture(earlier: false, truncated: true))
    #expect(!view.earlier)
    #expect(view.hasUndisplayedContent)
  }
}
