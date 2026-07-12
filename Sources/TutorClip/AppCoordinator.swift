import AppKit
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    let settingsStore: SettingsStore
    let configLoader: ConfigLoader
    let historyStore: HistoryStore
    let masteryEvidenceStore: MasteryEvidenceStore
    let ocrService: OCRService
    let promptBuilder: PromptBuilder
    private let ocrRequestLifecycle = OCRRequestLifecycle()
    let teachingScheduler: TeachingScheduler

    private var menuBarController: MenuBarController?
    private var shortcutManager: ShortcutManager?
    private var captureController: CaptureOverlayController?
    var tutorWindowController: TutorWindowController?
    private var tutorWindowControllerID: UUID?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var launchMarkerTimer: Timer?
    var didHandleCommandLineDemo = false
    private var captureHiddenWindows: [NSWindow] = []
    private var captureGeneration = CaptureGenerationTracker()
    var pendingReviewSessions: [TutorSession] = []

    init() {
        #if DEBUG
        let testDirectory = ProcessInfo.processInfo.environment["TUTORCLIP_UI_TEST_DIRECTORY"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        #else
        let testDirectory: URL? = nil
        #endif
        settingsStore = SettingsStore(baseDirectory: testDirectory)
        configLoader = ConfigLoader()
        historyStore = HistoryStore(baseDirectory: testDirectory)
        masteryEvidenceStore = MasteryEvidenceStore(baseDirectory: testDirectory)
        ocrService = OCRService()
        promptBuilder = PromptBuilder()
        teachingScheduler = TeachingScheduler()
        #if DEBUG
        if isUITesting {
            settingsStore.update { $0.hasCompletedOnboarding = true }
        }
        #endif
    }

    func start() {
        #if DEBUG
        RuntimeLog.write("coordinator-start uiTesting=\(isUITesting) testDirectory=\(ProcessInfo.processInfo.environment["TUTORCLIP_UI_TEST_DIRECTORY"] ?? "nil")")
        #else
        RuntimeLog.write("coordinator-start")
        #endif
        masteryEvidenceStore.open { [weak self] in
            self?.historyStore.open { [weak self] in
                #if DEBUG
                if let self, self.isUITesting {
                    let session = DemoSessionFactory.makeUITest()
                    RuntimeLog.write("ui-test-fixture-open chars=\(session.ocrDocument.editedText.count) answers=\(TutorQuestionParsing.answerChoices(from: session.ocrDocument.editedText).joined())")
                    self.masteryEvidenceStore.record(session: session, enabled: true)
                    self.openTutorWindow(session: session)
                    return
                }
                #endif
                guard let self, self.settingsStore.settings.hasCompletedOnboarding,
                      !CommandLine.arguments.contains("--demo-session"), self.tutorWindowController == nil else { return }
                let legacy = self.historyStore.sessions
                if self.masteryEvidenceStore.evidence.isEmpty,
                   self.settingsStore.settings.learningProgressEnabled,
                   !legacy.isEmpty {
                    var remaining = legacy.count
                    for session in legacy {
                        self.masteryEvidenceStore.record(session: session, enabled: true) { [weak self] _ in
                            remaining -= 1
                            if remaining == 0 { self?.startTodayPractice() }
                        }
                    }
                    return
                }
                self.startTodayPractice()
            }
        }
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

    #if DEBUG
    private var isUITesting: Bool {
        ProcessInfo.processInfo.environment["TUTORCLIP_UI_TEST"] == "1"
    }
    #endif

    func shutdown() {
        RuntimeLog.write("coordinator-shutdown")
        tutorWindowController?.persistBeforeAppTermination()
        ocrRequestLifecycle.cancel(reason: "app-shutdown")
        captureController?.cancel()
        captureController = nil
        captureGeneration.invalidate()
        launchMarkerTimer?.invalidate()
        shortcutManager?.unregister()
        // App termination must not return while queued privacy-safe text and
        // learning writes are still pending, or macOS may end the process first.
        historyStore.closeAndWait()
        masteryEvidenceStore.closeAndWait()
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
        captureController = CaptureOverlayController(appLanguage: settingsStore.settings.appLanguage) { [weak self] result in
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
            RuntimeLog.write("ocr-finished lines=\(document.lines.count) appActive=\(NSApp.isActive)")
            session.ocrDocument = document
            session.title = SessionTitle.make(from: document.editedText)
            session.category = SessionCategory.infer(from: document.editedText)
            self.tutorWindowController?.updateSession(session, isLoadingOCR: false)
            self.tutorWindowController?.formatOCR()
        }
    }

    func openTutorWindow(session: TutorSession, isLoadingOCR: Bool = false, near selectionRect: CGRect? = nil) {
        ocrRequestLifecycle.cancel(reason: "tutor-session-opened")
        if let tutorWindowController {
            tutorWindowController.updateSession(session, isLoadingOCR: isLoadingOCR)
            tutorWindowController.show()
            return
        }
        let client = DeepSeekClient(configLoader: configLoader, settingsStore: settingsStore)
        let viewModel = TutorViewModel(
            session: session,
            isLoadingOCR: isLoadingOCR,
            settingsStore: settingsStore,
            historyStore: historyStore,
            masteryEvidenceStore: masteryEvidenceStore,
            deepSeekClient: client,
            promptBuilder: promptBuilder,
            onRecapture: { [weak self] in self?.beginCapture() },
            onSettings: { [weak self] in self?.showSettings() },
            onKnowledgeMap: { [weak self] in self?.showKnowledgeMap() },
            onNextQuestion: { [weak self] in self?.openNextAdaptiveQuestion() },
            onClose: { [weak self] in self?.tutorWindowController?.close() }
        )
        let historyViewModel = HistoryViewModel(
            settingsStore: settingsStore,
            historyStore: historyStore,
            masteryEvidenceStore: masteryEvidenceStore,
            onOpen: { [weak self] session in self?.openTutorWindow(session: session) },
            onPracticeSkill: { [weak self] profile in self?.startSkillPractice(profile) },
            onPracticeKnowledgePoint: { [weak self] profile in self?.startKnowledgePointPractice(profile) },
            onStartReview: { [weak self] sessions, limit in self?.startReviewQueue(sessions, limit: limit) }
        )
        let controllerID = UUID()
        tutorWindowControllerID = controllerID
        tutorWindowController = TutorWindowController(
            viewModel: viewModel,
            historyViewModel: historyViewModel,
            onStartToday: { [weak self] in self?.startTodayPractice() },
            onStartChallenge: { [weak self] in self?.startChallengePractice() },
            onCapture: { [weak self] in self?.beginCapture() },
            onSettings: { [weak self] in self?.showSettings() }
        ) { [weak self] in
            guard let self, self.tutorWindowControllerID == controllerID else {
                RuntimeLog.write("stale-tutor-window-close-ignored")
                return
            }
            self.ocrRequestLifecycle.cancel(reason: "tutor-window-closed")
            self.tutorWindowController = nil
            self.tutorWindowControllerID = nil
            self.openNextReviewSession()
        }
        tutorWindowController?.show(near: selectionRect)
    }

    private func openNextAdaptiveQuestion() {
        #if DEBUG
        if isUITesting {
            openTutorWindow(session: DemoSessionFactory.makeUITestNext())
            return
        }
        #endif
        startTodayPractice(respectsDailyLimit: false)
    }

    func detachAndCloseTutorWindow() {
        guard let controller = tutorWindowController else { return }
        ocrRequestLifecycle.cancel(reason: "tutor-window-detached")
        tutorWindowControllerID = nil
        tutorWindowController = nil
        controller.close()
    }

    func showMainWindow() {
        if let tutorWindowController {
            tutorWindowController.show()
        } else {
            startTodayPractice()
        }
    }

    func showSettings() {
        settingsWindowController?.close()
        let viewModel = SettingsViewModel(settingsStore: settingsStore, configLoader: configLoader, historyStore: historyStore, masteryEvidenceStore: masteryEvidenceStore) { [weak self] in
            self?.shortcutManager?.unregister()
            self?.shortcutManager = ShortcutManager(settings: self?.settingsStore.settings ?? AppSettings()) { [weak self] in
                Task { @MainActor in self?.beginCapture() }
            }
            self?.settingsStore.shortcutRegistrationResult = self?.shortcutManager?.register() ?? .unregistered
            self?.menuBarController?.refresh()
        }
        weak var createdController: SettingsWindowController?
        let controller = SettingsWindowController(
            viewModel: viewModel,
            onRestartOnboarding: { [weak self] in
                self?.settingsWindowController?.requestClose()
                self?.showOnboarding()
            },
            onClose: { [weak self] in
                guard let self, self.settingsWindowController === createdController else { return }
                self.settingsWindowController = nil
            }
        )
        createdController = controller
        settingsWindowController = controller
        controller.show()
    }

    func showOnboarding() {
        onboardingWindowController?.close()
        let viewModel = makeSettingsViewModel()
        weak var createdController: OnboardingWindowController?
        let controller = OnboardingWindowController(
            viewModel: viewModel,
            onFinish: { [weak self] in
                guard let self, self.onboardingWindowController === createdController else { return }
                createdController?.close()
                self.onboardingWindowController = nil
                self.menuBarController?.refresh()
                self.startTodayPractice()
            },
            onWindowClosed: { [weak self] in
                guard let self, self.onboardingWindowController === createdController else { return }
                self.onboardingWindowController = nil
            }
        )
        createdController = controller
        onboardingWindowController = controller
        controller.show()
    }

    private func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(settingsStore: settingsStore, configLoader: configLoader, historyStore: historyStore, masteryEvidenceStore: masteryEvidenceStore) { [weak self] in
            self?.shortcutManager?.unregister()
            self?.shortcutManager = ShortcutManager(settings: self?.settingsStore.settings ?? AppSettings()) { [weak self] in
                Task { @MainActor in self?.beginCapture() }
            }
            self?.settingsStore.shortcutRegistrationResult = self?.shortcutManager?.register() ?? .unregistered
            self?.menuBarController?.refresh()
        }
    }

    func showHistory() {
        ensureWorkspaceWindow()
        tutorWindowController?.showHistory()
    }

    func showKnowledgeMap() {
        ensureWorkspaceWindow()
        tutorWindowController?.showKnowledgeMap()
    }

    private func ensureWorkspaceWindow() {
        guard tutorWindowController == nil else { return }
        let session = TutorSession.newSession(screenshot: nil)
        session.title = "TutorClip"
        openTutorWindow(session: session)
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
