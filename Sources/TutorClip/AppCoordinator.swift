import AppKit
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    let settingsStore = SettingsStore()
    let configLoader = ConfigLoader()
    let historyStore = HistoryStore()
    let ocrService = OCRService()
    let promptBuilder = PromptBuilder()
    private let ocrRequestLifecycle = OCRRequestLifecycle()

    private var menuBarController: MenuBarController?
    private var shortcutManager: ShortcutManager?
    private var captureController: CaptureOverlayController?
    private var tutorWindowController: TutorWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var launchMarkerTimer: Timer?
    private var didHandleCommandLineDemo = false
    private var captureHiddenWindows: [NSWindow] = []
    private var captureGeneration = CaptureGenerationTracker()

    func start() {
        RuntimeLog.write("coordinator-start")
        historyStore.open()
        menuBarController = MenuBarController(coordinator: self)
        shortcutManager = ShortcutManager(settings: settingsStore.settings) { [weak self] in
            Task { @MainActor in self?.beginCapture() }
        }
        settingsStore.shortcutRegistrationResult = shortcutManager?.register() ?? .unregistered
        RuntimeLog.write("shortcut-register \(settingsStore.shortcutRegistrationResult.isRegistered) \(settingsStore.shortcutRegistrationResult.message)")
        handleLaunchMarkers()
        launchMarkerTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.handleLaunchMarkers() }
        }
    }

    func shutdown() {
        RuntimeLog.write("coordinator-shutdown")
        ocrRequestLifecycle.cancel(reason: "app-shutdown")
        captureController?.cancel()
        captureController = nil
        captureGeneration.invalidate()
        launchMarkerTimer?.invalidate()
        shortcutManager?.unregister()
        historyStore.close()
    }

    func beginCapture() {
        RuntimeLog.write("begin-capture")
        guard PermissionService.hasScreenCapturePermission() else {
            RuntimeLog.write("begin-capture-blocked-screen-permission")
            showScreenCapturePermissionRequired()
            return
        }
        captureController?.cancel()
        let captureID = captureGeneration.start()
        hideAppWindowsForCapture()
        captureController = CaptureOverlayController { [weak self] result in
            guard let self else { return }
            guard self.captureGeneration.accept(captureID) else {
                RuntimeLog.write("capture-result-stale")
                return
            }
            switch result {
            case .cancelled:
                RuntimeLog.write("capture-result-cancelled")
                self.captureController = nil
                self.restoreAppWindowsAfterCancelledCapture()
                self.ensureShortcutRegistered()
            case .captured(let image, let selectionRect):
                RuntimeLog.write("capture-result-captured size=\(Int(image.size.width))x\(Int(image.size.height))")
                self.captureController = nil
                self.restoreAppWindowsAfterCapture()
                self.ensureShortcutRegistered()
                self.handleCapturedImage(image, selectionRect: selectionRect)
            case .failed(let message):
                RuntimeLog.write("capture-result-failed \(message)")
                self.captureController = nil
                self.restoreAppWindowsAfterCancelledCapture()
                self.ensureShortcutRegistered()
                self.showCaptureFailure(message)
            }
        }
        captureController?.show()
    }

    private func handleCapturedImage(_ image: NSImage, selectionRect: CGRect) {
        RuntimeLog.write("handle-captured-image")
        let session = TutorSession.newSession(screenshot: image)
        openTutorWindow(session: session, isLoadingOCR: true, near: selectionRect)
        let language = settingsStore.settings.ocrLanguage
        ocrRequestLifecycle.start(sessionID: session.id) { [ocrService] in
            RuntimeLog.write("ocr-start")
            return await ocrService.recognize(image: image, language: language)
        } onResult: { [weak self, weak session] document in
            guard let self, let session else { return }
            RuntimeLog.write("ocr-finished lines=\(document.lines.count)")
            session.ocrDocument = document
            session.title = SessionTitle.make(from: document.editedText)
            session.category = SessionCategory.infer(from: document.editedText)
            self.tutorWindowController?.updateSession(session, isLoadingOCR: false)
            self.tutorWindowController?.formatOCR()
        }
    }

    func openTutorWindow(session: TutorSession, isLoadingOCR: Bool = false, near selectionRect: CGRect? = nil) {
        ocrRequestLifecycle.cancel(reason: "tutor-session-opened")
        tutorWindowController?.close()
        let client = DeepSeekClient(configLoader: configLoader, settingsStore: settingsStore)
        let viewModel = TutorViewModel(
            session: session,
            isLoadingOCR: isLoadingOCR,
            settingsStore: settingsStore,
            historyStore: historyStore,
            deepSeekClient: client,
            promptBuilder: promptBuilder,
            onRecapture: { [weak self] in self?.beginCapture() },
            onSettings: { [weak self] in self?.showSettings() },
            onClose: { [weak self] in self?.tutorWindowController?.close() }
        )
        tutorWindowController = TutorWindowController(viewModel: viewModel) { [weak self] in
            self?.ocrRequestLifecycle.cancel(reason: "tutor-window-closed")
            self?.tutorWindowController = nil
        }
        tutorWindowController?.show(near: selectionRect)
    }

    func showSettings() {
        settingsWindowController?.close()
        let viewModel = SettingsViewModel(settingsStore: settingsStore, configLoader: configLoader, historyStore: historyStore) { [weak self] in
            self?.shortcutManager?.unregister()
            self?.shortcutManager = ShortcutManager(settings: self?.settingsStore.settings ?? AppSettings()) { [weak self] in
                Task { @MainActor in self?.beginCapture() }
            }
            self?.settingsStore.shortcutRegistrationResult = self?.shortcutManager?.register() ?? .unregistered
            self?.menuBarController?.refresh()
        }
        settingsWindowController = SettingsWindowController(viewModel: viewModel) { [weak self] in
            self?.settingsWindowController = nil
        }
        settingsWindowController?.show()
    }

    func showHistory() {
        historyWindowController?.close()
        let viewModel = HistoryViewModel(settingsStore: settingsStore, historyStore: historyStore) { [weak self] session in
            self?.openTutorWindow(session: session)
        }
        historyWindowController = HistoryWindowController(viewModel: viewModel)
        historyWindowController?.show()
    }

    func recentSessions(limit: Int) -> [TutorSession] {
        Array(historyStore.sessions.prefix(limit))
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func ensureShortcutRegistered() {
        guard settingsStore.shortcutRegistrationResult.isRegistered else {
            settingsStore.shortcutRegistrationResult = shortcutManager?.register() ?? .unregistered
            return
        }
    }

    private func requestPermissionsFromApp() {
        _ = PermissionService.requestScreenCapturePermission()
        PermissionService.requestAccessibilityPermission()
        PermissionService.openPrivacySettings()
        showSettings()
    }

    private func writeDiagnosticsFromApp() {
        let config = configLoader.currentConfig(settings: settingsStore.settings)
        let settings = settingsStore.settings
        let shortcut = settingsStore.shortcutRegistrationResult
        Task {
            let items = await DiagnosticsService.runWithCaptureProbe(settings: settings, shortcut: shortcut, config: config)
            let lines = ["Runtime=\(RuntimeLog.runtimeIdentity())"] + items.map { "\($0.title)=\($0.state.rawValue) \($0.detail)" }
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".tutorclip", isDirectory: true)
            let file = directory.appendingPathComponent("diagnostics.txt")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func hideAppWindowsForCapture() {
        captureHiddenWindows = NSApp.windows.filter { window in
            window.isVisible && !(window is CaptureOverlayWindow)
        }
        captureHiddenWindows.forEach { $0.orderOut(nil) }
    }

    private func restoreAppWindowsAfterCancelledCapture() {
        restoreAppWindowsAfterCapture()
    }

    private func restoreAppWindowsAfterCapture() {
        let windows = captureHiddenWindows
        captureHiddenWindows.removeAll()
        windows.forEach { $0.orderFront(nil) }
    }

    private func showCaptureFailure(_ message: String) {
        let language = settingsStore.settings.appLanguage
        let alert = NSAlert()
        alert.messageText = language.text("截图失败", "Screenshot failed")
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showScreenCapturePermissionRequired() {
        let language = settingsStore.settings.appLanguage
        let alert = NSAlert()
        alert.messageText = language.text("需要屏幕录制权限", "Screen Recording permission is required")
        alert.informativeText = language.text(
            "TutorClip 需要屏幕录制权限，才能用 Shift + Command + O 截取选中区域。",
            "TutorClip needs Screen Recording permission before Shift + Command + O can capture a selected region."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: language.text("打开隐私设置", "Open Privacy Settings"))
        alert.addButton(withTitle: language.text("取消", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionService.openPrivacySettings()
        }
    }

    private func handleLaunchMarkers() {
        if consumeLaunchMarker(named: "request-permissions") {
            requestPermissionsFromApp()
        }
        if consumeLaunchMarker(named: "write-diagnostics") {
            writeDiagnosticsFromApp()
        }
        let hasCommandLineDemo = CommandLine.arguments.contains("--demo-session")
        let shouldOpenCommandLineDemo = hasCommandLineDemo && !didHandleCommandLineDemo
        didHandleCommandLineDemo = didHandleCommandLineDemo || hasCommandLineDemo
        if shouldOpenCommandLineDemo || consumeLaunchMarker(named: "launch-demo") {
            openTutorWindow(session: DemoSessionFactory.make())
        }
    }

    private func consumeLaunchMarker(named name: String) -> Bool {
        let marker = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tutorclip", isDirectory: true)
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: marker.path) else { return false }
        try? FileManager.default.removeItem(at: marker)
        return true
    }
}

struct CaptureGenerationTracker {
    private(set) var currentID: UUID?

    mutating func start() -> UUID {
        let id = UUID()
        currentID = id
        return id
    }

    mutating func accept(_ id: UUID) -> Bool {
        guard currentID == id else { return false }
        currentID = nil
        return true
    }

    mutating func invalidate() {
        currentID = nil
    }
}
