import XCTest

final class ReactionTests: XCTestCase {
  func testHeldTextCanBeReactedToRemovedAndRepliedTo() {
    let app = XCUIApplication()
    app.launch()
    let sidebar = app.buttons["open-sidebar"]
    XCTAssertTrue(sidebar.waitForExistence(timeout: 15))
    sidebar.tap()
    app.buttons["agents"].tap()
    let chatID = "00000000-0000-4000-8000-000000000001"
    let chat = app.buttons["chat-" + chatID]
    XCTAssertTrue(chat.waitForExistence(timeout: 10))
    chat.tap()

    let selected = app.descendants(matching: .any)["message-actions-\(chatID)-7:user"].firstMatch
    XCTAssertTrue(selected.waitForExistence(timeout: 10))
    selected.press(forDuration: 0.8)
    XCTAssertTrue(app.buttons["reaction-copy"].waitForExistence(timeout: 5))
    app.buttons["reaction-picker"].tap()
    let rocket = app.descendants(matching: .any)["reaction-🚀"].firstMatch
    XCTAssertTrue(rocket.waitForExistence(timeout: 5))
    rocket.tap()

    selected.press(forDuration: 0.8)
    app.buttons["reaction-more"].tap()
    XCTAssertTrue(app.buttons["reaction-share"].exists)
    app.buttons["reaction-remove"].tap()

    selected.press(forDuration: 0.8)
    app.buttons["reaction-reply"].tap()
    XCTAssertTrue(app.buttons["thread-back"].waitForExistence(timeout: 5))
    let closeReplies = NSPredicate(format: "label == %@", "Close replies")
    let changed = expectation(for: closeReplies, evaluatedWith: app.buttons["thread-back"])
    wait(for: [changed], timeout: 5)
  }
}
