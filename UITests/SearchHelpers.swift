import XCTest

// Types into the You tab's search, pulling the list down first: the field hides under the
// title once the list has scrolled.
@MainActor
func search(_ app: XCUIApplication, for text: String) {
    let field = app.searchFields.firstMatch
    for _ in 0..<4 where !(field.exists && field.isHittable) {
        app.swipeDown()
    }
    XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field")
    field.tap()
    field.typeText(text)
}

// Leaves a search: iOS 26 draws a close button where earlier versions had Cancel.
@MainActor
func closeSearch(_ app: XCUIApplication) {
    let close = app.buttons["Close"].firstMatch
    (close.exists ? close : app.buttons["Cancel"].firstMatch).tap()
}
