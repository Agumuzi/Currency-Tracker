import Darwin
import Foundation

struct BackupSettings: Codable {
    var selectedPairIDs: [String]
    var converterCurrenciesFollowSelectedPairs: Bool
    var converterCurrencyCodes: [String]
    var autoRefreshMinutes: Int
    var menuBarOpenRefreshEnabled: Bool
    var trendPointLimit: Int
    var featuredPairID: String
    var showsFlags: Bool
    var baseCurrencyCode: String
    var textConversionShortcut: GlobalShortcutDescriptor?
    var automaticUpdateChecksEnabled: Bool
    var menuBarItemEnabled: Bool
    var backgroundActivityEnabled: Bool
    var menuBarDisplayMode: MenuBarDisplayMode
    var rateDisplayBaseAmount: Int
    var conversionFractionDigits: Int
    var rateAlerts: [RateAlert]
    var settingsProfiles: [SettingsProfile]
    var activeProfileID: UUID?
    var customAPIProviders: [CustomAPIProvider]
}

struct ConfigurationBackup: Codable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var appVersion: String
    var exportedAt: Date
    var settings: BackupSettings
    var enhancedCredentials: [String: String]
    var selectedEnhancedSources: [String]

    var pairCount: Int { settings.selectedPairIDs.count }
    var profileCount: Int { settings.settingsProfiles.count }
    var sourceCount: Int { enhancedCredentials.count + settings.customAPIProviders.count }
}

enum ConfigurationBackupError: LocalizedError {
    case fileTooLarge
    case unsupportedFormat
    case invalidContent
    case failedToSave

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: String(localized: "备份文件过大")
        case .unsupportedFormat: String(localized: "不支持此备份版本")
        case .invalidContent: String(localized: "备份内容无效")
        case .failedToSave: String(localized: "无法保存备份文件")
        }
    }
}

@MainActor
final class ConfigurationBackupService {
    private let preferences: PreferencesStore
    private let credentialStore: EnhancedSourceCredentialStore
    private let secretStore: any SecretStoring
    private let backupDirectory: URL

    init(
        preferences: PreferencesStore,
        credentialStore: EnhancedSourceCredentialStore,
        secretStore: any SecretStoring,
        backupDirectory: URL? = nil
    ) {
        self.preferences = preferences
        self.credentialStore = credentialStore
        self.secretStore = secretStore
        if let backupDirectory {
            self.backupDirectory = backupDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.backupDirectory = base.appendingPathComponent("CurrencyTracker/Backups", isDirectory: true)
        }
    }

    func makeBackup(appVersion: String) throws -> ConfigurationBackup {
        var credentials: [String: String] = [:]
        for kind in EnhancedCredentialKind.allCases {
            let value = try secretStore.read(account: kind.account) ?? credentialStore.storedValue(for: kind)
            if !value.isEmpty { credentials[kind.rawValue] = value }
        }
        var settings = preferences.backupSettings()
        for index in settings.customAPIProviders.indices {
            let provider = settings.customAPIProviders[index]
            settings.customAPIProviders[index].apiKey = try secretStore.read(account: provider.localSecretAccount)
                ?? provider.apiKey
        }
        return ConfigurationBackup(
            formatVersion: ConfigurationBackup.currentFormatVersion,
            appVersion: appVersion,
            exportedAt: .now,
            settings: settings,
            enhancedCredentials: credentials,
            selectedEnhancedSources: credentialStore.selectedKinds.map(\.rawValue)
        )
    }

