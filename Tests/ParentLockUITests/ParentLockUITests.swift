//
//  ParentLockUITests.swift
//  Basic UI smoke tests. Face ID prompts are bypassed in the simulator via
//  Features ▸ Face ID ▸ Matching Face.
//

import XCTest

final class ParentLockUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingAppearsOnFirstLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to ParentLock"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDashboardShowsCards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        // After simulated Face ID match, the dashboard cards should exist.
        XCTAssertTrue(app.staticTexts["ParentLock"].waitForExistence(timeout: 10))
    }
}
