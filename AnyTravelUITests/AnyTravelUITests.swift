import XCTest

@MainActor
final class AnyTravelUITests: XCTestCase {
    func testWelcomeScreenHasAUsableStartingPoint() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding"]
        app.launch()

        XCTAssertTrue(app.textFields["输入城市、区域或目的地"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["苏州"].isHittable)
        XCTAssertTrue(app.buttons["在地图上唤醒目的地"].exists)
    }

    func testFirstLaunchExplainsTheFlowAndReachesInitialSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--force-onboarding"]
        app.launch()

        let openingTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "让每一次选择")
        ).firstMatch
        XCTAssertTrue(openingTitle.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            let continueButton = app.buttons["继续"]
            XCTAssertTrue(continueButton.isHittable)
            continueButton.tap()
        }

        XCTAssertTrue(app.staticTexts["出发前，先留下几句偏好"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["携程, 登录"].exists || app.staticTexts["携程"].exists)
        let startButton = app.buttons["开始规划"]
        XCTAssertTrue(startButton.isHittable)
        startButton.tap()
        XCTAssertTrue(app.textFields["输入城市、区域或目的地"].waitForExistence(timeout: 3))
    }

    func testCanSaveTripAndSeeItInLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-ready"]
        app.launch()

        let saveButton = app.buttons["保存"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.isHittable)
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["这段旅程已收进本机旅册。"].waitForExistence(timeout: 3))

        let libraryButton = app.buttons["已保存行程"]
        XCTAssertTrue(libraryButton.isHittable)
        libraryButton.tap()

        XCTAssertTrue(app.navigationBars["我的旅册"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["苏州市 · 3天"].waitForExistence(timeout: 3))
    }

    func testCompletePlanTabsExposeStayTransportAndExpenseDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-ready"]
        app.launch()

        let accommodationTab = app.buttons["住宿"]
        XCTAssertTrue(accommodationTab.waitForExistence(timeout: 5))
        accommodationTab.tap()
        XCTAssertTrue(app.staticTexts["住宿比价 · 1个候选"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["¥468/晚"].exists)
        XCTAssertTrue(app.staticTexts["演示价"].exists)

        app.buttons["交通"].tap()
        XCTAssertTrue(app.staticTexts["高铁抵达苏州"].waitForExistence(timeout: 3))
        let transferReason = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "苏州站到住宿约4.6公里")
        ).firstMatch
        XCTAssertTrue(transferReason.exists)

        app.buttons["费用"].tap()
        XCTAssertTrue(app.staticTexts["完整费用 · 2人"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["往返大交通"].exists)
        XCTAssertTrue(app.staticTexts["机动金"].exists)
    }
}
