import AppKit

enum CaptureResult {
    case cancelled
    case captured(NSImage, CGRect)
    case failed(String)
}

@MainActor
final class CaptureOverlayController {
    private static let overlayTimeout: TimeInterval = 20

    private var windows: [CaptureOverlayWindow] = []
    private let completion: @MainActor (CaptureResult) -> Void
    private var didComplete = false
    private var didStartCapture = false
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var timeoutTimer: Timer?
    private var captureTask: Task<Void, Never>?

    init(completion: @escaping @MainActor (CaptureResult) -> Void) {
        self.completion = completion
        RuntimeLog.write("capture-controller-init")
    }

    func show() {
        RuntimeLog.write("capture-overlay-show screens=\(NSScreen.screens.count)")
        guard !NSScreen.screens.isEmpty else {
            finish(.failed("No displays are available for screenshot capture."))
            return
        }
        startTimeoutTimer()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                RuntimeLog.write("capture-overlay-local-esc")
                self?.finish(.cancelled)
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                RuntimeLog.write("capture-overlay-global-esc")
                Task { @MainActor in self?.finish(.cancelled) }
            }
        }
        windows = NSScreen.screens.map { screen in
            let window = CaptureOverlayWindow(screen: screen) { [weak self] action in
                self?.handle(action)
            }
            window.orderFrontRegardless()
            return window
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    func cancel() {
        RuntimeLog.write("capture-controller-cancel")
        finish(.cancelled)
    }

    private func handle(_ action: CaptureOverlayAction) {
        switch action {
        case .cancelled:
            RuntimeLog.write("capture-action-cancelled")
            finish(.cancelled)
        case .selected(let selection):
            guard !didStartCapture else { return }
            didStartCapture = true
            RuntimeLog.write("capture-action-selected rect=\(selection.globalRect.debugDescription) size=\(selection.outputSize.debugDescription)")
            removeKeyMonitors()
            hideOverlayWindows()
            closeOverlayWindows()
            RuntimeLog.write("screen-capture-start")
            captureTask = Task(priority: .userInitiated) { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 120_000_000)
                    RuntimeLog.write("capture-delay-after-overlay-close-ms=120")
                } catch {
                    RuntimeLog.write("capture-delay-cancelled")
                    return
                }
                let image = await ScreenCaptureService.capture(globalRect: selection.globalRect, outputSize: selection.outputSize)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.completeCapture(with: image, selectionRect: selection.globalRect)
                }
            }
        }
    }

    private func finish(_ result: CaptureResult) {
        guard !didComplete else { return }
        didComplete = true
        RuntimeLog.write("capture-finish")
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        captureTask?.cancel()
        captureTask = nil
        removeKeyMonitors()
        closeOverlayWindows()
        completion(result)
    }

    private func removeKeyMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    private func hideOverlayWindows() {
        RuntimeLog.write("capture-hide-overlay-windows count=\(windows.count)")
        windows.forEach { $0.orderOut(nil) }
    }

    private func closeOverlayWindows() {
        RuntimeLog.write("capture-close-overlay-windows count=\(windows.count)")
        windows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    private func startTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: Self.overlayTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                RuntimeLog.write("capture-overlay-timeout")
                self?.finish(.failed("Screenshot selection timed out and was cancelled."))
            }
        }
    }

    private func completeCapture(with image: NSImage?, selectionRect: CGRect) {
        guard let image else {
            finish(.failed("ScreenCaptureKit did not return an image for the selected region."))
            return
        }
        RuntimeLog.write("screen-capture-finished")
        finish(.captured(image, selectionRect))
    }
}
