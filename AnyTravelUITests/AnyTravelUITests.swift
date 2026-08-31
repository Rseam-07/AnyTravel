import XCTest

final class AnyTravelUITests: XCTestCase {
    func testWelcomeScreenHasAUsableStartingPoint() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.textFields["输入城市、区域或目的地"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["苏州"].isHittable)
        XCTAssertTrue(app.buttons["在地图上定位"].exists)
    }

    func testCanSaveTripAndSeeItInLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-ready"]
        app.launch()

        let saveButton = app.buttons["保存"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.isHittable)
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["行程已保存在这台设备上。"].waitForExistence(timeout: 3))

        let libraryButton = app.buttons["已保存行程"]
        XCTAssertTrue(libraryButton.isHittable)
        libraryButton.tap()

        XCTAssertTrue(app.navigationBars["已保存行程"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["苏州市 · 1天"].waitForExistence(timeout: 3))
    }
}
