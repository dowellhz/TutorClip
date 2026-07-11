import Combine
import Foundation
import ServiceManagement

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var temporaryAPIKey: String
    @Published var keySource: String
    @Published var hasScreenCapturePermission: Bool
    @Published var hasAccessibilityPermission: Bool
    @Published var shortcutValidationMessage: String = ""
    @Published var shortcutRegistrationMessage: String
    @Published var shortcutIsRegistered: Bool
    @Published var launchAtLoginMessage: String
    @Published var saveStatusMessage: String = ""
    @Published var saveStatusIsError: Bool = false
    @Published var diagnostics: [DiagnosticItem] = []
    @Published private(set) var isRunningDiagnostics: Bool = false
    @Published var historyStatusMessage: String = ""
    @Published var historyStatusIsError: Bool = false
    @Published var isClearingHistory: Bool = false

    private let settingsStore: SettingsStore
    private let configLoader: ConfigLoader
    private let historyStore: HistoryStore
    private let onShortcutChanged: () -> Void
    private let updateLaunchAtLogin: @MainActor (Bool) throws -> Void
    private let diagnosticsRunner: (AppSettings, ShortcutRegistrationResult, DeepSeekConfig) async -> [DiagnosticItem]
    private var diagnosticsTask: Task<Void, Never>?
    private var diagnosticsRunID: UUID?

    init(
        settingsStore: SettingsStore,
        configLoader: ConfigLoader,
        historyStore: HistoryStore,
        onShortcutChanged: @escaping () -> Void,
        updateLaunchAtLogin: @escaping @MainActor (Bool) throws -> Void = SettingsViewModel.updateSystemLaunchAtLogin,
        diagnosticsRunner: @escaping (AppSettings, ShortcutRegistrationResult, DeepSeekConfig) async -> [DiagnosticItem] = DiagnosticsService.runWithCaptureProbe
    ) {
        self.settingsStore = settingsStore
        self.configLoader = configLoader
        self.historyStore = historyStore
        self.onShortcutChanged = onShortcutChanged
        self.updateLaunchAtLogin = updateLaunchAtLogin
        self.diagnosticsRunner = diagnosticsRunner
        settings = settingsStore.settings
        temporaryAPIKey = configLoader.temporaryAPIKey
        keySource = configLoader.currentConfig(settings: settingsStore.settings).keySource.rawValue
        hasScreenCapturePermission = PermissionService.hasScreenCapturePermission()
        hasAccessibilityPermission = PermissionService.hasAccessibilityPermission()
        shortcutRegistrationMessage = settingsStore.shortcutRegistrationResult.message
        shortcutIsRegistered = settingsStore.shortcutRegistrationResult.isRegistered
        launchAtLoginMessage = Self.launchAtLoginStatusMessage(language: settingsStore.settings.appLanguage)
        if let error = settingsStore.persistenceError {
            saveStatusMessage = settings.appLanguage.text("设置读取失败：\(error)", "Failed to load settings: \(error)")
            saveStatusIsError = true
        }
    }

    func save() {
        let previousSettings = settingsStore.settings
        guard settingsStore.update({ $0 = settings }) else {
            let detail = settingsStore.persistenceError ?? settings.appLanguage.text("未知磁盘错误", "Unknown disk error")
            saveStatusMessage = settings.appLanguage.text("设置保存失败：\(detail)", "Failed to save settings: \(detail)")
            saveStatusIsError = true
            return
        }
        configLoader.temporaryAPIKey = temporaryAPIKey
        let launchUpdateError = applyLaunchAtLoginIfNeeded(previousValue: previousSettings.launchAtLogin)
        keySource = configLoader.currentConfig(settings: settingsStore.settings).keySource.rawValue
        onShortcutChanged()
        shortcutRegistrationMessage = settingsStore.shortcutRegistrationResult.message
        shortcutIsRegistered = settingsStore.shortcutRegistrationResult.isRegistered
        if let launchUpdateError {
            saveStatusMessage = launchUpdateError
            saveStatusIsError = true
        } else {
            saveStatusMessage = settings.appLanguage.text("设置已保存。", "Settings saved.")
            saveStatusIsError = false
        }
    }

    func configPath() -> String {
        configLoader.configFilePath()
    }

    func persistAPIKeyToConfig() {
        configLoader.temporaryAPIKey = temporaryAPIKey
        do {
            try configLoader.persistTemporaryAPIKey(settings: settings)
            keySource = configLoader.currentConfig(settings: settings).keySource.rawValue
            saveStatusMessage = settings.appLanguage.text("API Key 已保存到本地配置。", "API Key saved to local config.")
            saveStatusIsError = false
        } catch {
            saveStatusMessage = settings.appLanguage.text("API Key 保存失败：\(error.localizedDescription)", "Failed to save API Key: \(error.localizedDescription)")
            saveStatusIsError = true
        }
    }

    func removeAPIKeyFromConfig() {
        do {
            try configLoader.removePersistedAPIKey()
            keySource = configLoader.currentConfig(settings: settings).keySource.rawValue
            saveStatusMessage = settings.appLanguage.text("本地配置中的 API Key 已删除。", "API Key removed from local config.")
            saveStatusIsError = false
        } catch {
            saveStatusMessage = settings.appLanguage.text("API Key 删除失败：\(error.localizedDescription)", "Failed to remove API Key: \(error.localizedDescription)")
            saveStatusIsError = true
        }
    }

    func refreshPermissions() {
        hasScreenCapturePermission = PermissionService.hasScreenCapturePermission()
        hasAccessibilityPermission = PermissionService.hasAccessibilityPermission()
    }

    func requestScreenCapturePermission() {
        _ = PermissionService.requestScreenCapturePermission()
        PermissionService.openPrivacySettings()
        refreshPermissions()
    }

    func openScreenRecordingSettings() {
        PermissionService.openPrivacySettings()
    }

    func requestAccessibilityPermission() {
        PermissionService.requestAccessibilityPermission()
        PermissionService.openAccessibilitySettings()
        refreshPermissions()
    }

    func clearHistory() {
        guard !isClearingHistory else { return }
        isClearingHistory = true
        historyStatusMessage = settings.appLanguage.text("正在清空历史…", "Clearing history…")
        historyStatusIsError = false
        historyStore.clear { [weak self] success in
            guard let self else { return }
            self.isClearingHistory = false
            self.historyStatusIsError = !success
            self.historyStatusMessage = success
                ? self.settings.appLanguage.text("历史已清空。", "History cleared.")
                : self.settings.appLanguage.text("清空历史失败，请查看运行日志。", "Failed to clear history. Check the runtime log.")
        }
    }

    func runDiagnostics() {
        diagnosticsTask?.cancel()
        let runID = UUID()
        diagnosticsRunID = runID
        let currentSettings = settingsStore.settings
        let shortcut = settingsStore.shortcutRegistrationResult
        let config = configLoader.currentConfig(settings: currentSettings)
        diagnostics = [
            DiagnosticItem(
                title: currentSettings.appLanguage.text("诊断", "Diagnostics"),
                state: .warn,
                detail: currentSettings.appLanguage.text("正在运行实际截屏探针...", "Running capture probe...")
            )
        ]
        isRunningDiagnostics = true
        let runner = diagnosticsRunner
        diagnosticsTask = Task { [weak self] in
            let result = await runner(currentSettings, shortcut, config)
            guard !Task.isCancelled,
                  let self,
                  self.diagnosticsRunID == runID else { return }
            self.diagnostics = result
            self.isRunningDiagnostics = false
            self.diagnosticsTask = nil
        }
    }

    func cancelDiagnostics() {
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        diagnosticsRunID = nil
        isRunningDiagnostics = false
    }

    private func applyLaunchAtLoginIfNeeded(previousValue: Bool) -> String? {
        guard settings.launchAtLogin != previousValue else {
            launchAtLoginMessage = Self.launchAtLoginStatusMessage(language: settings.appLanguage)
            return nil
        }
        do {
            try updateLaunchAtLogin(settings.launchAtLogin)
            launchAtLoginMessage = Self.launchAtLoginStatusMessage(language: settings.appLanguage)
            return nil
        } catch {
            let message = settings.appLanguage.text(
                "登录启动更新失败：\(error.localizedDescription)",
                "Launch at login update failed: \(error.localizedDescription)"
            )
            settings.launchAtLogin = previousValue
            let rollbackSucceeded = settingsStore.update { $0.launchAtLogin = previousValue }
            launchAtLoginMessage = message
            if !rollbackSucceeded {
                let rollbackError = settingsStore.persistenceError ?? settings.appLanguage.text("未知磁盘错误", "Unknown disk error")
                return settings.appLanguage.text(
                    "\(message)；设置回滚失败：\(rollbackError)",
                    "\(message); settings rollback failed: \(rollbackError)"
                )
            }
            return message
        }
    }

    private static func updateSystemLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    private static func launchAtLoginStatusMessage(language: AppLanguage) -> String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return language.text("登录时启动已启用。", "Launch at login is enabled.")
        case .requiresApproval:
            return language.text("登录时启动需要在系统设置中批准。", "Launch at login requires approval in System Settings.")
        case .notRegistered:
            return language.text("登录时启动已关闭。", "Launch at login is disabled.")
        case .notFound:
            return language.text("当前 App 包不支持登录时启动。", "Launch at login is unavailable for this app bundle.")
        @unknown default:
            return language.text("登录时启动状态未知。", "Launch at login status is unknown.")
        }
    }
}

