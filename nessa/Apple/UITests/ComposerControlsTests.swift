import XCTest

/// Exercises the authored controls against the real development store and speech adapter.
final class ComposerControlsTests: XCTestCase {
  func testHomeTextCreatesAndSendsOnceThenDictationCanBeEdited() {
    let app = XCUIApplication()
    app.launch()
    let input = app.descendants(matching: .any)["message-input"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 20))
    let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: input)
    XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
    input.tap()
    let first = "Exact composer first message"
    input.typeText(first)
    app.buttons["Send message"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts[first].firstMatch.waitForExistence(timeout: 15))
    let dictate = app.buttons["Dictate message"].firstMatch
    XCTAssertTrue(dictate.waitForExistence(timeout: 8))
    dictate.tap()
    let transcribed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "This is a mocked voice message."), object: input)
    XCTAssertEqual(XCTWaiter.wait(for: [transcribed], timeout: 10), .completed)
    input.tap()
    input.typeText(" Edited.")
    app.buttons["Send message"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["This is a mocked voice message. Edited."].firstMatch.waitForExistence(timeout: 15))
  }

  func testCameraUnavailableShowsAnAttachmentErrorAndPreservesText() {
    let app = XCUIApplication()
    app.launch()
    let input = app.descendants(matching: .any)["message-input"].firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 20))
    let actions = app.buttons["Message actions"].firstMatch
    let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: actions)
    XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
    input.tap()
    input.typeText("Keep this draft")
    actions.tap()
    let camera = app.descendants(matching: .any)["Camera"].firstMatch
    XCTAssertTrue(camera.waitForExistence(timeout: 5))
    camera.tap()
    XCTAssertTrue(app.descendants(matching: .any)["Camera is unavailable on this device. Choose Photos or Add Files instead."].firstMatch.waitForExistence(timeout: 8))
    app.buttons["OK"].firstMatch.tap()
    XCTAssertEqual(input.value as? String, "Keep this draft")
  }
}
