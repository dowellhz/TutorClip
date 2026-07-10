import AppKit
@preconcurrency import Vision

final class OCRService {
    private let layoutService = OCRLayoutService()
    private let imageProcessor = OCRImageProcessor()

    func recognize(image: NSImage, language: OCRLanguage) async -> OCRDocument {
        guard let sourceImage = image.sourceCGImageForOCR() else {
            return OCRDocument.empty()
        }
        guard !Task.isCancelled else { return OCRDocument.empty() }
        let cgImage = await imageProcessor.prepare(sourceImage)
        guard !Task.isCancelled else { return OCRDocument.empty() }
        RuntimeLog.write("ocr-input-pixels \(cgImage.width)x\(cgImage.height)")
        let operation = OCRRecognitionOperation()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { [layoutService] request, _ in
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let document = layoutService.makeDocument(observations: observations, language: language)
                    operation.complete(with: document)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let languages = language.recognitionLanguages
                if !languages.isEmpty {
                    request.recognitionLanguages = languages
                }

                guard operation.install(continuation: continuation, request: request) else {
                    continuation.resume(returning: OCRDocument.empty())
                    return
                }
                let handler = VNImageRequestHandler(cgImage: cgImage)
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try handler.perform([request])
                    } catch {
                        operation.complete(with: OCRDocument.empty())
                    }
                }
            }
        } onCancel: {
            operation.cancel()
        }
    }
}

actor OCRImageProcessor {
    func prepare(_ image: CGImage) -> CGImage {
        image.upscaledForOCR()
    }
}

private final class OCRRecognitionOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<OCRDocument, Never>?
    private var request: VNRecognizeTextRequest?
    private var wasCancelled = false

    func install(
        continuation: CheckedContinuation<OCRDocument, Never>,
        request: VNRecognizeTextRequest
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !wasCancelled else { return false }
        self.continuation = continuation
        self.request = request
        return true
    }

    func complete(with document: OCRDocument) {
        lock.lock()
        let pending = continuation
        continuation = nil
        request = nil
        lock.unlock()
        pending?.resume(returning: document)
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let pending = continuation
        let activeRequest = request
        continuation = nil
        request = nil
        lock.unlock()

        activeRequest?.cancel()
        pending?.resume(returning: OCRDocument.empty())
        RuntimeLog.write("ocr-vision-request-cancelled")
    }
}

private extension NSImage {
    func sourceCGImageForOCR() -> CGImage? {
        if let best = representations
            .compactMap({ $0.cgImage(forProposedRect: nil, context: nil, hints: nil) })
            .max(by: { $0.width * $0.height < $1.width * $1.height }) {
            return best
        }
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

private extension CGImage {
    func upscaledForOCR() -> CGImage {
        let targetWidth = 2400
        guard width > 0, height > 0 else { return paddedForOCR() }
        guard width < targetWidth else { return paddedForOCR() }

        let scale = min(3, max(1, targetWidth / width))
        guard scale > 1 else { return paddedForOCR() }

        let scaledWidth = width * scale
        let scaledHeight = height * scale
        guard let colorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: scaledWidth,
                height: scaledHeight,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return self
        }

        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
        return context.makeImage()?.paddedForOCR() ?? paddedForOCR()
    }

    private func paddedForOCR() -> CGImage {
        let padding = 24
        let paddedWidth = width + padding * 2
        let paddedHeight = height + padding * 2
        guard let colorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: paddedWidth,
                height: paddedHeight,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return self
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: paddedWidth, height: paddedHeight))
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: padding, y: padding, width: width, height: height))
        return context.makeImage() ?? self
    }
}
