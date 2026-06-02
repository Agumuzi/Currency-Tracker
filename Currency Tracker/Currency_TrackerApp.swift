//
//  Currency_TrackerApp.swift
//  Currency Tracker
//
//  Created by Thomas Tao on 4/10/26.
//

import AppKit
import Observation
import SwiftUI

@main
struct Currency_TrackerApp: App {
    @NSApplicationDelegateAdaptor(ApplicationLifecycleController.self) private var lifecycleController

    private let userDefaults: UserDefaults
    private let preferences: PreferencesStore
    private let credentialStore: EnhancedSourceCredentialStore
    private let launchController: LaunchAtLoginController
    private let settingsWindowController: SettingsWindowController
    private let welcomeWindowController: WelcomeWindowController
    private let panelWindowController: PanelWindowController
    private let softwareUpdateWindowController: SoftwareUpdateWindowController
    private let automaticUpdateCoordinator: AutomaticSoftwareUpdateCoordinator
    private let serviceActionHandler: ServiceActionHandler
    private let globalShortcutHandler: GlobalShortcutHandler
    private let initialLaunchCoordinator: InitialLaunchCoordinator
    private let statusItemController: StatusItemController
    private let isRunningUITests: Bool
    @State private var viewModel: ExchangePanelViewModel

    init() {
        let isRunningUITests = Self.isRunningUITests()
        let userDefaults = Self.makeUserDefaults()
        let secretStore = Self.makeSecretStore()
        let preferences = PreferencesStore(userDefaults: userDefaults, secretStore: secretStore)
        let credentialStore = EnhancedSourceCredentialStore(secretStore: secretStore, userDefaults: userDefaults)
        let launchController = LaunchAtLoginController()
        let service = ExchangeRateService()
        let store = ExchangeRateStore()
        let viewModel = ExchangePanelViewModel(
            preferences: preferences,
            credentialStore: credentialStore,
            service: service,
            store: store,
            previewState: isRunningUITests ? .sample : nil
        )
        let dockVisibilityController = DockVisibilityController { level, message in
            viewModel.recordInternalEvent(message, level: level)
        }
        let panelWindowController = PanelWindowController(viewModel: viewModel)
        let softwareUpdateWindowController = SoftwareUpdateWindowController()
        let promptPanel = LightweightPromptPanel()
        let clipboardWriter = ClipboardWriter()
        let conversionCoordinator = ConversionCoordinator(
            preferences: preferences,
            credentialStore: credentialStore,
            service: service,
            store: store,
            promptPanel: promptPanel,
            clipboardWriter: clipboardWriter,
            liveLogHandler: { level, message in
                viewModel.recordInternalEvent(message, level: level)
            },
            snapshotMergeHandler: { snapshots in
                viewModel.mergeServiceSnapshots(snapshots)
            }
        )
        let globalShortcutHandler = GlobalShortcutHandler(
            preferences: preferences,
            coordinator: conversionCoordinator,
            popupPresenter: promptPanel,
            logHandler: { level, message in
                viewModel.recordInternalEvent(message, level: level)
            }
        )
        let serviceActionHandler = ServiceActionHandler(coordinator: conversionCoordinator)
        let settingsWindowController = SettingsWindowController(
            preferences: preferences,
            credentialStore: credentialStore,
            launchController: launchController,
            viewModel: viewModel,
            service: service,
            dockVisibilityController: dockVisibilityController,
            globalShortcutHandler: globalShortcutHandler,
            softwareUpdateWindowController: softwareUpdateWindowController
        )
        let welcomeWindowController = WelcomeWindowController(
            userDefaults: userDefaults,
            launchController: launchController
        )
        panelWindowController.configurePinnedContent { controller in
            AnyView(
                ContentView(
                    viewModel: viewModel,
                    preferences: preferences,
                    settingsWindowController: settingsWindowController,
                    panelWindowController: controller,
                    autoBootstrap: false,
                    presentationMode: .pinned,
                    menuBarMaximumPanelHeight: nil
                )
            )
        }
        let automaticUpdateCoordinator = AutomaticSoftwareUpdateCoordinator(
            preferences: preferences,
            updateWindowController: softwareUpdateWindowController,
            isRunningUITests: isRunningUITests
        )
        let initialLaunchCoordinator = InitialLaunchCoordinator(
            userDefaults: userDefaults,
            preferences: preferences,
            settingsWindowController: settingsWindowController,
            welcomeWindowController: welcomeWindowController,
            automaticUpdateCoordinator: automaticUpdateCoordinator,
            isRunningUITests: isRunningUITests
        )
        let statusItemController = StatusItemController(
            preferences: preferences,
            viewModel: viewModel,
            settingsWindowController: settingsWindowController,
            panelWindowController: panelWindowController,
            isRunningUITests: isRunningUITests
        )
        self.isRunningUITests = isRunningUITests
        self.userDefaults = userDefaults
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.launchController = launchController
        self.settingsWindowController = settingsWindowController
        self.welcomeWindowController = welcomeWindowController
        self.panelWindowController = panelWindowController
        self.softwareUpdateWindowController = softwareUpdateWindowController
        self.automaticUpdateCoordinator = automaticUpdateCoordinator
        self.serviceActionHandler = serviceActionHandler
        self.globalShortcutHandler = globalShortcutHandler
        self.initialLaunchCoordinator = initialLaunchCoordinator
        self.statusItemController = statusItemController
        _viewModel = State(initialValue: viewModel)
        NSApplication.shared.setActivationPolicy(isRunningUITests || !preferences.menuBarItemEnabled ? .regular : .accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Currency Tracker menu bar app remains active")
        lifecycleController.configure { [weak settingsWindowController] in
            settingsWindowController?.show()
        }
        serviceActionHandler.register()
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    settingsWindowController.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private static func makeUserDefaults() -> UserDefaults {
        let environment = ProcessInfo.processInfo.environment
        guard let suiteName = environment["CURRENCY_TRACKER_DEFAULTS_SUITE"],
              let defaults = UserDefaults(suiteName: suiteName) else {
            return .standard
        }

        if environment["CURRENCY_TRACKER_RESET_DEFAULTS"] == "1" {
            defaults.removePersistentDomain(forName: suiteName)
        }

        return defaults
    }

    private static func isRunningUITests() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments

        return environment["XCTestConfigurationFilePath"] != nil
            || environment["CURRENCY_TRACKER_UI_TEST_SHOW_SETTINGS"] == "1"
            || arguments.contains("-CurrencyTrackerUITestShowSettings")
    }

    private static func makeSecretStore() -> any SecretStoring {
        let environment = ProcessInfo.processInfo.environment

        if environment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] == "1" {
            return EphemeralSecretStore()
        }

        return LocalSecretStore(service: "com.thomas.currency-tracker")
    }
}

