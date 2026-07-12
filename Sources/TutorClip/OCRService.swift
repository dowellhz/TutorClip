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
        let rawDetectedCount = document.tokens.filter { $0.isLikelyUnderlined == true }.count
        let acceptedIDs = Set(OCRVisualCuePolicy.acceptedUnderlinedTokens(in: document).map(\.id))
        for index in document.tokens.indices where !acceptedIDs.contains(document.tokens[index].id) {
            document.tokens[index].isLikelyUnderlined = false
        }
        if rawDetectedCount != acceptedIDs.count {
            RuntimeLog.write("ocr-underline-detection-filtered detected=\(rawDetectedCount) accepted=\(acceptedIDs.count) total=\(document.tokens.count)")
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

enum OCRVisualCuePolicy {
    static func acceptedUnderlinedTokens(in document: OCRDocument) -> [OCRToken] {
        let tableRegions = document.structuredTables.map { $0.boundingBox.cgRect }
        let inferredTableTitleRegions = tableRegions.map { table in
            CGRect(
                x: 0,
                y: table.maxY,
                width: 1,
                height: min(0.15, max(0, 1 - table.maxY))
            )
        }
        let regions = tableRegions
            + inferredTableTitleRegions
            + [document.documentTitle?.boundingBox.cgRect].compactMap { $0 }
        let candidates = document.tokens.filter { token in
            token.isLikelyUnderlined == true
                && !regions.contains { substantiallyContains(token.boundingBox.cgRect, region: $0) }
        }
        guard !shouldSuppressUnderlineDetection(
            detectedCount: candidates.count,
            totalCount: document.tokens.count
        ) else { return [] }
        return candidates
    }

    static func shouldSuppressUnderlineDetection(detectedCount: Int, totalCount: Int) -> Bool {
        guard totalCount > 0, detectedCount >= 6 else { return false }
        return Double(detectedCount) / Double(totalCount) >= 0.35
    }

    static func substantiallyContains(_ token: CGRect, region: CGRect) -> Bool {
        guard token.width > 0, token.height > 0 else { return false }
        let overlap = token.intersection(region)
        guard !overlap.isNull, !overlap.isEmpty else { return false }
        return overlap.width * overlap.height >= token.width * token.height * 0.5
    }

    static func occursUniquely(_ text: String, in source: String) -> Bool {
        guard !text.isEmpty else { return false }
        let source = source as NSString
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let whole = NSRange(location: 0, length: source.length)
        let first = source.range(of: text, options: options, range: whole)
        guard first.location != NSNotFound else { return false }
        let next = first.location + first.length
        let remaining = NSRange(location: next, length: source.length - next)
        return source.range(of: text, options: options, range: remaining).location == NSNotFound
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
    func upscaledForOCR(targetWidth: Int = 2400, maximumScale: Int = 3) -> CGImage {
        guard width > 0, height > 0 else { return paddedForOCR() }
        guard width < targetWidth else { return paddedForOCR() }

        let scale = min(maximumScale, max(1, targetWidth / width))
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
