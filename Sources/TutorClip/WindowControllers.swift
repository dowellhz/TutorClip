import AppKit
import SwiftUI

@MainActor
final class TutorWindowController: NSWindowController {
    private let viewModel: TutorViewModel
    private let router = MainWorkspaceRouter()
    private let onWindowClosed: () -> Void

    init(
        viewModel: TutorViewModel,
        historyViewModel: HistoryViewModel,
        onStartToday: @escaping () -> Void,
        onStartChallenge: @escaping () -> Void,
        onCapture: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onWindowClosed: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onWindowClosed = onWindowClosed
        let content = MainWorkspaceView(
            tutorViewModel: viewModel,
            historyViewModel: historyViewModel,
            router: router,
            onStartToday: onStartToday,
            onStartChallenge: onStartChallenge,
            onCapture: onCapture,
            onSettings: onSettings
        )
        let window = TutorMainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TutorClip"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(near selectionRect: CGRect? = nil) {
        if window?.isVisible != true {
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // One-time fronting is required after capture. The normal window level
        // still lets any subsequently selected app cover TutorClip.
        window?.orderFrontRegardless()
        RuntimeLog.write("tutor-window-fronted level=normal")
    }

    func updateSession(_ session: TutorSession, isLoadingOCR: Bool) {
        viewModel.persistBeforeReplacingSession(with: session.id)
        viewModel.replaceSession(session, isLoadingOCR: isLoadingOCR)
        router.route = .question
    }

    func showHistory() { router.route = .history; show() }
    func showKnowledgeMap() { router.route = .knowledge; show() }
    func showToday() { router.route = .today; show() }

    func showDailyPracticeComplete() {
        viewModel.isDailyPracticeComplete = true
        router.route = .today
        show()
    }

    func formatOCR() {
        viewModel.formatOCR()
    }

    func generatePracticeQuestion() {
        viewModel.generatePracticeQuestion()
    }

    func persistBeforeAppTermination() {
        viewModel.closeAndPersistIfNeeded()
    }

    private func positionWindow(near selectionRect: CGRect) {
        guard let window else { return }
        let screen = screen(containing: selectionRect) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let gap: CGFloat = 16
        var frame = window.frame
        frame.size.width = min(frame.width, visibleFrame.width - gap * 2)
        frame.size.height = min(frame.height, visibleFrame.height - gap * 2)
        frame.origin = TutorWindowPositioning.origin(for: frame.size, near: selectionRect, in: visibleFrame, gap: gap)
        window.setFrame(frame, display: true)
        RuntimeLog.write("tutor-window-position-near selection=\(selectionRect.integral) frame=\(frame.integral)")
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { left, right in
            left.visibleFrame.intersection(rect).area < right.visibleFrame.intersection(rect).area
        }
    }
}

enum TutorWindowPositioning {
    static func origin(for size: CGSize, near selectionRect: CGRect, in visibleFrame: CGRect, gap: CGFloat) -> CGPoint {
        let x = clamped(selectionRect.midX - size.width / 2, min: visibleFrame.minX, max: visibleFrame.maxX - size.width)
        let y = clamped(selectionRect.midY - size.height / 2, min: visibleFrame.minY, max: visibleFrame.maxY - size.height)
        let belowY = selectionRect.minY - size.height - gap
        if belowY >= visibleFrame.minY {
            return CGPoint(x: x, y: belowY)
        }

        let aboveY = selectionRect.maxY + gap
        if aboveY + size.height <= visibleFrame.maxY {
            return CGPoint(x: x, y: aboveY)
        }

        let rightX = selectionRect.maxX + gap
        if rightX + size.width <= visibleFrame.maxX {
            return CGPoint(x: rightX, y: y)
        }

        let leftX = selectionRect.minX - size.width - gap
        if leftX >= visibleFrame.minX {
            return CGPoint(x: leftX, y: y)
        }

        return bestFallbackOrigin(for: size, near: selectionRect, in: visibleFrame, gap: gap)
    }