@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let preferences: PreferencesStore
    private let viewModel: ExchangePanelViewModel
    private let settingsWindowController: SettingsWindowController
    private let panelWindowController: PanelWindowController
    private let isRunningUITests: Bool
    private var statusItem: NSStatusItem?
    private var menuPanel: NSPanel?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    init(
        preferences: PreferencesStore,
        viewModel: ExchangePanelViewModel,
        settingsWindowController: SettingsWindowController,
        panelWindowController: PanelWindowController,
        isRunningUITests: Bool
    ) {
        self.preferences = preferences
        self.viewModel = viewModel
        self.settingsWindowController = settingsWindowController
        self.panelWindowController = panelWindowController
        self.isRunningUITests = isRunningUITests
        super.init()
        applyState()
        observeState()
    }

    private func observeState() {
        withObservationTracking {
            _ = preferences.menuBarItemEnabled
            _ = preferences.menuBarDisplayMode
            _ = viewModel.cards
            _ = viewModel.featuredPairID
            _ = viewModel.menuBarHelpText
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.applyState()
                self?.observeState()
            }
        }
    }

    private func applyState() {
        if isRunningUITests || !preferences.menuBarItemEnabled {
            removeStatusItem()
        } else {
            ensureStatusItem()
            updateButton()
        }
    }

    private func removeStatusItem() {
        closeMenuPanel()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func ensureStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func updateButton() {
        guard let button = statusItem?.button else {
            return
        }

        let featuredCard = viewModel.cards.first { $0.id == viewModel.featuredPairID } ?? viewModel.cards.first
        let symbolImage = Self.menuBarIcon
        button.image = nil
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = viewModel.menuBarHelpText

        switch preferences.menuBarDisplayMode {
        case .iconOnly:
            statusItem?.length = NSStatusItem.squareLength
            button.image = symbolImage
        case .pairOnly:
            statusItem?.length = NSStatusItem.variableLength
            if let featuredCard {
                button.image = symbolImage
                button.imagePosition = .imageLeading
                button.title = " \(featuredCard.compactPairLabel)"
            } else {
                button.imagePosition = .imageOnly
                button.image = symbolImage
            }
        case .featuredRate:
            statusItem?.length = NSStatusItem.variableLength
            if let featuredCard, featuredCard.snapshot != nil {
                button.image = symbolImage
                button.imagePosition = .imageLeading
                button.title = " \(featuredCard.valueText)"
            } else {
                button.imagePosition = .imageOnly
                button.image = symbolImage
            }
        case .compactPair:
            statusItem?.length = NSStatusItem.variableLength
            if let featuredCard, featuredCard.snapshot != nil {
                button.image = symbolImage
                button.imagePosition = .imageLeading
                button.title = " \(featuredCard.compactPairLabel) \(featuredCard.valueText)"
            } else {
                button.imagePosition = .imageOnly
                button.image = symbolImage
            }
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard preferences.menuBarItemEnabled else {
            return
        }

        if let menuPanel, menuPanel.isVisible {
            closeMenuPanel()
            return
        }

        let contentSize = resolvedMenuBarPopoverContentSize(for: sender)
        let frame = resolvedMenuBarPanelFrame(contentSize: contentSize, from: sender)
        let panel = MenuBarExchangeRatePanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("currency-tracker-menu-panel")
        panel.delegate = self
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.minSize = NSSize(width: 408, height: 320)
        panel.maxSize = NSSize(width: 560, height: max(760, contentSize.height))
        panel.contentViewController = NSHostingController(
            rootView: ContentView(
                viewModel: viewModel,
                preferences: preferences,
                settingsWindowController: settingsWindowController,
                panelWindowController: panelWindowController,
                autoBootstrap: !isRunningUITests,
                presentationMode: .menuBar,
                menuBarMaximumPanelHeight: contentSize.height
            )
        )
        panel.setContentSize(contentSize)
        panel.setFrame(frame, display: false)
        menuPanel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installMenuPanelDismissHandlers()
    }

    private func resolvedMenuBarPopoverContentSize(for button: NSStatusBarButton) -> NSSize {
        let visibleFrame = screen(for: button).visibleFrame
        let maximumHeight = max(Self.menuBarPopoverMinimumHeight, visibleFrame.height - (Self.menuBarPopoverScreenInset * 2))
        let contentHeight = estimatedMenuBarPopoverContentHeight()
        return NSSize(
            width: Self.menuBarPopoverWidth,
            height: min(max(contentHeight, Self.menuBarPopoverMinimumHeight), maximumHeight)
        )
    }

    private func estimatedMenuBarPopoverContentHeight() -> CGFloat {
        let pairCount = preferences.selectedPairs.count
        let cardAreaHeight: CGFloat
        if pairCount == 0 {
            cardAreaHeight = Self.collapsedCardHeight
        } else {
            cardAreaHeight = (CGFloat(pairCount) * Self.collapsedCardHeight)
                + (CGFloat(max(0, pairCount - 1)) * Self.cardSpacing)
                + Self.cardStackBottomPadding
        }

        let showsStatusBanner = shouldReserveMenuBarStatusBanner
        let bannerHeight = showsStatusBanner ? Self.statusBannerHeight : 0
        let spacingCount: CGFloat = showsStatusBanner ? 3 : 2

        return Self.panelTopPadding
            + Self.panelBottomPadding
            + Self.toolbarHeight
            + bannerHeight
            + Self.footerHeight
            + (spacingCount * Self.panelSectionSpacing)
            + cardAreaHeight
    }

    private var shouldReserveMenuBarStatusBanner: Bool {
        guard viewModel.statusMessage != nil else {
            return false
        }

        if preferences.selectedPairs.isEmpty {
            return true
        }

        return viewModel.statusSymbolName.contains("exclamationmark")
            || viewModel.cards.contains { $0.state != .ready }
    }

    private func resolvedMenuBarPanelFrame(contentSize: NSSize, from button: NSStatusBarButton) -> NSRect {
        let screen = screen(for: button)
        let visibleFrame = screen.visibleFrame
        let rawAnchorFrame = screenFrame(for: button)
        let anchorFrame = rawAnchorFrame.flatMap { frame in
            let hasUsableSize = frame.width >= 4 && frame.height >= 4
            let isNotPinnedToScreenEdge = frame.midX > visibleFrame.minX + 24
            return hasUsableSize && isNotPinnedToScreenEdge ? frame : nil
        }
        let topEdge = min(anchorFrame?.minY ?? visibleFrame.maxY, visibleFrame.maxY) - Self.menuBarPopoverTopInset
        let height = min(contentSize.height, max(Self.menuBarPopoverMinimumHeight, topEdge - visibleFrame.minY - Self.menuBarPopoverScreenInset))
        let fallbackX = visibleFrame.maxX - contentSize.width - Self.menuBarPopoverScreenInset
        let x = clamped(
            anchorFrame.map { $0.midX - (contentSize.width / 2) } ?? fallbackX,
            lower: visibleFrame.minX + Self.menuBarPopoverScreenInset,
            upper: max(visibleFrame.minX + Self.menuBarPopoverScreenInset, visibleFrame.maxX - contentSize.width - Self.menuBarPopoverScreenInset)
        )
        let y = clamped(
            topEdge - height,
            lower: visibleFrame.minY + Self.menuBarPopoverScreenInset,
            upper: max(visibleFrame.minY + Self.menuBarPopoverScreenInset, visibleFrame.maxY - height - Self.menuBarPopoverTopInset)
        )

        return NSRect(x: x, y: y, width: contentSize.width, height: height)
    }

    private func closeMenuPanel() {
        removeMenuPanelDismissHandlers()
        menuPanel?.contentViewController = nil
        menuPanel?.orderOut(nil)
        menuPanel = nil
    }

    private func installMenuPanelDismissHandlers() {
        removeMenuPanelDismissHandlers()

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, let menuPanel = self.menuPanel else {
                return event
            }

            if event.type == .keyDown, event.keyCode == 53 {
                self.closeMenuPanel()
                return nil
            }

            if let eventWindow = event.window, eventWindow === menuPanel {
                return event
            }

            self.closeMenuPanel()
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeMenuPanel()
            }
        }
    }

    private func removeMenuPanelDismissHandlers() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === menuPanel else {
            return
        }

        closeMenuPanel()
    }

    private func screenFrame(for button: NSStatusBarButton) -> NSRect? {
        guard let window = button.window else {
            return nil
        }

        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func screen(for button: NSStatusBarButton) -> NSScreen {
        if let screen = button.window?.screen {
            return screen
        }

        if let anchorFrame = screenFrame(for: button),
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) }) {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private static let menuBarPopoverWidth: CGFloat = 408
    private static let menuBarPopoverMinimumHeight: CGFloat = 320
    private static let menuBarPopoverScreenInset: CGFloat = 8
    private static let menuBarPopoverTopInset: CGFloat = 4
    private static let panelTopPadding: CGFloat = 14
    private static let panelBottomPadding: CGFloat = 12
    private static let panelSectionSpacing: CGFloat = 10
    private static let toolbarHeight: CGFloat = 36
    private static let statusBannerHeight: CGFloat = 44
    private static let footerHeight: CGFloat = 34
    private static let collapsedCardHeight: CGFloat = 112
    private static let cardSpacing: CGFloat = 12
    private static let cardStackBottomPadding: CGFloat = 10

    private static let menuBarIcon: NSImage = {
        let pointSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: pointSize, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)

            NSColor.black.setStroke()
            NSColor.black.setFill()

            let lensRect = NSRect(x: 1.9, y: 5.05, width: 11.7, height: 11.7)

            let handlePath = NSBezierPath()
            handlePath.lineWidth = 3.05
            handlePath.lineCapStyle = .round
            handlePath.move(to: NSPoint(x: 12.55, y: 6.05))
            handlePath.line(to: NSPoint(x: 16.15, y: 1.95))
            handlePath.stroke()

            let lensPath = NSBezierPath(ovalIn: lensRect)
            lensPath.lineWidth = 1.55
            lensPath.stroke()

            let yenPath = NSBezierPath()
            yenPath.lineWidth = 1.85
            yenPath.lineCapStyle = .butt
            yenPath.lineJoinStyle = .miter
            yenPath.move(to: NSPoint(x: 5.45, y: 13.55))
            yenPath.line(to: NSPoint(x: 7.78, y: 9.70))
            yenPath.line(to: NSPoint(x: 10.1, y: 13.55))
            yenPath.move(to: NSPoint(x: 7.78, y: 9.70))
            yenPath.line(to: NSPoint(x: 7.78, y: 6.70))
            yenPath.stroke()

            let upperBar = NSBezierPath()
            upperBar.lineWidth = 1.05
            upperBar.lineCapStyle = .butt
            upperBar.move(to: NSPoint(x: 5.55, y: 9.15))
            upperBar.line(to: NSPoint(x: 10.0, y: 9.15))
            upperBar.stroke()

            let lowerBar = NSBezierPath()
            lowerBar.lineWidth = 1.05
            lowerBar.lineCapStyle = .butt
            lowerBar.move(to: NSPoint(x: 5.55, y: 7.85))
            lowerBar.line(to: NSPoint(x: 10.0, y: 7.85))
            lowerBar.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Currency Tracker"
        return image
    }()
}

