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

    func testBusyTripCanBecomeRelaxedWithoutReplacingItsStops() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--ui-test-ready", "--ui-test-busy"]
        app.launch()

        XCTAssertTrue(app.staticTexts["这段行程有点赶"].waitForExistence(timeout: 5))
        let relaxButton = app.buttons["relax-plan-action"]
        XCTAssertTrue(relaxButton.isHittable)
        relaxButton.tap()

        XCTAssertTrue(app.staticTexts["relaxed-plan-success"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["第 4 天"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["苏州博物馆"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "忙碌行程一键铺松"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAssistantSettingsExposeManagedAndSecureCustomModes() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--ui-test-ready", "--ui-test-settings"]
        app.launch()

        XCTAssertTrue(app.navigationBars["旅途偏好与价格渠道"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["旅途里的智能向导"].exists)
        let managedModel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "GLM-5.3-Flash")
        ).firstMatch
        XCTAssertTrue(managedModel.waitForExistence(timeout: 2))

        let providerPicker = app.segmentedControls["assistant-provider-picker"]
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 2))
        let customMode = providerPicker.buttons["自定义服务"]
        XCTAssertTrue(customMode.waitForExistence(timeout: 2))
        customMode.tap()

        XCTAssertTrue(app.textFields["assistant-custom-base-url"].waitForExistence(timeout: 2))
        let customModel = app.textFields["assistant-custom-model"]
        for _ in 0..<2 where !customModel.exists { app.swipeUp() }
        XCTAssertTrue(customModel.waitForExistence(timeout: 3))
        let customAPIKey = app.secureTextFields["assistant-custom-api-key"]
        for _ in 0..<2 where !customAPIKey.exists { app.swipeUp() }
        XCTAssertTrue(customAPIKey.waitForExistence(timeout: 3))

        let tongcheng = app.staticTexts["同程旅行"]
        for _ in 0..<4 where !tongcheng.exists { app.swipeUp() }
        XCTAssertTrue(tongcheng.waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "智能向导与平台登录设置"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCompletePlanTabsExposeStayTransportAndExpenseDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-ready"]
        app.launch()

        let rationale = app.descendants(matching: .any)["planning-rationale"]
        XCTAssertTrue(rationale.waitForExistence(timeout: 5))
        XCTAssertTrue(rationale.label.contains("这一天为何这样展开"))

        let accommodationTab = app.buttons["住宿"]
        XCTAssertTrue(accommodationTab.waitForExistence(timeout: 5))
        let exportMenu = app.buttons["plan-export-menu"]
        XCTAssertTrue(exportMenu.exists)
        XCTAssertTrue(exportMenu.isHittable)
        exportMenu.tap()
        XCTAssertTrue(app.buttons["分享完整 PDF"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["导出日历文件"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.08)).tap()
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
        let arrivalTaxi = app.buttons["local-transfer-outbound-taxi"]
        XCTAssertTrue(arrivalTaxi.waitForExistence(timeout: 3))
        XCTAssertTrue(arrivalTaxi.isHittable)
        arrivalTaxi.tap()
        XCTAssertTrue(arrivalTaxi.isSelected)

        let returnSegment = app.segmentedControls["transport-direction-picker"].buttons["返程"]
        XCTAssertTrue(returnSegment.waitForExistence(timeout: 3))
        XCTAssertTrue(returnSegment.isHittable)
        returnSegment.tap()
        XCTAssertTrue(app.staticTexts["G7028 · 苏州→上海"].waitForExistence(timeout: 3))
        let returnTransferReason = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "住宿到苏州站约4.6公里")
        ).firstMatch
        XCTAssertTrue(returnTransferReason.exists)
        let returnMetro = app.buttons["local-transfer-return-publicTransit"]
        XCTAssertTrue(returnMetro.waitForExistence(timeout: 3))
        XCTAssertTrue(returnMetro.isSelected)
        XCTAssertTrue(app.staticTexts["验收样例"].exists)
        let returnScreenshot = XCTAttachment(screenshot: app.screenshot())
        returnScreenshot.name = "门到门接驳选择"
        returnScreenshot.lifetime = .keepAlways
        add(returnScreenshot)

        app.buttons["费用"].tap()
        XCTAssertTrue(app.staticTexts["完整费用 · 2人"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["去程大交通"].exists)
        XCTAssertTrue(app.staticTexts["返程大交通"].exists)
        XCTAssertTrue(app.staticTexts["抵达接驳"].exists)
        XCTAssertTrue(app.staticTexts["返程接驳"].exists)
        XCTAssertTrue(app.staticTexts["机动金"].exists)
    }

    func testCompletePlanExportsPDFToSystemShareSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-ready"]
        app.launch()

        let exportMenu = app.buttons["plan-export-menu"]
        XCTAssertTrue(exportMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(exportMenu.isHittable)
        exportMenu.tap()

        let exportPDF = app.buttons["分享完整 PDF"]
        XCTAssertTrue(exportPDF.waitForExistence(timeout: 2))
        exportPDF.tap()

        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 12))
        XCTAssertTrue(app.cells["保存到“文件”"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "完整方案 PDF 系统分享"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testGeneratedTripCanBeEditedWithoutStartingOver() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--ui-test-ready"]
        app.launch()

        let adjustButton = app.buttons["调整"]
        XCTAssertTrue(adjustButton.waitForExistence(timeout: 5))
        adjustButton.tap()

        let editRouteButton = app.buttons["增删与调整路线"]
        XCTAssertTrue(editRouteButton.waitForExistence(timeout: 2))
        editRouteButton.tap()

        XCTAssertTrue(app.navigationBars["编排行程"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["拙政园"].exists)
        XCTAssertTrue(app.staticTexts["苏州博物馆"].exists)

        app.buttons["调整拙政园"].tap()
        let removeButton = app.buttons["移出行程"]
        XCTAssertTrue(removeButton.waitForExistence(timeout: 2))
        removeButton.tap()

        XCTAssertFalse(app.staticTexts["拙政园"].exists)
        XCTAssertTrue(app.staticTexts["苏州博物馆"].exists)

        let undoButton = app.buttons["撤销"]
        XCTAssertTrue(undoButton.isHittable)
        undoButton.tap()
        XCTAssertTrue(app.staticTexts["拙政园"].waitForExistence(timeout: 3))

        let redoButton = app.buttons["重做"]
        XCTAssertTrue(redoButton.isHittable)
        redoButton.tap()
        let gardenRemoved = NSPredicate(format: "exists == false")
        expectation(for: gardenRemoved, evaluatedWith: app.staticTexts["拙政园"])
        waitForExpectations(timeout: 3)

        undoButton.tap()
        XCTAssertTrue(app.staticTexts["拙政园"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["完成"].isHittable)
    }

    func testGeneratedTripCanCopyAStopToAnotherDay() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--ui-test-ready"]
        app.launch()

        XCTAssertTrue(app.buttons["调整"].waitForExistence(timeout: 5))
        app.buttons["调整"].tap()
        XCTAssertTrue(app.buttons["增删与调整路线"].waitForExistence(timeout: 2))
        app.buttons["增删与调整路线"].tap()

        XCTAssertTrue(app.navigationBars["编排行程"].waitForExistence(timeout: 3))
        app.buttons["调整拙政园"].tap()
        XCTAssertTrue(app.buttons["复制到另一天"].waitForExistence(timeout: 2))
        app.buttons["复制到另一天"].tap()

        let copyToDayTwo = app.buttons["copy-stop-to-day-1"]
        XCTAssertTrue(copyToDayTwo.waitForExistence(timeout: 2))
        copyToDayTwo.tap()

        let dayTwo = app.buttons["itinerary-day-1"]
        XCTAssertTrue(dayTwo.waitForExistence(timeout: 2))
        dayTwo.tap()
        XCTAssertTrue(app.staticTexts["平江路"].exists)
        XCTAssertTrue(app.staticTexts["拙政园"].waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "跨天复制后的行程编辑器"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testGeneratedTripCanChangeConditionsAndKeepItsPlan() {
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--ui-test-ready"]
        app.launch()

        XCTAssertTrue(app.buttons["调整"].waitForExistence(timeout: 5))
        app.buttons["调整"].tap()
        let conditionsButton = app.buttons["修改日期与出发条件"]
        XCTAssertTrue(conditionsButton.waitForExistence(timeout: 2))
        conditionsButton.tap()

        XCTAssertTrue(app.navigationBars["调整旅行条件"].waitForExistence(timeout: 3))
        let skipAccommodation = app.switches["trip-conditions-skip-accommodation"]
        for _ in 0..<2 where !skipAccommodation.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(skipAccommodation.waitForExistence(timeout: 3))
        XCTAssertTrue(skipAccommodation.isHittable)
        // SwiftUI exposes the entire Form row as the switch element. Tap the
        // visible control on the trailing edge instead of the row's midpoint.
        skipAccommodation.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let switchedOn = NSPredicate(format: "value == %@", "1")
        expectation(for: switchedOn, evaluatedWith: skipAccommodation)
        waitForExpectations(timeout: 2)
        app.buttons["重新计算"].tap()

        let accommodationTab = app.buttons["住宿"]
        XCTAssertTrue(accommodationTab.waitForExistence(timeout: 3))
        accommodationTab.tap()
        XCTAssertTrue(app.staticTexts["已跳过住宿"].waitForExistence(timeout: 3))

        app.buttons["行程"].tap()
        XCTAssertTrue(app.staticTexts["苏州博物馆"].exists)

        app.buttons["调整"].tap()
        let editRouteButton = app.buttons["增删与调整路线"]
        XCTAssertTrue(editRouteButton.waitForExistence(timeout: 2))
        editRouteButton.tap()
        XCTAssertTrue(app.navigationBars["编排行程"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["苏州博物馆"].exists)
        XCTAssertTrue(app.staticTexts["拙政园"].exists)
    }
}
