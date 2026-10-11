import Foundation
import Testing

@testable import NessaFeatures

@Test func filePreviewBoundsLargeContentsWithoutChangingOriginal() {
  let original = Data(repeating: 65, count: FileTextPreview.maximumBytes * 4)
  let preview = FileTextPreview.prepare(original)
  #expect(preview?.text.utf8.count == FileTextPreview.maximumBytes)
  #expect(preview?.truncated == true)
  #expect(original.count == FileTextPreview.maximumBytes * 4)
}

@Test func filePreviewPreservesUTF8AtTruncationBoundary() {
  let text = String(repeating: "a", count: FileTextPreview.maximumBytes - 1) + "💗end"
  let preview = FileTextPreview.prepare(Data(text.utf8))
  #expect(preview?.text == String(repeating: "a", count: FileTextPreview.maximumBytes - 1))
  #expect(preview?.truncated == true)
}

@Test func filePreviewHandlesSmallAndInvalidFiles() {
  let preview = FileTextPreview.prepare(Data("Hello 💗".utf8))
  #expect(preview?.text == "Hello 💗")
  #expect(preview?.truncated == false)
  #expect(FileTextPreview.prepare(Data([0xFF])) == nil)
}