    private static func bestFallbackOrigin(for size: CGSize, near selectionRect: CGRect, in visibleFrame: CGRect, gap: CGFloat) -> CGPoint {
        let candidates = [
            CGPoint(x: selectionRect.midX - size.width / 2, y: selectionRect.minY - size.height - gap),
            CGPoint(x: selectionRect.midX - size.width / 2, y: selectionRect.maxY + gap),
            CGPoint(x: selectionRect.maxX + gap, y: selectionRect.midY - size.height / 2),
            CGPoint(x: selectionRect.minX - size.width - gap, y: selectionRect.midY - size.height / 2)
        ].map { point in
            CGPoint(
                x: clamped(point.x, min: visibleFrame.minX, max: visibleFrame.maxX - size.width),
                y: clamped(point.y, min: visibleFrame.minY, max: visibleFrame.maxY - size.height)
            )
        }

        return candidates.min { left, right in
            let leftFrame = CGRect(origin: left, size: size)
            let rightFrame = CGRect(origin: right, size: size)
            let leftOverlap = leftFrame.intersection(selectionRect).area
            let rightOverlap = rightFrame.intersection(selectionRect).area
            if leftOverlap != rightOverlap {
                return leftOverlap < rightOverlap
            }
            return distance(from: leftFrame, to: selectionRect) < distance(from: rightFrame, to: selectionRect)
        } ?? CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
    }

    private static func distance(from frame: CGRect, to rect: CGRect) -> CGFloat {
        hypot(frame.midX - rect.midX, frame.midY - rect.midY)
    }

    private static func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(value, maxValue))
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

extension TutorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        viewModel.closeAndPersistIfNeeded()
        onWindowClosed()
    }
}

private final class TutorMainWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if WindowKeyboardPolicy.shouldClose(modifierFlags: event.modifierFlags, keyCode: event.keyCode) {
            performClose(nil)
            return
        }
        if event.keyCode == 53 {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard WindowKeyboardPolicy.shouldClose(
            modifierFlags: event.modifierFlags,
            keyCode: event.keyCode
        ) else {
            return super.performKeyEquivalent(with: event)
        }
        performClose(nil)
        return true
    }

    override func cancelOperation(_ sender: Any?) {
    }
}

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(viewModel: SettingsViewModel, onFinish: @escaping () -> Void, onWindowClosed: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 570),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TutorClip Setup"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(viewModel: viewModel, onFinish: onFinish))
        super.init(window: window)
        let delegate = ClosureWindowDelegate(onClose: onWindowClosed)
        window.delegate = delegate
        retainedDelegate = delegate
    }

    private var retainedDelegate: NSWindowDelegate?

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class ClosureWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

final class SettingsWindowController: NSWindowController {
    private let onClose: () -> Void
    private let viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel, onRestartOnboarding: @escaping () -> Void = {}, onClose: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onClose = onClose
        let window = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TutorClip Help & Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(
            viewModel: viewModel,
            onClose: { [weak self] in self?.requestClose() },
            onRestartOnboarding: onRestartOnboarding
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func requestClose() {
        guard let window else { return }
        viewModel.cancelDiagnostics()
        window.performClose(nil)
        if window.isVisible {
            window.orderOut(nil)
            onClose()
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        viewModel.cancelDiagnostics()
        onClose()
    }
}

private final class SettingsPanel: NSWindow {
    override func keyDown(with event: NSEvent) {
        if WindowKeyboardPolicy.shouldClose(modifierFlags: event.modifierFlags, keyCode: event.keyCode) {
            performClose(nil)
            return
        }
        super.keyDown(with: event)
    }


    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard WindowKeyboardPolicy.shouldClose(
            modifierFlags: event.modifierFlags,
            keyCode: event.keyCode
        ) else {
            return super.performKeyEquivalent(with: event)
        }
        performClose(nil)
        return true
    }
}

enum WindowKeyboardPolicy {
    static func shouldClose(modifierFlags: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        modifierFlags.contains(.command) && keyCode == 13
    }
}