    func encoded(_ backup: ConfigurationBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    func prepareImport(_ data: Data) throws -> ConfigurationBackup {
        guard data.count <= 2_000_000 else { throw ConfigurationBackupError.fileTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(ConfigurationBackup.self, from: data)
        guard backup.formatVersion == ConfigurationBackup.currentFormatVersion else {
            throw ConfigurationBackupError.unsupportedFormat
        }
        try validate(backup)
        return backup
    }

    /// Saves a recovery copy before changing any live settings or credentials.
    @discardableResult
    func importBackup(_ backup: ConfigurationBackup, appVersion: String) throws -> URL {
        try validate(backup)
        let previous = try makeBackup(appVersion: appVersion)
        let recoveryURL = backupDirectory.appendingPathComponent("pre-import-\(UUID().uuidString).json")
        try Self.writeOwnerOnly(try encoded(previous), to: recoveryURL)

        let allAccounts = Set(EnhancedCredentialKind.allCases.map(\.account))
            .union(previous.settings.customAPIProviders.map(\.localSecretAccount))
            .union(backup.settings.customAPIProviders.map(\.localSecretAccount))
        let oldValues = try Dictionary(uniqueKeysWithValues: allAccounts.map { account in
            (account, try secretStore.read(account: account) ?? "")
        })
        var newValues: [String: String] = [:]
        for kind in EnhancedCredentialKind.allCases {
            newValues[kind.account] = backup.enhancedCredentials[kind.rawValue] ?? ""
        }
        for provider in backup.settings.customAPIProviders {
            newValues[provider.localSecretAccount] = provider.apiKey
        }
        var updates = Dictionary(uniqueKeysWithValues: allAccounts.map { ($0, "") })
        updates.merge(newValues) { _, imported in imported }

        do {
            try secretStore.replaceValues(updates)
        } catch {
            try? secretStore.replaceValues(oldValues)
            throw error
        }

        preferences.restoreBackupSettings(backup.settings)
        credentialStore.restoreSelectedKinds(backup.selectedEnhancedSources.compactMap(EnhancedCredentialKind.init(rawValue:)))
        credentialStore.reload()
        return recoveryURL
    }

    func export(_ backup: ConfigurationBackup, to url: URL) throws {
        try Self.writeOwnerOnly(try encoded(backup), to: url)
    }

    private func validate(_ backup: ConfigurationBackup) throws {
        guard backup.formatVersion == ConfigurationBackup.currentFormatVersion else {
            throw ConfigurationBackupError.unsupportedFormat
        }
        let settings = backup.settings
        let pairIDs = settings.selectedPairIDs
        guard pairIDs.allSatisfy({ PreferencesStore.pairForDisplay(id: $0) != nil }),
              Set(pairIDs).count == pairIDs.count,
              settings.featuredPairID.isEmpty || pairIDs.contains(settings.featuredPairID),
              CurrencyCatalog.info(for: settings.baseCurrencyCode) != nil,
              [0, 5, 10, 30, 60].contains(settings.autoRefreshMinutes),
              [12, 20, 30, 50].contains(settings.trendPointLimit),
              CurrencyDisplayFormatting.displayBaseAmountOptions.contains(settings.rateDisplayBaseAmount),
              CurrencyDisplayFormatting.fractionDigitOptions.contains(settings.conversionFractionDigits),
              PreferencesStore.normalizedCurrencyCodes(settings.converterCurrencyCodes) == settings.converterCurrencyCodes,
              Set(settings.customAPIProviders.map(\.id)).count == settings.customAPIProviders.count,
              settings.rateAlerts.allSatisfy({ PreferencesStore.pairForDisplay(id: $0.pairID) != nil && $0.threshold.isFinite && $0.threshold > 0 }),
              Set(settings.settingsProfiles.map(\.id)).count == settings.settingsProfiles.count,
              settings.settingsProfiles.allSatisfy({ profile in
                  profile.selectedPairIDs.allSatisfy { PreferencesStore.pairForDisplay(id: $0) != nil }
                      && Set(profile.selectedPairIDs).count == profile.selectedPairIDs.count
                      && PreferencesStore.normalizedCurrencyCodes(profile.converterCurrencyCodes) == profile.converterCurrencyCodes
                      && CurrencyCatalog.info(for: profile.baseCurrencyCode) != nil
                      && [0, 5, 10, 30, 60].contains(profile.autoRefreshMinutes)
                      && [12, 20, 30, 50].contains(profile.trendPointLimit)
              }),
              settings.activeProfileID == nil || settings.settingsProfiles.contains(where: { $0.id == settings.activeProfileID }),
              backup.enhancedCredentials.keys.allSatisfy({ EnhancedCredentialKind(rawValue: $0) != nil }),
              backup.selectedEnhancedSources.allSatisfy({ EnhancedCredentialKind(rawValue: $0) != nil }),
              Set(backup.selectedEnhancedSources).count == backup.selectedEnhancedSources.count else {
            throw ConfigurationBackupError.invalidContent
        }
    }

    static func writeOwnerOnly(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        guard fileManager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw ConfigurationBackupError.failedToSave
        }
        defer { try? fileManager.removeItem(at: temporary) }
        guard rename(temporary.path, url.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
