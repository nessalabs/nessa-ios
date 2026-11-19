import XCTest

final class ThreadFlowTests: XCTestCase {
  func testCreateSendAndInspectAgent() throws {
    let app = XCUIApplication()
    app.launch()
    let create = app.buttons["New chat"].firstMatch
    XCTAssertTrue(create.waitForExistence(timeout: 20))
    let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == YES"), object: create)
    XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
    create.tap()
    let input = app.descendants(matching: .any).matching(NSPredicate(
      format: "elementType == %d OR elementType == %d",
      XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue
    )).firstMatch
    XCTAssertTrue(input.waitForExistence(timeout: 10))
    input.tap()
    let message = "Exact simulator delivery"
    input.typeText(message)
    app.buttons["Send message"].tap()
    XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 15))
    let details = app.descendants(matching: .any)["thread-details"].firstMatch
    XCTAssertTrue(details.waitForExistence(timeout: 5))
    details.tap()
    XCTAssertTrue(app.descendants(matching: .any)["Access granted"].firstMatch.waitForExistence(timeout: 5))
    app.buttons["Close details"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 5))
  }
}
