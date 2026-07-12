import Foundation
import Vision

struct DiagnosticItem: Identifiable, Equatable {
    enum State: String {
        case pass = "PASS"
        case warn = "WARN"
        case fail = "FAIL"
    }

    var id = UUID()
    var title: String
    var state: State
    var detail: String
}

enum DiagnosticsService {
    static func run(settings: AppSettings, shortcut: ShortcutRegistrationResult, config: DeepSeekConfig) -> [DiagnosticItem] {
        let language = settings.appLanguage
        return [
            screenRecordingItem(language: language),
            accessibilityItem(language: language),
            shortcutItem(shortcut, language: language),
            apiKeyItem(config, language: language),
            visionItem(settings.ocrLanguage, language: language),
            historyDirectoryItem(language: language),
            screenshotPersistenceItem(language: language)
        ] + PipelineTimingMetrics.diagnosticItems(language: language)
    }

    static func runWithCaptureProbe(settings: AppSettings, shortcut: ShortcutRegistrationResult, config: DeepSeekConfig) async -> [DiagnosticItem] {
        var items = run(settings: settings, shortcut: shortcut, config: config)
        items.insert(await screenCaptureHealthItem(language: settings.appLanguage), at: 1)
        return items
    }

    private static func accessibilityItem(language: AppLanguage) -> DiagnosticItem {
        let granted = PermissionService.hasAccessibilityPermission()
        return DiagnosticItem(
            title: language.text("辅助功能", "Accessibility"),
            state: granted ? .pass : .warn,
            detail: granted
                ? language.text("权限已允许。", "Permission is granted.")
                : language.text("当前截图流程不强制需要，但快捷键或浮窗受限时会有帮助。", "Not required for current capture flow, but useful if shortcut/overlay behavior is restricted.")
        )
    }

    private static func screenRecordingItem(language: AppLanguage) -> DiagnosticItem {
        let granted = PermissionService.hasScreenCapturePermission()
        return DiagnosticItem(
            title: language.text("屏幕录制", "Screen Recording"),
            state: granted ? .pass : .fail,
            detail: granted ? language.text("权限已允许。", "Permission is granted.") : language.text("截图需要此权限。", "Permission is required for capture.")
        )
    }

    private static func screenCaptureHealthItem(language: AppLanguage) async -> DiagnosticItem {
        switch await ScreenCaptureHealthService.probe().state {
        case .unavailable:
            return DiagnosticItem(
                title: language.text("实际截屏", "Capture Probe"),
                state: .fail,
                detail: language.text("屏幕录制权限未授予，无法执行实际截屏探针。", "Screen Recording is not granted, so the capture probe cannot run.")
            )
        case .failed:
            return DiagnosticItem(
                title: language.text("实际截屏", "Capture Probe"),
                state: .fail,
                detail: language.text("ScreenCaptureKit 未返回图片。请确认授权的是当前安装的 TutorClip，并重启 App。", "ScreenCaptureKit did not return an image. Confirm the installed TutorClip app is authorized and restart it.")
            )
        case .captured(let width, let height, let looksUniform):
            return DiagnosticItem(
                title: language.text("实际截屏", "Capture Probe"),
                state: looksUniform ? .warn : .pass,
                detail: looksUniform
                    ? language.text("返回 \(width)x\(height) 图片，但内容接近纯色；如果截图预览仍是背景，请重置屏幕录制权限后重新授权当前 App。", "Returned a \(width)x\(height) image, but it looks nearly uniform. If previews still show only the background, reset Screen Recording and re-authorize the current app.")
                    : language.text("ScreenCaptureKit 返回 \(width)x\(height) 图片。", "ScreenCaptureKit returned a \(width)x\(height) image.")
            )
        }
    }

    private static func shortcutItem(_ result: ShortcutRegistrationResult, language: AppLanguage) -> DiagnosticItem {
        DiagnosticItem(
            title: language.text("全局快捷键", "Global Shortcut"),
            state: result.isRegistered ? .pass : .fail,
            detail: result.message
        )
    }

