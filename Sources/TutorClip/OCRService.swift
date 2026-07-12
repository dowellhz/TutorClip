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
        restoreLineUnderlines(in: &document, pixels: pixels, width: image.width, height: image.height)
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

    private static func restoreLineUnderlines(
        in document: inout OCRDocument,
        pixels: [UInt8],
        width: Int,
        height: Int
    ) {
        let tokenIndexes = Dictionary(uniqueKeysWithValues: document.tokens.indices.map { (document.tokens[$0].id, $0) })
        for line in document.lines {
            let segments = horizontalUnderlineSegments(
                below: line.boundingBox.cgRect,
                pixels: pixels,
                width: width,
                height: height
            )
            guard !segments.isEmpty else { continue }
            for tokenID in line.tokenIds {
                guard let tokenIndex = tokenIndexes[tokenID] else { continue }
                let box = document.tokens[tokenIndex].boundingBox.cgRect
                if segments.contains(where: { substantiallyOverlaps(box: box, segment: $0, imageWidth: width) }) {
                    document.tokens[tokenIndex].isLikelyUnderlined = true
                }
            }
        }
    }

    private static func horizontalUnderlineSegments(
        below line: CGRect,
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> [ClosedRange<Int>] {
        let minX = max(0, min(width - 1, Int(line.minX * Double(width))))
        let maxX = max(minX, min(width - 1, Int(line.maxX * Double(width))))
        let lineBottom = Int((1 - line.minY) * Double(height))
        let lineHeight = max(2, Int(line.height * Double(height)))
        // Vision's line box can include or exclude the underline depending on the
        // screenshot scale. Search the lower half of the line plus a small margin;
        // the long-run requirement below excludes ordinary glyph strokes.
        let minY = max(0, min(height - 1, lineBottom - max(3, lineHeight / 2)))
        let maxY = max(minY, min(height - 1, lineBottom + max(3, lineHeight / 3)))
        let minimumRun = max(8, Int(Double(maxX - minX + 1) * 0.12))
        var segments: [ClosedRange<Int>] = []

        for y in minY...maxY {
            var runStart: Int?
            for x in minX...maxX {
                if pixels[y * width + x] < 105 {
                    if runStart == nil { runStart = x }
                } else if let start = runStart {
                    if x - start >= minimumRun {
                        segments.append(start...(x - 1))
                    }
                    runStart = nil
                }
            }
            if let runStart, maxX - runStart + 1 >= minimumRun {
                segments.append(runStart...maxX)
            }
        }
        return segments
    }

    private static func substantiallyOverlaps(box: CGRect, segment: ClosedRange<Int>, imageWidth: Int) -> Bool {
        let minX = Int(box.minX * Double(imageWidth))
        let maxX = Int(box.maxX * Double(imageWidth))
        let overlap = max(0, min(maxX, segment.upperBound) - max(minX, segment.lowerBound) + 1)
        let tokenWidth = max(1, maxX - minX + 1)
        return Double(overlap) / Double(tokenWidth) >= 0.45
    }
}

enum OCRVisualCuePolicy {
    private struct UnderlineFragment {
        var lineIndex: Int
        var text: String
        var startsLine: Bool
        var endsLine: Bool
    }

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

    static func underlinedTextSpans(in document: OCRDocument) -> [String] {
        let acceptedIDs = Set(acceptedUnderlinedTokens(in: document).map(\.id))
        guard !acceptedIDs.isEmpty else { return [] }

        let tokensByID = Dictionary(uniqueKeysWithValues: document.tokens.map { ($0.id, $0) })
        let fragments = document.lines.enumerated().flatMap { lineIndex, line in
            underlineFragments(in: line, lineIndex: lineIndex, tokensByID: tokensByID, acceptedIDs: acceptedIDs)
        }
        return expandSentenceSpans(mergeLineFragments(fragments), in: document)
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

    private static func underlineFragments(
        in line: OCRLine,
        lineIndex: Int,
        tokensByID: [UUID: OCRToken],
        acceptedIDs: Set<UUID>
    ) -> [UnderlineFragment] {
        let lineTokens = line.tokenIds.compactMap { tokensByID[$0] }
        guard !lineTokens.isEmpty else { return [] }

        var result: [UnderlineFragment] = []
        var tokenIndex = 0
        var spanStart: String.Index?
        var spanEnd: String.Index?

        func appendFragment() {
            guard let spanStart, let spanEnd else { return }
            let prefix = line.text[..<spanStart]
            let suffix = line.text[line.text.index(after: spanEnd)...]
            result.append(UnderlineFragment(
                lineIndex: lineIndex,
                text: String(line.text[spanStart...spanEnd]),
                startsLine: prefix.allSatisfy(\.isWhitespace),
                endsLine: suffix.allSatisfy(\.isWhitespace)
            ))
        }

        for index in line.text.indices {
            let character = line.text[index]
            guard !character.isWhitespace else { continue }
            guard tokenIndex < lineTokens.count else { break }
            let token = lineTokens[tokenIndex]
            tokenIndex += 1

            if acceptedIDs.contains(token.id) {
                if spanStart == nil { spanStart = index }
                spanEnd = index
            } else if spanStart != nil {
                appendFragment()
                spanStart = nil
                spanEnd = nil
            }
        }
        appendFragment()
        return result
    }

    private static func mergeLineFragments(_ fragments: [UnderlineFragment]) -> [String] {
        var result: [String] = []
        var previous: UnderlineFragment?

        for fragment in fragments {
            if let previous,
               previous.lineIndex + 1 == fragment.lineIndex,
               previous.endsLine,
               fragment.startsLine,
               !result.isEmpty {
                result[result.count - 1] += " " + fragment.text
            } else {
                result.append(fragment.text)
            }
            previous = fragment
        }
        return result
    }

    private static func expandSentenceSpans(_ spans: [String], in document: OCRDocument) -> [String] {
        guard spans.count >= 2 else { return spans }
        let source = document.lines.map(\.text).joined(separator: " ")
        let normalizedSpans = spans.map(normalizedWhitespace)
        var replacements: [Int: String] = [:]

        for sentence in sentences(in: source) {
            let normalizedSentence = normalizedWhitespace(sentence)
            let matchingIndexes = normalizedSpans.indices.filter { normalizedSentence.contains(normalizedSpans[$0]) }
            let matchedCharacterCount = matchingIndexes.reduce(0) { $0 + normalizedSpans[$1].count }
            guard matchingIndexes.count >= 2,
                  Double(matchedCharacterCount) / Double(max(1, normalizedSentence.count)) >= 0.35,
                  let first = matchingIndexes.first else { continue }
            replacements[first] = sentence
            for index in matchingIndexes.dropFirst() {
                replacements[index] = ""
            }
        }

        return spans.enumerated().compactMap { index, span in
            guard let replacement = replacements[index] else { return span }
            return replacement.isEmpty ? nil : replacement
        }
    }

    private static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var start = text.startIndex
        for index in text.indices where ".?!".contains(text[index]) {
            let end = text.index(after: index)
            let sentence = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            start = end
        }
        let remainder = text[start...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !remainder.isEmpty { result.append(remainder) }
        return result
    }

    private static func normalizedWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
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
