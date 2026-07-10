import AppKit
import ScreenCaptureKit

enum ScreenCaptureService {
    private static let captureTimeout: TimeInterval = 5

    static func capture(globalRect: CGRect, outputSize: CGSize) async -> NSImage? {
        RuntimeLog.write("screen-capture-service-capture")
        guard let target = captureTarget(for: globalRect) else {
            RuntimeLog.write("screen-capture-service-no-appkit-screen")
            return nil
        }
        RuntimeLog.write(
            "screen-capture-service-target appkit=\(globalRect.debugDescription) id=\(target.displayID) source=\(target.sourceRect.debugDescription)"
        )
        let outcome = await AsyncTimeoutRace.run(
            timeoutNanoseconds: UInt64(captureTimeout * 1_000_000_000)
        ) {
            await captureWithoutOuterTimeout(target: target, outputSize: outputSize)
        }
        switch outcome {
        case .value(let image):
            return image
        case .timedOut:
            RuntimeLog.write("screen-capture-service-outer-timeout")
            return nil
        case .cancelled:
            RuntimeLog.write("screen-capture-service-cancelled")
            return nil
        }
    }

    private static func captureWithoutOuterTimeout(target: ScreenCaptureTarget, outputSize: CGSize) async -> NSImage? {
        return await captureDisplayRegion(target: target, outputSize: outputSize)
    }

    private static func captureDisplayRegion(target: ScreenCaptureTarget, outputSize: CGSize) async -> NSImage? {
        do {
            RuntimeLog.write("screen-capture-service-display-region")
            let content = try await SCShareableContent.current
            guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
                RuntimeLog.write("screen-capture-service-no-display")
                return nil
            }

            let config = SCStreamConfiguration()
            config.sourceRect = target.sourceRect
            config.width = max(1, Int(target.sourceRect.width * target.scale))
            config.height = max(1, Int(target.sourceRect.height * target.scale))
            config.showsCursor = false
            RuntimeLog.write(
                "screen-capture-service-display-selected id=\(display.displayID) frame=\(display.frame.debugDescription) source=\(target.sourceRect.debugDescription) scale=\(target.scale) config=\(config.width)x\(config.height)"
            )

            let filter = SCContentFilter(display: display, excludingWindows: [])
            return await withTimedImageContinuation { continuation in
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                    RuntimeLog.write("screen-capture-service-filter-callback image=\(image != nil)")
                    guard let image else {
                        _ = continuation.resume(returning: nil)
                        return
                    }
                    _ = continuation.resume(returning: nsImage(from: image))
                }
            }
        } catch {
            RuntimeLog.write("screen-capture-service-error \(error.localizedDescription)")
            return nil
        }
    }

    private static func withTimedImageContinuation(
        _ body: @escaping (CaptureContinuationBox<NSImage?>) -> Void
    ) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let box = CaptureContinuationBox(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + captureTimeout) {
                if box.resume(returning: nil) {
                    RuntimeLog.write("screen-capture-service-timeout")
                }
            }
            body(box)
        }
    }

    private static func captureTarget(for appKitRect: CGRect) -> ScreenCaptureTarget? {
        guard let screen = NSScreen.screens.max(by: {
            $0.frame.intersection(appKitRect).area < $1.frame.intersection(appKitRect).area
        }),
        let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
        let sourceRect = ScreenCaptureGeometry.sourceRect(appKitRect: appKitRect, screenFrame: screen.frame) else {
            return nil
        }
        return ScreenCaptureTarget(
            displayID: displayNumber.uint32Value,
            sourceRect: sourceRect,
            scale: screen.backingScaleFactor
        )
    }

    private static func nsImage(from cgImage: CGImage) -> NSImage {
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        RuntimeLog.write("screen-capture-service-image-pixels \(cgImage.width)x\(cgImage.height)")
        return NSImage(cgImage: cgImage, size: pixelSize)
    }

}

struct ScreenCaptureTarget {
    var displayID: CGDirectDisplayID
    var sourceRect: CGRect
    var scale: CGFloat
}

enum ScreenCaptureGeometry {
    static func sourceRect(appKitRect: CGRect, screenFrame: CGRect) -> CGRect? {
        let clippedRect = appKitRect.standardized.intersection(screenFrame)
        guard !clippedRect.isNull, !clippedRect.isEmpty else { return nil }
        return CGRect(
            x: clippedRect.minX - screenFrame.minX,
            y: screenFrame.maxY - clippedRect.maxY,
            width: clippedRect.width,
            height: clippedRect.height
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

private final class CaptureContinuationBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) -> Bool {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        current?.resume(returning: value)
        return current != nil
    }
}
