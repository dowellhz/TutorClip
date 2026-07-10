import AppKit

struct ScreenCaptureHealth: Equatable {
    enum State: Equatable {
        case unavailable
        case captured(width: Int, height: Int, looksUniform: Bool)
        case failed
    }

    var state: State
}

enum ScreenCaptureHealthService {
    static func probe() async -> ScreenCaptureHealth {
        guard PermissionService.hasScreenCapturePermission() else {
            return ScreenCaptureHealth(state: .unavailable)
        }

        let marker = await ScreenCaptureProbeMarker.show()
        if marker != nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let rect = marker?.frame ?? probeRect()
        guard let image = await ScreenCaptureService.capture(globalRect: rect, outputSize: rect.size),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            await marker?.close()
            return ScreenCaptureHealth(state: .failed)
        }
        await marker?.close()

        return ScreenCaptureHealth(
            state: .captured(
                width: cgImage.width,
                height: cgImage.height,
                looksUniform: imageLooksUniform(cgImage)
            )
        )
    }

    private static func probeRect() -> CGRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 200, height: 200)
        let size = min(96, max(24, min(visibleFrame.width, visibleFrame.height) / 8))
        return CGRect(
            x: visibleFrame.midX - size / 2,
            y: visibleFrame.midY - size / 2,
            width: size,
            height: size
        )
    }

    private static func imageLooksUniform(_ image: CGImage) -> Bool {
        guard image.width > 1, image.height > 1,
              let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return true
        }

        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let bytesPerRow = image.bytesPerRow
        let samples = samplePoints(width: image.width, height: image.height)
        guard let first = colorSignature(bytes: bytes, bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel, x: samples[0].x, y: samples[0].y) else {
            return true
        }

        for point in samples.dropFirst() {
            guard let signature = colorSignature(bytes: bytes, bytesPerRow: bytesPerRow, bytesPerPixel: bytesPerPixel, x: point.x, y: point.y) else {
                continue
            }
            if colorDistance(first, signature) > 18 {
                return false
            }
        }
        return true
    }

    private static func samplePoints(width: Int, height: Int) -> [(x: Int, y: Int)] {
        [
            (width / 2, height / 2),
            (width / 4, height / 4),
            (width * 3 / 4, height / 4),
            (width / 4, height * 3 / 4),
            (width * 3 / 4, height * 3 / 4)
        ]
    }

    private static func colorSignature(bytes: UnsafePointer<UInt8>, bytesPerRow: Int, bytesPerPixel: Int, x: Int, y: Int) -> (Int, Int, Int)? {
        let offset = y * bytesPerRow + x * bytesPerPixel
        guard bytesPerPixel >= 3 else { return nil }
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    private static func colorDistance(_ lhs: (Int, Int, Int), _ rhs: (Int, Int, Int)) -> Int {
        abs(lhs.0 - rhs.0) + abs(lhs.1 - rhs.1) + abs(lhs.2 - rhs.2)
    }
}

@MainActor
private final class ScreenCaptureProbeMarker {
    let frame: CGRect
    private let window: NSWindow

    private init(frame: CGRect, window: NSWindow) {
        self.frame = frame
        self.window = window
    }

    static func show() -> ScreenCaptureProbeMarker? {
        guard NSApplication.shared.isRunning else { return nil }
        let frame = markerFrame()
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = ScreenCaptureProbeMarkerView(frame: CGRect(origin: .zero, size: frame.size))
        window.orderFrontRegardless()
        window.displayIfNeeded()
        return ScreenCaptureProbeMarker(frame: frame, window: window)
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    private static func markerFrame() -> CGRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 240, height: 240)
        let width = min(160, max(80, visibleFrame.width / 8))
        let height = min(120, max(60, visibleFrame.height / 8))
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}

private final class ScreenCaptureProbeMarkerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemYellow]
        let halfWidth = bounds.width / 2
        let halfHeight = bounds.height / 2
        let rects = [
            CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight),
            CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight),
            CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight),
            CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight)
        ]
        for (color, rect) in zip(colors, rects) {
            color.setFill()
            rect.fill()
        }
    }
}
