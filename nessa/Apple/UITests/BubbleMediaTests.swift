import XCTest

final class BubbleMediaTests: XCTestCase {
  func testStoredPhotoInDetailsOpensDecodedGalleryAndReturnsToTranscript() {
    let app = XCUIApplication()
    app.launch()
    let menu = app.buttons["open-sidebar"]
    XCTAssertTrue(menu.waitForExistence(timeout: 15))
    menu.tap()
    app.buttons["agents"].tap()
    let chatID = "00000000-0000-4000-8000-000000000001"
    let chat = app.buttons["chat-" + chatID]
    XCTAssertTrue(chat.waitForExistence(timeout: 15))
    chat.tap()

    let details = app.descendants(matching: .any)["thread-details"].firstMatch
    XCTAssertTrue(details.waitForExistence(timeout: 10))
    details.tap()
    let tab = app.descendants(matching: .any)["details-tab-Artifacts"].firstMatch
    XCTAssertTrue(tab.waitForExistence(timeout: 10))
    tab.tap()
    let artifact = chatID + "-0:image:0"
    let tile = app.buttons["open-photo-artifact-" + artifact]
    XCTAssertTrue(tile.waitForExistence(timeout: 10))
    let rendered = app.descendants(matching: .any)["photo-ready-" + artifact].firstMatch
    XCTAssertTrue(rendered.waitForExistence(timeout: 10))
    tile.tap()
    let done = app.buttons["done-artifact-" + artifact]
    XCTAssertTrue(done.waitForExistence(timeout: 8))
    XCTAssertTrue(app.descendants(matching: .any)["photo-ready-" + artifact].firstMatch.waitForExistence(timeout: 8))
    done.tap()
    XCTAssertTrue(tile.waitForExistence(timeout: 5))
    app.buttons["details-close"].tap()
    XCTAssertTrue(details.waitForExistence(timeout: 5))
  }
}
