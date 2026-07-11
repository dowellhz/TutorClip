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
        do {
            var request = RecognizeDocumentsRequest()
            request.textRecognitionOptions.useLanguageCorrection = true
            request.textRecognitionOptions.automaticallyDetectLanguage = language == .automatic
            request.textRecognitionOptions.recognitionLanguages = language.recognitionLanguages.map(Locale.Language.init(identifier:))
            let observations = try await request.perform(on: cgImage)
            guard !Task.isCancelled, let observation = observations.first else { return OCRDocument.empty() }
            var document = layoutService.makeDocument(observation: observation, language: language)
            OCRVisualStyleDetector.detectUnderlines(in: cgImage, document: &document)
            RuntimeLog.write("ocr-document-structure tables=\(document.structuredTables.count) lines=\(document.lines.count)")
            return document
        } catch is CancellationError {
            RuntimeLog.write("ocr-document-request-cancelled")
            return OCRDocument.empty()
        } catch {
            RuntimeLog.write("ocr-document-request-failed \(error.localizedDescription)")
            return OCRDocument.empty()
        }
    }
}

actor OCRImageProcessor {
    func prepare(_ image: CGImage) -> CGImage {
        image.upscaledForOCR()
    }
}

private enum OCRVisualStyleDetector {
    static func detectUnderlines(in image: CGImage, document: inout OCRDocument) {
        guard image.width > 0, image.height > 0 else { return }
        var pixels = [UInt8](repeating: 255, count: image.width * image.height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else { return }

        for index in document.tokens.indices {
            let box = document.tokens[index].boundingBox.cgRect
            document.tokens[index].isLikelyUnderlined = hasUnderline(
                box: box,
                pixels: pixels,
                width: image.width,
                height: image.height
            )
        }
    }

    private static func hasUnderline(box: CGRect, pixels: [UInt8], width: Int, height: Int) -> Bool {
        let minX = max(0, min(width - 1, Int(box.minX * Double(width))))
        let maxX = max(minX, min(width - 1, Int(box.maxX * Double(width))))
        let boxBottom = Int((1 - box.minY) * Double(height))
        let tokenHeight = max(2, Int(box.height * Double(height)))
        let minY = max(0, min(height - 1, boxBottom - max(2, tokenHeight / 8)))
        let maxY = max(minY, min(height - 1, boxBottom + max(2, tokenHeight / 5)))
        let requiredRun = max(4, Int(Double(maxX - minX + 1) * 0.48))

        for y in minY...maxY {
            var run = 0
            for x in minX...maxX {
                if pixels[y * width + x] < 105 {
                    run += 1
                    if run >= requiredRun { return true }
                } else {
                    run = 0
                }
            }
        }
        return false
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