    private static func apiKeyItem(_ config: DeepSeekConfig, language: AppLanguage) -> DiagnosticItem {
        DiagnosticItem(
            title: "DeepSeek API Key",
            state: config.apiKey == nil ? .warn : .pass,
            detail: config.apiKey == nil
                ? language.text("API Key 未配置。", "API key is not configured.")
                : language.text("配置来源：\(config.keySource.rawValue)。", "Configured from \(config.keySource.rawValue).")
        )
    }

    private static func visionItem(_ ocrLanguage: OCRLanguage, language: AppLanguage) -> DiagnosticItem {
        do {
            let supported = try VNRecognizeTextRequest().supportedRecognitionLanguages()
            let required = ocrLanguage == .chinese ? ["zh-Hans"] : ["en-US"]
            let missing = required.filter { !supported.contains($0) }
            return DiagnosticItem(
                title: language.text("本地 OCR", "Local OCR"),
                state: missing.isEmpty ? .pass : .fail,
                detail: missing.isEmpty
                    ? language.text("Vision 支持 \(required.joined(separator: ", "))。", "Vision supports \(required.joined(separator: ", ")).")
                    : language.text("缺少 \(missing.joined(separator: ", "))。", "Missing \(missing.joined(separator: ", ")).")
            )
        } catch {
            return DiagnosticItem(title: language.text("本地 OCR", "Local OCR"), state: .fail, detail: error.localizedDescription)
        }
    }

    private static func historyDirectoryItem(language: AppLanguage) -> DiagnosticItem {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tutorclip", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let probe = directory.appendingPathComponent(".write-test")
            try "ok".write(to: probe, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: probe)
            return DiagnosticItem(
                title: language.text("历史存储", "History Storage"),
                state: .pass,
                detail: language.text("\(directory.path) 可写。", "\(directory.path) is writable.")
            )
        } catch {
            return DiagnosticItem(title: language.text("历史存储", "History Storage"), state: .fail, detail: error.localizedDescription)
        }
    }

    private static func screenshotPersistenceItem(language: AppLanguage) -> DiagnosticItem {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tutorclip", isDirectory: true)
        let extensions = ["png", "jpg", "jpeg", "heic", "tiff"]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return noScreenshotFilesItem(language: language)
        }
        for case let url as URL in enumerator where extensions.contains(url.pathExtension.lowercased()) {
            return DiagnosticItem(
                title: language.text("截图持久化", "Screenshot Persistence"),
                state: .fail,
                detail: language.text("发现图片文件：\(url.lastPathComponent)。", "Found image file: \(url.lastPathComponent).")
            )
        }
        return noScreenshotFilesItem(language: language)
    }

    private static func noScreenshotFilesItem(language: AppLanguage) -> DiagnosticItem {
        DiagnosticItem(
            title: language.text("截图持久化", "Screenshot Persistence"),
            state: .pass,
            detail: language.text("未发现截图文件。", "No screenshot files found.")
        )
    }
}

enum PipelineTimingMetrics {
    private static let lock = NSLock()
    private static var latest: [String: TimeInterval] = [:]

    static func record(stage: String, duration: TimeInterval) {
        lock.lock()
        latest[stage] = duration
        lock.unlock()
    }

    static func diagnosticItems(language: AppLanguage) -> [DiagnosticItem] {
        lock.lock()
        let snapshot = latest
        lock.unlock()
        guard !snapshot.isEmpty else {
            return [DiagnosticItem(
                title: language.text("最近链路耗时", "Recent Pipeline Timing"),
                state: .warn,
                detail: language.text("完成一次截图识题后会显示各阶段耗时。", "Stage timings appear after one screenshot question.")
            )]
        }
        return snapshot.keys.sorted().map { stage in
            let seconds = snapshot[stage] ?? 0
            return DiagnosticItem(
                title: language == .chinese ? stage.replacingOccurrences(of: "Local Vision OCR", with: "本地 Vision OCR").replacingOccurrences(of: "Pro OCR formatting", with: "Pro OCR 排版").replacingOccurrences(of: "Pro answer verification", with: "Pro 答案校验") : stage,
                state: seconds > 20 ? .warn : .pass,
                detail: language.text("最近一次：\(seconds.formatted(.number.precision(.fractionLength(1)))) 秒", "Latest: \(seconds.formatted(.number.precision(.fractionLength(1)))) s")
            )
        }
    }
}
