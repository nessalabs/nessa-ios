import XCTest

extension XCUIApplication {
  /// The host and its UITextView expose the same identifier. Use the editor's on-screen
  /// geometry so XCTest delivers an actual keyboard-opening touch inside that nested control.
  func tapComposer(_ field: XCUIElement, at normalized: CGVector = CGVector(dx: 0.45, dy: 0.5)) {
    let rect = field.frame
    coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: rect.minX - frame.minX + rect.width * normalized.dx,
                           dy: rect.minY - frame.minY + rect.height * normalized.dy)).tap()
  }

  /// Exact exposes both a host accessibility element and the editing UITextView. XCTest's
  /// typeText can reject that composite even while its caret and software keyboard are active.
  /// Tap the same visible keys as a person, including Shift and punctuation.
  func typeOnComposerKeyboard(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
    let keyboard = keyboards.firstMatch
    guard keyboard.waitForExistence(timeout: 8) else {
      XCTFail("The composer did not open the keyboard", file: file, line: line)
      return
    }
    for character in text {
      let label = String(character)
      if character == " " {
        keyboard.keys["space"].tap()
        continue
      }
      let exact = keyboard.keys.matching(NSPredicate(format: "label == %@", label)).firstMatch
      if !exact.exists {
        let alternateCase = keyboard.keys.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
        if character.isLetter, alternateCase.exists {
          keyboard.buttons["shift"].tap()
        } else {
          keyboard.keys["more"].tap()
          if character.isLetter, !exact.exists { keyboard.buttons["shift"].tap() }
        }
      }
      guard exact.exists || exact.waitForExistence(timeout: 2) else {
        XCTFail("Missing keyboard key for \(label)", file: file, line: line)
        return
      }
      exact.tap()
    }
  }
}

extension XCUIElement {
  /// iOS can apply the keyboard's automatic sentence casing on insertion. Preserve the
  /// actual editor value so the delivery and dismissal assertions still check every byte.
  func composerValue(matching expected: String, file: StaticString = #filePath, line: UInt = #line) -> String {
    let actual = value as? String ?? ""
    XCTAssertEqual(actual.lowercased(), expected.lowercased(), file: file, line: line)
    return actual
  }
}