private final class MenuBarExchangeRatePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class ApplicationLifecycleController: NSObject, NSApplicationDelegate {
    private static weak var current: ApplicationLifecycleController?
    private var reopenHandler: (() -> Void)?
    private var allowsTermination = false

    override init() {
        super.init()
        Self.current = self
    }

    func configure(reopenHandler: @escaping () -> Void) {
        self.reopenHandler = reopenHandler
    }

    static func terminate(_ sender: Any? = nil) {
        current?.allowsTermination = true
        NSApplication.shared.terminate(sender)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        allowsTermination ? .terminateNow : .terminateCancel
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenHandler?()
        return false
    }

}

private final class EphemeralSecretStore: SecretStoring {
    private var values: [String: String] = [:]

    func read(account: String) throws -> String? {
        values[account]
    }

    func write(_ value: String, account: String) throws {
        values[account] = value
    }

    func delete(account: String) throws {
        values[account] = nil
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let preferences: PreferencesStore
    private let credentialStore: EnhancedSourceCredentialStore
    private let launchController: LaunchAtLoginController
    private let viewModel: ExchangePanelViewModel
    private let service: ExchangeRateService
    private let dockVisibilityController: DockVisibilityController
    private let globalShortcutHandler: GlobalShortcutHandler
    private let softwareUpdateWindowController: SoftwareUpdateWindowController
    private lazy var apiConfigurationViewModel = APIConfigurationViewModel(
        credentialStore: credentialStore,
        service: service,
        logHandler: { [weak self] level, message in
            self?.viewModel.recordInternalEvent(message, level: level)
        }
    )
    private var windowController: NSWindowController?
    private var focusSection: SettingsSection?

    init(
        preferences: PreferencesStore,
        credentialStore: EnhancedSourceCredentialStore,
        launchController: LaunchAtLoginController,
        viewModel: ExchangePanelViewModel,
        service: ExchangeRateService,
        dockVisibilityController: DockVisibilityController,
        globalShortcutHandler: GlobalShortcutHandler,
        softwareUpdateWindowController: SoftwareUpdateWindowController
    ) {
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.launchController = launchController
        self.viewModel = viewModel
        self.service = service
        self.dockVisibilityController = dockVisibilityController
        self.globalShortcutHandler = globalShortcutHandler
        self.softwareUpdateWindowController = softwareUpdateWindowController
        super.init()
    }

    func show(section: SettingsSection? = nil) {
        focusSection = section
        if windowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeRootView()))
            window.identifier = NSUserInterfaceItemIdentifier("currency-tracker-settings-window")
            window.delegate = self
            window.title = "Currency Tracker"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unifiedCompact
            window.titlebarSeparatorStyle = .none
            window.isOpaque = true
            window.backgroundColor = Self.settingsWindowBackgroundColor
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 940, height: 660))
            window.minSize = NSSize(width: 820, height: 560)
            window.setFrameAutosaveName("currency-tracker-settings-window")
            window.center()

            windowController = NSWindowController(window: window)
        } else if let window = windowController?.window {
            window.contentViewController = NSHostingController(rootView: makeRootView())
        }

        dockVisibilityController.showDockForSettingsWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == windowController?.window else {
            return
        }

        dockVisibilityController.restoreMenuBarOnlyMode(shouldHideDock: preferences.menuBarItemEnabled)
        if preferences.menuBarItemEnabled == false && preferences.backgroundActivityEnabled == false {
            ApplicationLifecycleController.terminate(nil)
        }
    }

    private static var settingsWindowBackgroundColor: NSColor {
        NSColor(name: NSColor.Name("CurrencySettingsDetailBackground")) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if isDark {
                return NSColor(calibratedRed: 0.085, green: 0.088, blue: 0.092, alpha: 1)
            }

            return NSColor(calibratedRed: 0.955, green: 0.960, blue: 0.970, alpha: 1)
        }
    }

    private func makeRootView() -> SettingsView {
        SettingsView(
            preferences: preferences,
            launchController: launchController,
            viewModel: viewModel,
            apiConfigurationViewModel: apiConfigurationViewModel,
            globalShortcutHandler: globalShortcutHandler,
            softwareUpdateWindowController: softwareUpdateWindowController,
            focusSection: focusSection
        )
    }
}

