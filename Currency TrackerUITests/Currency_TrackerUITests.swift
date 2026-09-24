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
            if language != "zh-Hans" {
                XCTAssertFalse(app.staticTexts["先了解接下来要开启哪些能力"].exists, "Untranslated welcome subtitle in \(language)")
                XCTAssertFalse(app.staticTexts["用于全局快捷键读取选中文本。"].exists, "Untranslated permission detail in \(language)")
                XCTAssertFalse(app.buttons["下一步"].exists, "Untranslated welcome button in \(language)")
            }
            app.buttons["settings.sidebar.backup"].click()
            XCTAssertTrue(app.buttons["settings.backup.export"].waitForExistence(timeout: 5))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "settings-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    @MainActor
    func testSettingsNavigationScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-CurrencyTrackerUITestShowSettings"]
        app.launchEnvironment["CURRENCY_TRACKER_DEFAULTS_SUITE"] = "CurrencyTrackerUITests.\(UUID().uuidString)"
        app.launchEnvironment["CURRENCY_TRACKER_RESET_DEFAULTS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_UI_TEST_SHOW_SETTINGS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_TEST_DATA_DIR"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurrencyTrackerUITests-\(UUID().uuidString)").path
        app.launch()

        let sections = ["general", "language", "rates", "profiles", "backup", "alerts",
                        "refresh", "dataSources", "permissions", "updates", "diagnostics", "system"]
        for section in sections {
            let button = app.buttons["settings.sidebar.\(section)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing \(section) section")
            button.click()
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "settings-flow-\(section)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testConverterSwitchesCurrenciesWithBlankEditableInput() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)"]
        app.launchEnvironment["CURRENCY_TRACKER_DEFAULTS_SUITE"] = "CurrencyTrackerUITests.\(UUID().uuidString)"
        app.launchEnvironment["CURRENCY_TRACKER_RESET_DEFAULTS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_UI_TEST_SHOW_PANEL"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_TEST_DATA_DIR"] = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurrencyTrackerUITests-\(UUID().uuidString)").path
        app.launch()

        let toggle = app.buttons["panel.toggleConverter"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        XCTAssertTrue(toggle.isEnabled)
        toggle.click()
        let openedScreenshot = XCTAttachment(screenshot: app.screenshot())
        openedScreenshot.name = "converter-after-toggle"
        openedScreenshot.lifetime = .keepAlways
        add(openedScreenshot)
        let usd = app.staticTexts["converter.result.USD"]
        XCTAssertTrue(usd.waitForExistence(timeout: 5), app.debugDescription)
        let defaultScreenshot = XCTAttachment(screenshot: app.screenshot())
        defaultScreenshot.name = "converter-default-base"
        defaultScreenshot.lifetime = .keepAlways
        add(defaultScreenshot)

        let yuanRow = app.staticTexts["CNY"]
        XCTAssertTrue(yuanRow.waitForExistence(timeout: 5))
        yuanRow.click()
        let yuanInput = app.textFields["converter.input.CNY"]
        XCTAssertTrue(yuanInput.waitForExistence(timeout: 5))
        let exampleResult = usd.label
        yuanInput.click()
        yuanInput.typeText("35")
        XCTAssertEqual(yuanInput.value as? String, "35")
        XCTAssertNotEqual(usd.label, exampleResult)
        let editedScreenshot = XCTAttachment(screenshot: app.screenshot())
        editedScreenshot.name = "converter-yuan-input"
        editedScreenshot.lifetime = .keepAlways
        add(editedScreenshot)
    }

}
