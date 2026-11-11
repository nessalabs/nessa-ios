import XCTest

final class NewConversationTests: XCTestCase {
  func testHomeDraftIsSentInTheNewThread() {
    let app = XCUIApplication()
    app.launch()
    sendFirstMessage("Hello from home", in: app)
    app.buttons["thread-back"].tap()
    XCTAssertTrue(app.buttons["open-sidebar"].waitForExistence(timeout: 5))
  }

  func testChannelDraftReturnsToTheSameChannel() {
    let app = XCUIApplication()
    app.launch()
    let menu = app.buttons["open-sidebar"]
    XCTAssertTrue(menu.waitForExistence(timeout: 15))
    menu.tap()
    let travel = app.buttons["channel-ch_bbbbbbbbbb"]
    XCTAssertTrue(travel.waitForExistence(timeout: 10))
    travel.tap()
    sendFirstMessage("Hello from travel", in: app)
    app.buttons["thread-back"].tap()
    XCTAssertTrue(app.navigationBars["travel"].waitForExistence(timeout: 5))
  }

  private func sendFirstMessage(_ message: String, in app: XCUIApplication) {
    let fields = app.descendants(matching: .any).matching(NSPredicate(
      format: "elementType == %d OR elementType == %d",
      XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue))
    let input = fields.firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 15))
    input.tap()
    input.typeText(message)
    let send = app.buttons["Send message"]
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: send)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    send.tap()
    XCTAssertTrue(app.buttons["thread-back"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 10))
  }
}
