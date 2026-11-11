import Foundation
import Testing
@testable import NessaFeatures

struct HomeFirstMessageTests {
  @Test func creationClearsOnlySubmittedContent() {
    let original = DraftAttachment(name: "first", mimeType: "text/plain", data: Data())
    let added = DraftAttachment(name: "next", mimeType: "text/plain", data: Data())
    let first = HomeFirstMessage(text: "hello", attachments: [original])
    var draft = "hello again"
    var attachments = [original, added]
    first.consume(from: &draft, attachments: &attachments)
    #expect(draft == "hello again")
    #expect(attachments == [added])
    draft = "hello"
    first.consume(from: &draft, attachments: &attachments)
    #expect(draft.isEmpty)
    #expect(attachments == [added])
  }
}
