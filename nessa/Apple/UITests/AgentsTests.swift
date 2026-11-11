import XCTest

final class AgentsTests: XCTestCase {
  private let waitingChat = "00000000-0000-4000-8000-000000000002"

  func testFiltersConfirmationAndOfferedReviewAnswer() {
    let app = XCUIApplication()
    app.launch()
    let menu = app.buttons["open-sidebar"]
    XCTAssertTrue(menu.waitForExistence(timeout: 15))
    menu.tap()
    app.buttons["agents"].tap()

    let earlier = app.descendants(matching: .any)["filter-earlier"].firstMatch
    XCTAssertTrue(earlier.waitForExistence(timeout: 10))
    earlier.tap()
    let request = app.descendants(matching: .any)["request-\(waitingChat)"].firstMatch
    XCTAssertFalse(request.exists)
    let chat = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat-")).firstMatch
    XCTAssertTrue(chat.waitForExistence(timeout: 5))
    let chatID = chat.identifier
    let conversationID = String(chatID.dropFirst("chat-".count))
    chat.swipeLeft()
    let archive = app.buttons["archive-\(conversationID)"]
    XCTAssertTrue(archive.waitForExistence(timeout: 5))
    archive.tap()
    let alert = app.alerts["Archive this chat?"]
    XCTAssertTrue(alert.waitForExistence(timeout: 5))
    alert.buttons["Cancel"].tap()
    XCTAssertTrue(app.buttons[chatID].waitForExistence(timeout: 5))

    let needsYou = app.descendants(matching: .any)["filter-needsYou"].firstMatch
    XCTAssertTrue(needsYou.waitForExistence(timeout: 5))
    needsYou.tap()
    let deny = app.buttons["answer-\(waitingChat)-reject"]
    XCTAssertTrue(deny.waitForExistence(timeout: 5))
    XCTAssertEqual(deny.label, "Deny")
    let allow = app.buttons["answer-\(waitingChat)-allow_once"]
    XCTAssertTrue(allow.exists)
    XCTAssertEqual(allow.label, "Allow once")
    deny.tap()
    let answered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: deny)
    XCTAssertEqual(XCTWaiter.wait(for: [answered], timeout: 5), .completed)
  }
}
