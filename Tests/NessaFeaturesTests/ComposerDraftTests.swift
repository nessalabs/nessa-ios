import Foundation
import Testing

@testable import NessaFeatures

@Test @MainActor func acceptanceClearsOnlyTheCapturedDraftAndRetainsReplyThread() {
  let draft = ComposerDraftViewModel()
  draft.text = "Original"
  draft.attachments = [.init(name: "photo.png", mimeType: "image/png", data: Data([1]))]
  draft.reply = .init(id: "parent", author: "Agent", text: "Parent")
  let attempt = draft.begin(scope: 1)
  draft.retainPending([])  // A refresh before the active send finishes must not drop ownership.
  draft.accept([attempt.identity.requestID], scope: 1)
  #expect(draft.text.isEmpty)
  #expect(draft.attachments.isEmpty)
  #expect(draft.reply?.id == "parent")
}

@Test @MainActor func identicalRetypedTextIsANewDraftAfterUncertainDelivery() {
  let draft = ComposerDraftViewModel()
  draft.text = "Same text"
  let original = draft.begin(scope: 1)
  draft.finished(original.identity.requestID, keepPending: true)
  draft.text = ""
  draft.text = "Same text"
  draft.accept([original.identity.requestID], scope: 1)
  #expect(draft.text == "Same text")
  let replacement = draft.begin(scope: 1)
  #expect(replacement.identity != original.identity)
  draft.accept([replacement.identity.requestID], scope: 1)
  #expect(draft.text.isEmpty)
}

@Test @MainActor func changedAttachmentOrReplySurvivesOldAcceptance() {
  let draft = ComposerDraftViewModel()
  draft.text = "Caption"
  let original = draft.begin(scope: 1)
  let photo = DraftAttachment(name: "new.png", mimeType: "image/png", data: Data([2]))
  draft.attachments = [photo]
  draft.accept([original.identity.requestID], scope: 1)
  #expect(draft.text == "Caption")
  #expect(draft.attachments == [photo])
  let second = draft.begin(scope: 1)
  draft.reply = .init(id: "different", author: "Agent", text: "Different parent")
  draft.accept([second.identity.requestID], scope: 1)
  #expect(draft.text == "Caption")
  #expect(draft.reply?.id == "different")
}

@Test @MainActor func oldScopeConfirmationCannotClearNewScopeDraft() {
  let draft = ComposerDraftViewModel()
  draft.text = "Private draft"
  let original = draft.begin(scope: 1)
  draft.accept([original.identity.requestID], scope: 2)
  #expect(draft.text == "Private draft")
  draft.finished(original.identity.requestID, keepPending: false)
  draft.accept([original.identity.requestID], scope: 1)
  #expect(draft.text == "Private draft")
}
