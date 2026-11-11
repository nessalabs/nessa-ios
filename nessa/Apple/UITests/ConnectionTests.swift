import XCTest

final class ConnectionTests: XCTestCase {
  func testDevelopmentConnectionCanDisconnect() {
    let app = XCUIApplication()
    app.launch()
    let menu = app.buttons["open-sidebar"]
    XCTAssertTrue(menu.waitForExistence(timeout: 15))
    menu.tap()
    app.buttons["settings"].tap()
    let connection = app.descendants(matching: .any)["connection"].firstMatch
    XCTAssertTrue(connection.waitForExistence(timeout: 5))
    connection.tap()
    let disconnect = app.buttons["link-disconnect"]
    XCTAssertTrue(disconnect.waitForExistence(timeout: 8))
    disconnect.tap()
    let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: disconnect)
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed)
  }

  func testCredentialStaysInSecureFieldAndClearsWhenLeaving() throws {
    let app = XCUIApplication()
    app.launchEnvironment["NESSA_MODE"] = "live"
    app.launch()
    let settings = app.buttons["settings"]
    let menu = app.buttons["open-sidebar"]
    XCTAssertTrue(menu.waitForExistence(timeout: 15))
    menu.tap()
    settings.tap()
    let connection = app.descendants(matching: .any)["connection"].firstMatch
    XCTAssertTrue(connection.waitForExistence(timeout: 5))
    connection.tap()

    let credential = app.secureTextFields["gateway-credential"]
    XCTAssertTrue(credential.waitForExistence(timeout: 5))
    let connect = app.buttons["link-connect"]
    XCTAssertFalse(connect.isEnabled)
    credential.tap()
    credential.typeText("simulator-only")
    let enabled = NSPredicate(format: "enabled == true")
    let ready = XCTNSPredicateExpectation(predicate: enabled, object: connect)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    XCTAssertFalse(app.staticTexts["simulator-only"].exists)

    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(connection.waitForExistence(timeout: 5))
    connection.tap()
    XCTAssertTrue(credential.waitForExistence(timeout: 5))
    XCTAssertFalse(connect.isEnabled)
  }
}
