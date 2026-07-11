import AppKit
import Darwin
import Foundation
import Vision

enum DiagnosticCLI {
    @MainActor
    static func runIfRequested() -> Bool {
        if let flag = CommandLine.arguments.firstIndex(of: "--probe-table-image"),
           CommandLine.arguments.indices.contains(flag + 1) {
            let passed = TableImageDiagnostic.runBlocking(
                imagePath: CommandLine.arguments[flag + 1],
                expectedAnswer: argument(after: "--expected-answer"),
                expectedTitle: argument(after: "--expected-title")
            )
            if !passed { exit(EXIT_FAILURE) }
            return true
        }
        if CommandLine.arguments.contains("--probe-markdown-pipeline") {
            runMarkdownPipelineProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-selection-prompts") {
            runSelectionPromptProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-default-settings") {
            runDefaultSettingsProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-notes-question-formatting") {
            runNotesQuestionFormattingProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-ocr-format-state") {
            runOCRFormatStateProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-response-processing") {
            runResponseProcessingProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-session-mutation") {
            runSessionMutationProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-answer-selection") {
            runAnswerSelectionProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-chat-request-builder") {
            runChatRequestBuilderProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-user-message-summary") {
            runUserMessageSummaryProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-language-policy") {
            runLanguagePolicyProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-latex-display") {
            runLatexDisplayProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-selection-ui-policy") {
            DiagnosticUIProbe.runSelectionUIPolicyProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-window-positioning") {
            DiagnosticUIProbe.runWindowPositioningProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-answer-ui-refresh") {
            DiagnosticUIProbe.runAnswerUIRefreshProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-study-status-ui-refresh") {
            DiagnosticUIProbe.runStudyStatusUIRefreshProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-source-edit-reset") {
            DiagnosticUIProbe.runSourceEditResetProbe()
            return true
        }
        if CommandLine.arguments.contains("--probe-history-roundtrip") {
            DiagnosticHistoryProbe.runBlocking()
            return true
        }
        guard CommandLine.arguments.contains("--diagnose") else { return false }

        print("screen=\(PermissionService.hasScreenCapturePermission())")
        print("screenCaptureProbe=\(screenCaptureProbe())")
        print("accessibility=\(PermissionService.hasAccessibilityPermission())")
        print("visionLanguages=\(visionLanguages())")
        return true
    }

    private static func argument(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return CommandLine.arguments[index + 1]
    }

    private static func screenCaptureProbe() -> String {
        let semaphore = DispatchSemaphore(value: 0)
        let box = LockedBox("timeout")
        Task {
            let health = await ScreenCaptureHealthService.probe()
            box.set(screenCaptureProbeDescription(health))
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 7)
        return box.value()
    }

    private static func screenCaptureProbeDescription(_ health: ScreenCaptureHealth) -> String {
        switch health.state {
        case .unavailable:
            return "unavailable"
        case .failed:
            return "failed"
        case .captured(let width, let height, let looksUniform):
            return "captured:\(width)x\(height):uniform=\(looksUniform)"
        }
    }

    private static func visionLanguages() -> String {
        do {
            let languages = try VNRecognizeTextRequest().supportedRecognitionLanguages()
            return ["en-US", "zh-Hans"].allSatisfy { languages.contains($0) } ? "ok" : "missing"
        } catch {
            return "error:\(error.localizedDescription)"
        }
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    func set(_ value: Value) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func value() -> Value {
        lock.lock()
        let value = storedValue
        lock.unlock()
        return value
    }
}
