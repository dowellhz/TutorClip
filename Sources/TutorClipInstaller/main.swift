import AppKit
import Security
import SwiftUI

private let tutorClipBundleID = "com.linlu.TutorClip"

@MainActor
final class InstallerAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var status = "准备安装 TutorClip"
    @Published private(set) var detail = "安装器会自动退出正在运行的旧版本，然后完成替换。"
    @Published private(set) var isInstalling = false
    @Published private(set) var isComplete = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        presentWindowWhenReady(attemptsRemaining: 10)
    }

    private func presentWindowWhenReady(attemptsRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = NSApp.windows.first(where: { $0.canBecomeKey }) else {
                if attemptsRemaining > 1 {
                    self.presentWindowWhenReady(attemptsRemaining: attemptsRemaining - 1)
                }
                return
            }
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func startInstallation() {
        guard !isInstalling else { return }
        if isComplete {
            NSApp.terminate(nil)
            return
        }
        isInstalling = true
        Task { @MainActor in
            defer { isInstalling = false }
            do {
                try await performInstallation()
                updateStatus("安装完成", detail: "TutorClip 已更新并重新启动。")
                isComplete = true
            } catch is CancellationError {
                updateStatus("安装已取消", detail: "没有替换现有版本。")
            } catch {
                updateStatus("安装失败", detail: error.localizedDescription)
            }
        }
    }

    private func performInstallation() async throws {
        let source = try sourceApplicationURL()
        try validateTutorClip(at: source)

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: tutorClipBundleID)
            .filter { !$0.isTerminated }
        let preferredLocation = runningApps.compactMap(\.bundleURL).first
        if !runningApps.isEmpty {
            updateStatus("正在退出旧版本…", detail: "请稍候，不需要在活动监视器中查找进程。")
            runningApps.forEach { $0.terminate() }
            let remaining = await waitForTermination(runningApps, attempts: 50)
            if !remaining.isEmpty {
                guard confirmForceQuit() else { throw CancellationError() }
                remaining.forEach { $0.forceTerminate() }
                guard await waitForTermination(remaining, attempts: 30).isEmpty else {
                    throw InstallerError.cannotTerminate
                }
            }
        }

        let destination = installationDestination(preferredLocation: preferredLocation)
        updateStatus("正在安装…", detail: destination.path)
        try install(source: source, destination: destination)
        try validateTutorClip(at: destination)

        updateStatus("正在启动新版…", detail: destination.path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
    }

    private func sourceApplicationURL() throws -> URL {
        let source = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("TutorClip.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw InstallerError.missingSource
        }
        return source
    }

    private func installationDestination(preferredLocation: URL?) -> URL {
        let homeDestination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("TutorClip.app", isDirectory: true)
        let systemDestination = URL(fileURLWithPath: "/Applications/TutorClip.app", isDirectory: true)
        if let preferredLocation,
           [homeDestination.standardizedFileURL, systemDestination.standardizedFileURL].contains(preferredLocation.standardizedFileURL) {
            return preferredLocation.standardizedFileURL
        }
        if FileManager.default.fileExists(atPath: homeDestination.path) { return homeDestination }
        if FileManager.default.fileExists(atPath: systemDestination.path) { return systemDestination }
        return homeDestination
    }

    private func install(source: URL, destination: URL) throws {
        if destination.path == "/Applications/TutorClip.app" {
            try privilegedInstall(source: source, destination: destination)
            return
        }
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func privilegedInstall(source: URL, destination: URL) throws {
        let command = "/bin/rm -rf \(shellQuote(destination.path)) && /usr/bin/ditto \(shellQuote(source.path)) \(shellQuote(destination.path))"
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        var errorInfo: NSDictionary?
        guard NSAppleScript(source: script)?.executeAndReturnError(&errorInfo) != nil else {
            let message = (errorInfo?[NSAppleScript.errorMessage] as? String) ?? "管理员授权失败。"
            throw InstallerError.privilegedCopyFailed(message)
        }
    }

    private func validateTutorClip(at url: URL) throws {
        guard Bundle(url: url)?.bundleIdentifier == tutorClipBundleID else {
            throw InstallerError.invalidSource
        }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw InstallerError.invalidSignature
        }
    }

    private func waitForTermination(_ applications: [NSRunningApplication], attempts: Int) async -> [NSRunningApplication] {
        for _ in 0..<attempts {
            let remaining = applications.filter { !$0.isTerminated }
            if remaining.isEmpty { return [] }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return applications.filter { !$0.isTerminated }
    }

    private func confirmForceQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = "TutorClip 仍在运行"
        alert.informativeText = "是否强制退出旧版本并继续安装？未保存的当前截图会被丢弃。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "强制退出并安装")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func updateStatus(_ status: String, detail: String) {
        self.status = status
        self.detail = detail
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

private struct InstallerView: View {
    @ObservedObject var controller: InstallerAppDelegate

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
            Text(controller.status)
                .font(.system(size: 22, weight: .semibold))
            Text(controller.detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 410)
            HStack(spacing: 12) {
                if controller.isInstalling {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(controller.isComplete ? "完成" : "安装") {
                    controller.startInstallation()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(controller.isInstalling)
            }
        }
        .padding(.horizontal, 38)
        .padding(.vertical, 32)
        .frame(width: 500, height: 330)
    }
}

@main
private struct InstallerMain: App {
    @NSApplicationDelegateAdaptor(InstallerAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("安装 TutorClip") {
            InstallerView(controller: delegate)
        }
        .defaultSize(width: 500, height: 330)
        .windowResizability(.contentSize)
    }
}

private enum InstallerError: LocalizedError {
    case missingSource
    case invalidSource
    case invalidSignature
    case cannotTerminate
    case privilegedCopyFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSource: return "安装器旁边没有找到 TutorClip.app，请重新打开官方 DMG。"
        case .invalidSource: return "待安装应用的身份不正确。"
        case .invalidSignature: return "TutorClip 签名验证失败，安装已停止。"
        case .cannotTerminate: return "无法退出正在运行的 TutorClip，请注销后重试。"
        case .privilegedCopyFailed(let message): return "无法写入 Applications：\(message)"
        }
    }
}
