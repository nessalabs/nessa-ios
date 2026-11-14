import Testing
@testable import NessaFeatures

struct ExactReactionActionTests {
  @Test func paletteAcceptsComposedEmojiAndRejectsStaleScopes() {
    #expect(ExactReactionAction.glyph("7:❤️", scope: 7) == "❤️")
    #expect(ExactReactionAction.glyph("7:🫶", scope: 7) == "🫶")
    #expect(ExactReactionAction.glyph("7:❤️", scope: 8) == nil)
    #expect(ExactReactionAction.glyph("7:👍👍", scope: 7) == nil)
    #expect(ExactReactionAction.glyph("7:", scope: 7) == nil)
  }
}