@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private let userDefaults: UserDefaults
    private let launchController: LaunchAtLoginController
    private var windowController: NSWindowController?
    private var onComplete: (() -> Void)?
    private var didCompleteWelcome = false

    init(
        userDefaults: UserDefaults,
        launchController: LaunchAtLoginController
    ) {
        self.userDefaults = userDefaults
        self.launchController = launchController
        super.init()
    }

    func configure(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    func show() {
        if windowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: makeRootView()))
            window.identifier = NSUserInterfaceItemIdentifier("currency-tracker-welcome-window")
            window.delegate = self
            window.title = "Currency Tracker"
            window.styleMask = [.titled, .closable]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.isReleasedWhenClosed = false
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.setContentSize(NSSize(width: 620, height: 480))
            window.center()
            windowController = NSWindowController(window: window)
        } else if let window = windowController?.window {
            window.contentViewController = NSHostingController(rootView: makeRootView())
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == windowController?.window else {
            return
        }

        completeWelcomeIfNeeded()
        windowController = nil
    }

    private func makeRootView() -> FirstRunWelcomeView {
        FirstRunWelcomeView(
            initialStep: currentStep,
            launchController: launchController,
            persistStep: { [weak self] step in
                self?.persistStep(step)
            },
            complete: { [weak self] in
                self?.completeAndClose()
            }
        )
    }

    private var currentStep: WelcomeStep {
        WelcomeStep.normalized(rawValue: userDefaults.object(forKey: WelcomeFlowPersistence.currentStepKey) as? Int)
    }

    private func persistStep(_ step: WelcomeStep) {
        userDefaults.set(step.rawValue, forKey: WelcomeFlowPersistence.currentStepKey)
    }

    private func completeAndClose() {
        completeWelcomeIfNeeded()
        windowController?.close()
    }

    private func completeWelcomeIfNeeded() {
        guard !didCompleteWelcome else {
            return
        }

        didCompleteWelcome = true
        userDefaults.removeObject(forKey: WelcomeFlowPersistence.currentStepKey)
        onComplete?()
    }
}
