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
    private var onboardingWindowController: OnboardingWindowController?
    private var historyWindowController: HistoryWindowController?
    private var knowledgeMapWindowController: KnowledgeMapWindowController?
    private var launchMarkerTimer: Timer?
    private var didHandleCommandLineDemo = false
    private var captureHiddenWindows: [NSWindow] = []
    private var captureGeneration = CaptureGenerationTracker()
    private var pendingReviewSessions: [TutorSession] = []

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
        if !settingsStore.settings.hasCompletedOnboarding {
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
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
        pendingReviewSessions = []
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
            onKnowledgeMap: { [weak self] in self?.showKnowledgeMap() },
            onClose: { [weak self] in self?.tutorWindowController?.close() }
        )
        tutorWindowController = TutorWindowController(viewModel: viewModel) { [weak self] in
            self?.ocrRequestLifecycle.cancel(reason: "tutor-window-closed")
            self?.tutorWindowController = nil
            self?.openNextReviewSession()
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
        settingsWindowController = SettingsWindowController(
            viewModel: viewModel,
            onRestartOnboarding: { [weak self] in
                self?.settingsWindowController?.requestClose()
                self?.showOnboarding()
            },
            onClose: { [weak self] in self?.settingsWindowController = nil }
        )
        settingsWindowController?.show()
    }

    func showOnboarding() {
        onboardingWindowController?.close()
        let viewModel = makeSettingsViewModel()
        onboardingWindowController = OnboardingWindowController(
            viewModel: viewModel,
            onFinish: { [weak self] in
                self?.onboardingWindowController?.close()
                self?.onboardingWindowController = nil
                self?.menuBarController?.refresh()
            },
            onWindowClosed: { [weak self] in
                self?.onboardingWindowController = nil
            }
        )
        onboardingWindowController?.show()
    }

    private func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(settingsStore: settingsStore, configLoader: configLoader, historyStore: historyStore) { [weak self] in
            self?.shortcutManager?.unregister()
            self?.shortcutManager = ShortcutManager(settings: self?.settingsStore.settings ?? AppSettings()) { [weak self] in
                Task { @MainActor in self?.beginCapture() }
            }
            self?.settingsStore.shortcutRegistrationResult = self?.shortcutManager?.register() ?? .unregistered
            self?.menuBarController?.refresh()
        }
    }

    func showHistory() {
        historyWindowController?.close()
        let viewModel = HistoryViewModel(settingsStore: settingsStore, historyStore: historyStore) { [weak self] session in
            self?.pendingReviewSessions = []
            self?.openTutorWindow(session: session)
        } onPracticeSkill: { [weak self] profile in
            self?.startSkillPractice(profile)
        } onStartReview: { [weak self] sessions, limit in
            self?.startReviewQueue(sessions, limit: limit)
        }
        historyWindowController = HistoryWindowController(viewModel: viewModel)
        historyWindowController?.show()
    }

    func showKnowledgeMap() {
        knowledgeMapWindowController?.close()
        let viewModel = HistoryViewModel(settingsStore: settingsStore, historyStore: historyStore, onOpen: { _ in }, onPracticeKnowledgePoint: { [weak self] profile in
            self?.startKnowledgePointPractice(profile)
        })
        knowledgeMapWindowController = KnowledgeMapWindowController(viewModel: viewModel)
        knowledgeMapWindowController?.show()
    }

    private func startKnowledgePointPractice(_ profile: SATKnowledgePointProfile) {
        guard let type = SATKnowledgeCatalog.questionType(id: profile.definition.questionTypeID) else { return }
        pendingReviewSessions = []
        let difficulty: SATDifficulty = profile.state == .pendingVerification ? .medium : .easy
        let target = "SAT targeted example. Question type: \(type.titleEN). Knowledge point: \(profile.definition.titleEN) [\(profile.id)]. Difficulty: \(difficulty.rawValue)."
        var document = OCRDocument.empty()
        document.fullText = target
        document.editedText = target
        let session = TutorSession.newSession(screenshot: nil)
        session.ocrDocument = document
        session.title = profile.definition.titleZH
        session.category = type.domain == "Standard English Conventions" ? .grammar : .reading
        session.learningMetadata.section = .readingWriting
        session.learningMetadata.domain = type.domain
        session.learningMetadata.skill = type.skill
        session.learningMetadata.questionTypeID = type.id
        session.learningMetadata.knowledgePointIDs = [profile.id]
        session.learningMetadata.difficulty = difficulty
        openTutorWindow(session: session)
        tutorWindowController?.generatePracticeQuestion()
    }

    private func startSkillPractice(_ profile: SATSkillProfile) {
        pendingReviewSessions = []
        var document = OCRDocument.empty()
        let target = "SAT targeted practice. Section: \(profile.section.rawValue). Domain: \(profile.domain). Skill: \(profile.skill). Difficulty: \(profile.recommendedDifficulty.rawValue)."
        document.fullText = target
        document.editedText = target
        let session = TutorSession.newSession(screenshot: nil)
        session.ocrDocument = document
        session.title = profile.skill
        session.category = profile.section == .math ? .math : .reading
        session.learningMetadata.section = profile.section
        session.learningMetadata.domain = profile.domain
        session.learningMetadata.skill = profile.skill
        session.learningMetadata.difficulty = profile.recommendedDifficulty
        openTutorWindow(session: session)
        tutorWindowController?.generatePracticeQuestion()
    }

    private func startReviewQueue(_ sessions: [TutorSession], limit: Int) {
        tutorWindowController?.close()
        pendingReviewSessions = Array(sessions.prefix(limit))
        openNextReviewSession()
    }

    private func openNextReviewSession() {
        guard !pendingReviewSessions.isEmpty else { return }
        openTutorWindow(session: pendingReviewSessions.removeFirst())
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
