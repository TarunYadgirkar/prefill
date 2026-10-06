import XCTest

// Leaves a search: iOS 26 draws a close button where earlier versions had Cancel.
@MainActor
func closeSearch(_ app: XCUIApplication) {
    let close = app.buttons["Close"].firstMatch
    (close.exists ? close : app.buttons["Cancel"].firstMatch).tap()
}
