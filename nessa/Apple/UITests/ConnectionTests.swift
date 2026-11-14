import XCTest

final class ConnectionTests: XCTestCase {
  func testLeavingPairingClearsThePrivateCode() {
    let app = XCUIApplication()
    app.launchEnvironment["NESSA_MODE"] = "live"
    app.launch()
    let pair = app.buttons["home-pair"]
    XCTAssertTrue(pair.waitForExistence(timeout: 15))
    pair.tap()
    let field = app.textFields["pair-code"]
    XCTAssertTrue(field.waitForExistence(timeout: 8))
    field.tap()
    field.typeText("ABCD2345")
    let submit = app.buttons["pair-submit"]
    let enabled = expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: submit)
    wait(for: [enabled], timeout: 5)
    app.buttons["pair-close"].tap()
    XCTAssertTrue(pair.waitForExistence(timeout: 8))
    pair.tap()
    XCTAssertTrue(field.waitForExistence(timeout: 8))
    XCTAssertFalse(submit.isEnabled)
    XCTAssertNotEqual(field.value as? String, "ABCD2345")
  }

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
    // AutoFill can arrive after Settings is already hittable on a cold simulator.
    // Follow the same two visible controls a person uses until the form reappears.
    let away = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: credential)
    XCTAssertEqual(XCTWaiter.wait(for: [away], timeout: 10), .completed)
    let declineSave = app.buttons["Not Now"]
    let deadline = Date().addingTimeInterval(40)
    while !credential.exists && Date() < deadline {
      let actionable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        declineSave.isHittable || connection.isHittable || credential.exists
      }, object: nil)
      guard XCTWaiter.wait(for: [actionable], timeout: max(0, deadline.timeIntervalSinceNow)) == .completed
      else { break }
      if declineSave.isHittable {
        declineSave.tap()
      } else if !credential.exists && connection.isHittable {
        connection.tap()
        _ = credential.waitForExistence(timeout: 2)
      }
    }
    XCTAssertTrue(credential.exists)
    XCTAssertFalse(connect.isEnabled)
  }
}
