//
//  SpeekUITests.swift
//  SpeekUITests
//
//  Created by Prakash Joshi on 15/10/2024.
//

import XCTest

final class SpeekUITests: XCTestCase {
    private let appDefaults = UserDefaults(suiteName: "com.aveekpatra.speek")

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testDashboardStatsNavigationShowsOverviewAndDetails() throws {
        appDefaults?.set(true, forKey: "hasCompletedOnboardingV2")
        appDefaults?.set(false, forKey: "enableAnnouncements")
        appDefaults?.synchronize()

        let app = XCUIApplication()
        app.launchArguments = [
            "-hasCompletedOnboardingV2", "YES",
            "-enableAnnouncements", "NO"
        ]
        app.launch()

        let window = app.windows["Speek"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        let sidebarButtons = window.buttons
        XCTAssertGreaterThanOrEqual(sidebarButtons.count, 3)
        sidebarButtons.element(boundBy: 0).click()

        let showsRecentTranscripts = app.staticTexts["Recent transcripts"].waitForExistence(timeout: 5)
        let showsEmptyDashboard = app.staticTexts["No Recorder Sessions Yet"].waitForExistence(timeout: 5)
        XCTAssertTrue(showsRecentTranscripts || showsEmptyDashboard)

        sidebarButtons.element(boundBy: 2).click()

        XCTAssertTrue(app.staticTexts["Estimated productivity gain"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
