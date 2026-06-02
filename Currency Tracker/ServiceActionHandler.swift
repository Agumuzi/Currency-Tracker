//
//  ServiceActionHandler.swift
//  Currency Tracker
//
//  Created by Codex on 4/12/26.
//

import AppKit
import Foundation

@MainActor
final class ServiceActionHandler: NSObject {
    private let coordinator: ConversionCoordinator

    init(coordinator: ConversionCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func register() {
        let portName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Currency Tracker"
        NSApplication.shared.servicesProvider = self
        NSRegisterServicesProvider(self, portName)
        NSUpdateDynamicServices()
    }

    @objc(convertSelectionToBaseCurrency:userData:error:)
    func convertSelectionToBaseCurrency(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let selectedText = pasteboard.string(forType: .string),
              selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            error.pointee = "无法读取选中文本" as NSString
            Task { @MainActor in
                await coordinator.handleSelectedText("", source: .services)
            }
            return
        }

        Task { @MainActor in
            await coordinator.handleSelectedText(selectedText, source: .services)
        }
    }
}

@MainActor
final class InitialLaunchCoordinator {
    enum InitialPresentationAction: Equatable {
        case none
        case automaticUpdateCheck
        case showWelcome
        case showSettings(SettingsSection?)
    }

    private let userDefaults: UserDefaults
    private let preferences: PreferencesStore
    private let settingsWindowController: SettingsWindowController
    private let welcomeWindowController: WelcomeWindowController
    private let automaticUpdateCoordinator: AutomaticSoftwareUpdateCoordinator
    private let isRunningUITests: Bool
    private var observer: NSObjectProtocol?
    private var didHandleInitialPresentation = false

    init(
        userDefaults: UserDefaults,
        preferences: PreferencesStore,
        settingsWindowController: SettingsWindowController,
        welcomeWindowController: WelcomeWindowController,
        automaticUpdateCoordinator: AutomaticSoftwareUpdateCoordinator,
        isRunningUITests: Bool
    ) {
        self.userDefaults = userDefaults
        self.preferences = preferences
        self.settingsWindowController = settingsWindowController
        self.welcomeWindowController = welcomeWindowController
        self.automaticUpdateCoordinator = automaticUpdateCoordinator
        self.isRunningUITests = isRunningUITests
        migrateLegacyWelcomeCompletionIfNeeded()
        self.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                await self?.handleApplicationDidFinishLaunching(notification)
            }
        }
        welcomeWindowController.configure { [weak self] in
            self?.markWelcomeCompleted()
        }

        if Self.shouldShowSettingsForUITest {
            Task { @MainActor [self] in
                try? await Task.sleep(nanoseconds: 200_000_000)
                await presentInitialSettingsIfNeeded(isDefaultLaunch: true, forceShowSettings: true)
            }
        }
    }

    deinit {
        observer.map(NotificationCenter.default.removeObserver)
    }

    private func handleApplicationDidFinishLaunching(_ notification: Notification) async {
        let shouldShowSettingsForUITest = Self.shouldShowSettingsForUITest
        if isRunningUITests && !shouldShowSettingsForUITest {
            return
        }

        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue ?? true
        guard isDefaultLaunch || shouldShowSettingsForUITest else {
            return
        }

        await presentInitialSettingsIfNeeded(isDefaultLaunch: isDefaultLaunch, forceShowSettings: shouldShowSettingsForUITest)
    }

    private func presentInitialSettingsIfNeeded(isDefaultLaunch: Bool, forceShowSettings: Bool) async {
        guard didHandleInitialPresentation == false else {
            return
        }

        if isRunningUITests && !forceShowSettings {
            didHandleInitialPresentation = true
            return
        }

        guard isDefaultLaunch || forceShowSettings else {
            return
        }

        let needsPermissionReview = await SoftwareUpdatePermissionRecovery.shouldPresentReviewAfterLaunch(userDefaults: userDefaults)
        let isDebugLaunch = ProcessInfo.processInfo.arguments.contains("-NSDocumentRevisionsDebugMode")
        let action = Self.resolvedInitialPresentationAction(
            isRunningUITests: isRunningUITests,
            forceShowSettings: forceShowSettings,
            isDefaultLaunch: isDefaultLaunch,
            needsPermissionReview: needsPermissionReview,
            hasCompletedWelcome: hasCompletedWelcome,
            isDebugLaunch: isDebugLaunch,
            menuBarItemEnabled: preferences.menuBarItemEnabled
        )

        didHandleInitialPresentation = true

        switch action {
        case .none:
            return
        case .automaticUpdateCheck:
            automaticUpdateCoordinator.checkIfNeeded()
        case .showWelcome:
            welcomeWindowController.show()
        case .showSettings(let section):
            if needsPermissionReview {
                markWelcomeCompleted()
            }
            settingsWindowController.show(section: section)
        }
    }

    nonisolated static func resolvedInitialPresentationAction(
        isRunningUITests: Bool,
        forceShowSettings: Bool,
        isDefaultLaunch: Bool,
        needsPermissionReview: Bool,
        hasCompletedWelcome: Bool,
        isDebugLaunch: Bool,
        menuBarItemEnabled: Bool
    ) -> InitialPresentationAction {
        if isRunningUITests && !forceShowSettings {
            return .none
        }

        guard isDefaultLaunch || forceShowSettings else {
            return .none
        }

        if needsPermissionReview {
            return .showSettings(.permissions)
        }

        if forceShowSettings {
            return .showSettings(nil)
        }

        if !hasCompletedWelcome && !isDebugLaunch && menuBarItemEnabled {
            return .showWelcome
        }

        if isDebugLaunch || !menuBarItemEnabled {
            return .showSettings(nil)
        }

        return .automaticUpdateCheck
    }

    private var hasCompletedWelcome: Bool {
        userDefaults.bool(forKey: WelcomeFlowPersistence.completedKey)
            || userDefaults.bool(forKey: WelcomeFlowPersistence.legacyInitialSettingsKey)
    }

    private func migrateLegacyWelcomeCompletionIfNeeded() {
        guard userDefaults.bool(forKey: WelcomeFlowPersistence.legacyInitialSettingsKey),
              !userDefaults.bool(forKey: WelcomeFlowPersistence.completedKey) else {
            return
        }

        userDefaults.set(true, forKey: WelcomeFlowPersistence.completedKey)
    }

    private func markWelcomeCompleted() {
        userDefaults.set(true, forKey: WelcomeFlowPersistence.completedKey)
        userDefaults.set(true, forKey: WelcomeFlowPersistence.legacyInitialSettingsKey)
        userDefaults.removeObject(forKey: WelcomeFlowPersistence.currentStepKey)
    }

    private static var shouldShowSettingsForUITest: Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments

        return environment["CURRENCY_TRACKER_UI_TEST_SHOW_SETTINGS"] == "1"
            || arguments.contains("-CurrencyTrackerUITestShowSettings")
    }
}
