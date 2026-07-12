import AppKit

final class CaptureOverlayWindow: NSWindow {
    init(screen: NSScreen, appLanguage: AppLanguage, completion: @escaping (CaptureOverlayAction) -> Void) {
        let content = CaptureOverlayView(screen: screen, appLanguage: appLanguage, completion: completion)
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        contentView = content
    }

    override var canBecomeKey: Bool { true }
}

final class CaptureOverlayView: NSView {
    private let targetScreen: NSScreen
    private let completion: (CaptureOverlayAction) -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var finalizedRect: CGRect?
    private var dragMode: DragMode = .none
    private var dragStartPoint: CGPoint?
    private var dragStartRect: CGRect?
    private let appLanguage: AppLanguage

    init(screen: NSScreen, appLanguage: AppLanguage, completion: @escaping (CaptureOverlayAction) -> Void) {
        targetScreen = screen
        self.appLanguage = appLanguage
        self.completion = completion
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard let rect = selectionRect else { return }
        NSColor.windowBackgroundColor.withAlphaComponent(0.08).setFill()
        rect.fill()

        NSColor.systemTeal.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()

        drawHandles(for: rect)
        drawHelpText(near: rect)
    }

    override func mouseDown(with event: NSEvent) {
        completion(.interaction)
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, finalizedRect != nil {
            RuntimeLog.write("capture-confirm-trigger double-click")
            confirmSelection()
            return
        }

        if let rect = finalizedRect {
            dragMode = hitTestMode(at: point, in: rect)
            if dragMode == .creating {
                finalizedRect = nil
                startPoint = point
                currentPoint = point
                dragStartPoint = nil
                dragStartRect = nil
            } else {
                dragStartPoint = point
                dragStartRect = rect
            }
        } else {
            dragMode = .creating
            startPoint = point
            currentPoint = point
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let dragStartPoint, let dragStartRect, finalizedRect != nil {
            finalizedRect = adjustedRect(
                from: dragStartRect,
                mode: dragMode,
                delta: CGPoint(x: point.x - dragStartPoint.x, y: point.y - dragStartPoint.y)
            )
        } else {
            currentPoint = point
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        completion(.interaction)
        if dragMode == .creating {
            currentPoint = convert(event.locationInWindow, from: nil)
            guard let rect = selectionRect, rect.width > 8, rect.height > 8 else {
                RuntimeLog.write("capture-mouse-up-small-selection")
                resetSelection()
                return
            }
            finalizedRect = rect.integral
            dragMode = .none
            dragStartPoint = nil
            dragStartRect = nil
            RuntimeLog.write("capture-mouse-up-finalized-awaiting-confirmation rect=\(finalizedRect?.debugDescription ?? "nil")")
            needsDisplay = true
            return
        }
        RuntimeLog.write("capture-adjust-finished mode=\(String(describing: dragMode)) rect=\(finalizedRect?.debugDescription ?? "nil")")
        dragMode = .none
        dragStartPoint = nil
        dragStartRect = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            RuntimeLog.write("capture-view-key-esc")
            completion(.cancelled)
            return
        }
        if event.keyCode == 36 {
            RuntimeLog.write("capture-confirm-trigger return")
            confirmSelection()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        completion(.cancelled)
    }

    private var selectionRect: CGRect? {
        if let finalizedRect { return finalizedRect }
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func confirmSelection() {
        guard let rect = selectionRect, rect.width > 8, rect.height > 8 else {
            NSSound.beep()
            return
        }
        let paddedRect = paddedSelectionRect(rect).integral
        let globalRect = globalCaptureRect(from: paddedRect).integral
        RuntimeLog.write("capture-confirm rect=\(rect.debugDescription) padded=\(paddedRect.debugDescription) bounds=\(bounds.debugDescription) window=\(window?.frame.debugDescription ?? "nil") global=\(globalRect.debugDescription)")
        completion(.selected(CaptureSelection(globalRect: globalRect, outputSize: paddedRect.size)))
    }

    private func resetSelection() {
        startPoint = nil
        currentPoint = nil
        finalizedRect = nil
        dragMode = .none
        dragStartPoint = nil
        dragStartRect = nil
        needsDisplay = true
    }

    private func drawHandles(for rect: CGRect) {
        NSColor.systemTeal.setFill()
        for handle in Handle.allCases {
            NSBezierPath(roundedRect: handleRect(for: handle, in: rect), xRadius: 3, yRadius: 3).fill()
        }
    }

    private func drawHelpText(near rect: CGRect) {
        let text: String
        if finalizedRect == nil {
            text = appLanguage.text("拖动以选择区域", "Drag to select")
        } else {
            text = appLanguage.text(
                "拖动边缘调整 · 回车截图 · Esc 取消",
                "Drag edges to adjust · Return to capture · Esc to cancel"
            )
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.45)
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: rect.minX, y: max(12, rect.minY - size.height - 12))
        text.draw(at: origin, withAttributes: attributes)
    }

    private func hitTestMode(at point: CGPoint, in rect: CGRect) -> DragMode {
        for handle in Handle.allCases where handleRect(for: handle, in: rect).insetBy(dx: -4, dy: -4).contains(point) {
            return .resizing(handle)
        }
        return rect.contains(point) ? .moving : .creating
    }

    private func handleRect(for handle: Handle, in rect: CGRect) -> CGRect {
        let size: CGFloat = 9
        let center: CGPoint
        switch handle {
        case .topLeft: center = CGPoint(x: rect.minX, y: rect.minY)
        case .top: center = CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: center = CGPoint(x: rect.maxX, y: rect.minY)
        case .right: center = CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: center = CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: center = CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: center = CGPoint(x: rect.minX, y: rect.maxY)
        case .left: center = CGPoint(x: rect.minX, y: rect.midY)
        }
        return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    private func adjustedRect(from rect: CGRect, mode: DragMode, delta: CGPoint) -> CGRect {
        var next = rect
        switch mode {
        case .none:
            break
        case .creating:
            currentPoint = CGPoint(x: (startPoint?.x ?? 0) + delta.x, y: (startPoint?.y ?? 0) + delta.y)
        case .moving:
            next.origin.x += delta.x
            next.origin.y += delta.y
        case .resizing(let handle):
            if handle.affectsLeft { next.origin.x += delta.x; next.size.width -= delta.x }
            if handle.affectsRight { next.size.width += delta.x }
            if handle.affectsTop { next.origin.y += delta.y; next.size.height -= delta.y }
            if handle.affectsBottom { next.size.height += delta.y }
        }
        next = normalize(rect: next)
        next.origin.x = min(max(next.origin.x, 0), bounds.width - next.width)
        next.origin.y = min(max(next.origin.y, 0), bounds.height - next.height)
        return next
    }

    private func normalize(rect: CGRect) -> CGRect {
        let minSize: CGFloat = 12
        var normalized = rect.standardized
        normalized.size.width = max(normalized.width, minSize)
        normalized.size.height = max(normalized.height, minSize)
        return normalized
    }

    private func globalCaptureRect(from rect: CGRect) -> CGRect {
        guard let window else {
            return CGRect(
                x: targetScreen.frame.origin.x + rect.origin.x,
                y: targetScreen.frame.origin.y + rect.origin.y,
                width: rect.width,
                height: rect.height
            )
        }
        let windowRect = convert(rect, to: nil)
        return window.convertToScreen(windowRect)
    }

    private func paddedSelectionRect(_ rect: CGRect) -> CGRect {
        rect
            .insetBy(dx: -4, dy: -4)
            .intersection(bounds)
            .standardized
    }
}

struct CaptureSelection {
    let globalRect: CGRect
    let outputSize: CGSize
}

enum CaptureOverlayAction {
    case interaction
    case cancelled
    case selected(CaptureSelection)
}

private enum DragMode: Equatable {
    case none
    case creating
    case moving
    case resizing(Handle)
}

private enum Handle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var affectsLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var affectsRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var affectsTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var affectsBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
}
