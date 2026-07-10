import AppKit
import Security
import SwiftUI

@main
struct TutorClipApp {
    static func main() {
        RuntimeLog.installCrashHooks()
        RuntimeLog.write("app-main")
        RuntimeLog.write("app-runtime \(RuntimeLog.runtimeIdentity())")
        if DiagnosticCLI.runIfRequested() {
            RuntimeLog.write("diagnostic-cli-exit")
            return
        }
        if SingleInstanceGuard.shouldExitCurrentProcess() {
            RuntimeLog.write("single-instance-exit")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            RuntimeLog.write("application-test-host")
            return
        }
        RuntimeLog.write("application-did-finish-launching")
        coordinator = AppCoordinator()
        coordinator?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        RuntimeLog.write("application-will-terminate")
        coordinator?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

enum SingleInstanceGuard {
    static func shouldExitCurrentProcess() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existingApps = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
        guard let existing = existingApps.first else { return false }
        if #available(macOS 14.0, *) {
            existing.activate()
        } else {
            existing.activate(options: [.activateIgnoringOtherApps])
        }
        return true
    }
}

enum RuntimeLog {
    private static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".tutorclip", isDirectory: true)
        .appendingPathComponent("runtime.log")
    private static let writer = RuntimeLogFileWriter(fileURL: fileURL, maxFileSize: 256 * 1024)

    static func installCrashHooks() {
        NSSetUncaughtExceptionHandler { exception in
            RuntimeLog.write("uncaught-exception name=\(exception.name.rawValue) reason=\(exception.reason ?? "nil")")
        }
    }

    static func write(_ message: String) {
        let line = "\(timestamp()) \(message)\n"
        writer.append(line)
    }

    static func runtimeIdentity() -> String {
        let bundlePath = Bundle.main.bundlePath
        let executablePath = Bundle.main.executablePath ?? "unknown"
        let modifiedAt = executableModifiedDate(path: executablePath)
        return "bundle=\(bundlePath) executable=\(executablePath) modified=\(modifiedAt) signing=\(signingIdentity())"
    }

    static func writeTextBlock(_ label: String, _ text: String) {
        guard verboseTextLoggingEnabled else {
            write("\(label) chars=\(text.count) redacted=true")
            return
        }
        write("\(label)-begin chars=\(text.count)")
        write(escapedLogText(text))
        write("\(label)-end")
    }

    static func writeTextMetrics(_ label: String, _ text: String) {
        let lines = text.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let blankLines = lines.count - nonEmptyLines.count
        let paragraphs = text.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        write(
            "\(label) chars=\(text.count) lines=\(lines.count) nonEmptyLines=\(nonEmptyLines.count) blankLines=\(blankLines) paragraphs=\(paragraphs.count) hash=\(stableHash(text))"
        )
    }

    private static var verboseTextLoggingEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["TUTORCLIP_VERBOSE_TEXT_LOGS"] == "1"
        #else
        false
        #endif
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func executableModifiedDate(path: String) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attributes[.modificationDate] as? Date else {
            return "unknown"
        }
        return ISO8601DateFormatter().string(from: date)
    }

    private static func signingIdentity() -> String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return "unavailable"
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return "unavailable"
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else {
            return "unavailable"
        }

        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String ?? "none"
        let identifier = dict[kSecCodeInfoIdentifier as String] as? String ?? Bundle.main.bundleIdentifier ?? "unknown"
        let cdhash = (dict[kSecCodeInfoUnique as String] as? Data)
            .map { data in data.map { String(format: "%02x", $0) }.joined() } ?? "unknown"
        return "identifier=\(identifier) team=\(team) cdhash=\(cdhash)"
    }

    private static func escapedLogText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

}
