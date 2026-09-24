//
//  Currency_TrackerUITests.swift
//  Currency TrackerUITests
//
//  Created by Thomas Tao on 4/10/26.
//

import XCTest

final class Currency_TrackerUITests: XCTestCase {

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
    func testSettingsWindowStartsBlankWithEmptyAPIState() throws {
        let app = XCUIApplication()
        let suiteName = "CurrencyTrackerUITests.\(UUID().uuidString)"
        app.launchArguments.append("-CurrencyTrackerUITestShowSettings")
        app.launchEnvironment["CURRENCY_TRACKER_DEFAULTS_SUITE"] = suiteName
        app.launchEnvironment["CURRENCY_TRACKER_RESET_DEFAULTS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_UI_TEST_SHOW_SETTINGS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_TEST_DATA_DIR"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurrencyTrackerUITests-\(UUID().uuidString)").path
        app.launch()

        XCTAssertTrue(app.buttons["settings.sidebar.rates"].waitForExistence(timeout: 5))
        app.buttons["settings.sidebar.rates"].click()
        XCTAssertTrue(app.staticTexts["settings.empty-pairs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["settings.currency-search"].waitForExistence(timeout: 5))

        app.buttons["settings.sidebar.dataSources"].click()
        XCTAssertTrue(app.buttons["settings.api.twelveData.primary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.api.openExchangeRates.primary"].waitForExistence(timeout: 5))

        app.buttons["settings.sidebar.updates"].click()
        XCTAssertTrue(app.buttons["settings.updates.check"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        let suiteName = "CurrencyTrackerUITests.\(UUID().uuidString)"
        app.launchEnvironment["CURRENCY_TRACKER_DEFAULTS_SUITE"] = suiteName
        app.launchEnvironment["CURRENCY_TRACKER_RESET_DEFAULTS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_TEST_DATA_DIR"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurrencyTrackerUITests-\(UUID().uuidString)").path
        app.launch()
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        app.terminate()
    }

    @MainActor
    func testAllSupportedLanguageSettingsScreenshots() throws {
        let languages = ["zh-Hans", "zh-Hant", "en", "ru", "ja", "ko", "de", "fr", "es", "it", "pt-BR"]
        for language in languages {
            let app = XCUIApplication()
            let suiteName = "CurrencyTrackerUITests.\(UUID().uuidString)"
            app.launchArguments += ["-AppleLanguages", "(\(language))", "-CurrencyTrackerUITestShowSettings"]
            app.launchEnvironment["CURRENCY_TRACKER_DEFAULTS_SUITE"] = suiteName
            app.launchEnvironment["CURRENCY_TRACKER_RESET_DEFAULTS"] = "1"
            app.launchEnvironment["CURRENCY_TRACKER_UI_TEST_SHOW_SETTINGS"] = "1"
            app.launchEnvironment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] = "1"
            app.launchEnvironment["CURRENCY_TRACKER_TEST_DATA_DIR"] = FileManager.default.temporaryDirectory
                .appendingPathComponent("CurrencyTrackerUITests-\(UUID().uuidString)").path
            app.launch()
            XCTAssertTrue(app.buttons["settings.sidebar.backup"].waitForExistence(timeout: 8), "Missing backup section in \(language)")
            app.buttons["settings.sidebar.backup"].click()
            XCTAssertTrue(app.buttons["settings.backup.export"].waitForExistence(timeout: 5))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "settings-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

}
