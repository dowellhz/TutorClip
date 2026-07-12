import Foundation
import XCTest
@testable import TutorClip

final class InfrastructureBehaviorTests: XCTestCase {
    @MainActor
    func testConfigLoaderPersistsAndRemovesAPIKeyWithOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-config-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = ConfigLoader(baseDirectory: directory)
        var settings = AppSettings()
        settings.deepseekBaseURL = "https://example.invalid"
        settings.deepseekModel = "test-model"
        loader.temporaryAPIKey = "synthetic-test-key"

        try loader.persistTemporaryAPIKey(settings: settings)

        let reloaded = ConfigLoader(baseDirectory: directory)
        let persisted = reloaded.currentConfig(settings: AppSettings())
        XCTAssertEqual(persisted.apiKey, "synthetic-test-key")
        XCTAssertEqual(persisted.baseURL, "https://example.invalid")
        XCTAssertEqual(persisted.model, "test-model")
        XCTAssertEqual(persisted.keySource, .configFile)
        let attributes = try FileManager.default.attributesOfItem(atPath: reloaded.configFilePath())
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try reloaded.removePersistedAPIKey()
        XCTAssertEqual(reloaded.currentConfig(settings: AppSettings()).keySource, .missing)
    }

    @MainActor
    func testConfigLoaderRejectsEmptyPersistentAPIKey() {
        let loader = ConfigLoader(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertThrowsError(try loader.persistTemporaryAPIKey(settings: AppSettings()))
    }

    @MainActor
    func testConfigLoaderUpdatesPersistedModelWithoutReplacingAPIKey() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-model-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = ConfigLoader(baseDirectory: directory)
        loader.temporaryAPIKey = "synthetic-test-key"
        try loader.persistTemporaryAPIKey(settings: AppSettings())

        var settings = AppSettings()
        settings.deepseekModel = DeepSeekModel.pro.rawValue
        try loader.updatePersistedConnectionSettings(settings)

        let reloaded = ConfigLoader(baseDirectory: directory)
        let config = reloaded.currentConfig(settings: AppSettings())
        XCTAssertEqual(config.apiKey, "synthetic-test-key")
        XCTAssertEqual(config.model, DeepSeekModel.pro.rawValue)
    }

    func testDeepSeekModelMapsLegacyAliasesToFlash() {
        XCTAssertEqual(DeepSeekModel(modelID: "deepseek-chat"), .flash)
        XCTAssertEqual(DeepSeekModel(modelID: "deepseek-v4-pro"), .pro)
    }

    func testPracticeVariationCyclesAndRetainsOnlyFiveRecentQuestions() {
        let planner = PracticeVariationPlanner()
        let first = planner.nextVariation()
        let second = planner.nextVariation()

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(PracticeVariationPlanner.practiceTemperature, 0.8)
        for index in 1...6 {
            planner.record("Question \(index)")
        }
        XCTAssertEqual(planner.recentQuestions, ["Question 2", "Question 3", "Question 4", "Question 5", "Question 6"])
        XCTAssertTrue(planner.isExactDuplicate("  QUESTION   6\n"))
    }

    func testPracticeDiversityPromptIncludesVariationAndRecentQuestions() {
        let planner = PracticeVariationPlanner()
        planner.record("A previous generated question")
        let variation = planner.nextVariation()
        let prompt = planner.diversityInstruction(for: variation, retrying: true)

        XCTAssertTrue(prompt.contains(variation.topic))
        XCTAssertTrue(prompt.contains("position \(variation.answerPosition)"))
        XCTAssertTrue(prompt.contains("A previous generated question"))
        XCTAssertTrue(prompt.contains("previous attempt was rejected"))
    }

    func testRuntimeLogWriterSerializesConcurrentAppends() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-log-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let fileURL = baseURL.appendingPathComponent("runtime.log")
        let writer = RuntimeLogFileWriter(fileURL: fileURL, maxFileSize: 1024 * 1024)

        DispatchQueue.concurrentPerform(iterations: 200) { index in
            XCTAssertTrue(writer.append("line-\(index)\n"))
        }

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        XCTAssertEqual(lines.count, 200)
        XCTAssertEqual(Set(lines).count, 200)
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testRuntimeLogWriterRotatesBeforeCrossingLimit() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tutorclip-log-rotation-xctest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }
        let fileURL = baseURL.appendingPathComponent("runtime.log")
        let writer = RuntimeLogFileWriter(fileURL: fileURL, maxFileSize: 10)

        XCTAssertTrue(writer.append("first\n"))
        XCTAssertTrue(writer.append("second\n"))

        let oldURL = baseURL.appendingPathComponent("runtime.old.log")
        XCTAssertEqual(try String(contentsOf: oldURL, encoding: .utf8), "first\n")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "second\n")
    }

    func testAsyncTimeoutReturnsWithoutWaitingForCancellationIgnoringOperation() async throws {
        let start = ContinuousClock.now
        let outcome = await AsyncTimeoutRace.run(timeoutNanoseconds: 15_000_000) {
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            return "late"
        }
        let elapsed = start.duration(to: .now)

        if case .timedOut = outcome {} else { XCTFail("Expected the timeout to win") }
        XCTAssertLessThan(elapsed, .milliseconds(100))
        try await Task.sleep(nanoseconds: 170_000_000)
    }

    func testAsyncTimeoutPropagatesParentCancellationImmediately() async throws {
        let task = Task {
            await AsyncTimeoutRace.run(timeoutNanoseconds: 5_000_000_000) {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                } catch {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
                return "late"
            }
        }
        await Task.yield()
        let cancelTime = ContinuousClock.now
        task.cancel()
        let outcome = await task.value

        if case .cancelled = outcome {} else { XCTFail("Expected parent cancellation to win") }
        XCTAssertLessThan(cancelTime.duration(to: .now), .milliseconds(100))
        try await Task.sleep(nanoseconds: 170_000_000)
    }

    func testAsyncTimeoutReturnsFastOperationValue() async {
        let outcome = await AsyncTimeoutRace.run(timeoutNanoseconds: 100_000_000) { "captured" }

        switch outcome {
        case .value(let value): XCTAssertEqual(value, "captured")
        case .timedOut: XCTFail("Fast operation unexpectedly timed out")
        case .cancelled: XCTFail("Fast operation unexpectedly cancelled")
        }
    }

    func testCaptureGenerationRejectsCompletionFromPreviousCapture() {
        var tracker = CaptureGenerationTracker()
        let firstCapture = tracker.start()
        let replacementCapture = tracker.start()

        XCTAssertFalse(tracker.accept(firstCapture))
        XCTAssertEqual(tracker.currentID, replacementCapture)
        XCTAssertTrue(tracker.accept(replacementCapture))
        XCTAssertNil(tracker.currentID)
    }

    func testScreenCaptureGeometryUsesDisplayLocalCoordinates() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let above = CGRect(x: 0, y: 1080, width: 1920, height: 1200)
        let below = CGRect(x: 0, y: -900, width: 1600, height: 900)

        XCTAssertEqual(ScreenCaptureGeometry.sourceRect(appKitRect: CGRect(x: 100, y: 100, width: 400, height: 300), screenFrame: primary), CGRect(x: 100, y: 680, width: 400, height: 300))
        XCTAssertEqual(ScreenCaptureGeometry.sourceRect(appKitRect: CGRect(x: 120, y: 1280, width: 500, height: 250), screenFrame: above), CGRect(x: 120, y: 750, width: 500, height: 250))
        XCTAssertEqual(ScreenCaptureGeometry.sourceRect(appKitRect: CGRect(x: 80, y: -700, width: 300, height: 200), screenFrame: below), CGRect(x: 80, y: 500, width: 300, height: 200))
    }

    func testScreenCaptureGeometryClipsEdgeSelectionsAndRejectsOffscreenRects() {
        let screen = CGRect(x: 100, y: 200, width: 1000, height: 800)

        XCTAssertEqual(ScreenCaptureGeometry.sourceRect(appKitRect: CGRect(x: 50, y: 150, width: 200, height: 200), screenFrame: screen), CGRect(x: 0, y: 650, width: 150, height: 150))
        XCTAssertEqual(ScreenCaptureGeometry.sourceRect(appKitRect: CGRect(x: 1000, y: 900, width: 200, height: 200), screenFrame: screen), CGRect(x: 900, y: 0, width: 100, height: 100))
        XCTAssertNil(ScreenCaptureGeometry.sourceRect(appKitRect: CGRect(x: -500, y: -500, width: 100, height: 100), screenFrame: screen))
        XCTAssertNil(ScreenCaptureGeometry.sourceRect(appKitRect: .zero, screenFrame: screen))
    }

    func testDeepSeekStreamDecoderAcceptsSSESpacingAndDoneVariants() {
        let event = #"{"choices":[{"delta":{"content":"你好"}}]}"#

        XCTAssertEqual(DeepSeekStreamDecoder.decode("data: \(event)"), .token("你好"))
        XCTAssertEqual(DeepSeekStreamDecoder.decode("data:\(event)"), .token("你好"))
        XCTAssertEqual(DeepSeekStreamDecoder.decode("data: [DONE]"), .done)
        XCTAssertEqual(DeepSeekStreamDecoder.decode("data:[DONE]"), .done)
        XCTAssertEqual(DeepSeekStreamDecoder.decode(": keep-alive"), .ignored)
        XCTAssertEqual(DeepSeekStreamDecoder.decode("data: not-json"), .malformed)
    }

    @MainActor
    func testDeepSeekRequestUsesBoundedProductTimeout() {
        let timeout = DeepSeekClient.requestTimeout
        XCTAssertGreaterThanOrEqual(timeout, 10)
        XCTAssertLessThanOrEqual(timeout, 30)
    }

    func testDeepSeekContentTrackerRejectsWhitespaceOnlyStream() {
        var tracker = DeepSeekStreamContentTracker()
        tracker.record("")
        tracker.record("  \n")
        XCTAssertFalse(tracker.hasVisibleContent)

        tracker.record("讲解")
        XCTAssertTrue(tracker.hasVisibleContent)
    }

    func testDeepSeekStreamDecoderPreservesTokenOrder() {
        let lines = [
            #"data: {"choices":[{"delta":{"content":"第一"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"第二"}}]}"#,
            "data: [DONE]"
        ]
        let tokens = lines.compactMap { line -> String? in
            guard case .token(let token) = DeepSeekStreamDecoder.decode(line) else { return nil }
            return token
        }

        XCTAssertEqual(tokens, ["第一", "第二"])
    }

    func testOCRImageProcessorUpscalesAndPadsSyntheticImage() async throws {
        let source = try makeSyntheticImage(width: 100, height: 50)
        let processed = await OCRImageProcessor().prepare(source)

        XCTAssertEqual(processed.width, 348)
        XCTAssertEqual(processed.height, 198)
    }

    func testWindowKeyboardPolicyClosesOnlyForCommandW() {
        XCTAssertTrue(WindowKeyboardPolicy.shouldClose(modifierFlags: [.command], keyCode: 13))
        XCTAssertTrue(WindowKeyboardPolicy.shouldClose(modifierFlags: [.command, .shift], keyCode: 13))
        XCTAssertFalse(WindowKeyboardPolicy.shouldClose(modifierFlags: [], keyCode: 13))
        XCTAssertFalse(WindowKeyboardPolicy.shouldClose(modifierFlags: [.command], keyCode: 53))
    }

    private func makeSyntheticImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw SyntheticImageError.creationFailed
        }
        return image
    }
}

private enum SyntheticImageError: Error {
    case creationFailed
}
