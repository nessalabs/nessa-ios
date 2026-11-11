import XCTest

final class PhoneNavigationTests: XCTestCase {
  func testHomeSettingsArchiveAndBack() {
    let app = XCUIApplication()
    app.launch()
    let menu = app.buttons["Open sidebar"]
    XCTAssertTrue(menu.waitForExistence(timeout: 15))
    menu.tap()
    app.buttons["Settings"].tap()
    app.descendants(matching: .any)["Archived chats"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["No archived chats."].waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.descendants(matching: .any)["Connection"].firstMatch.waitForExistence(timeout: 5))
  }
}
