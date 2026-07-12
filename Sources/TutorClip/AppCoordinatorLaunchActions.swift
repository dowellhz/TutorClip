import Foundation

@MainActor
extension AppCoordinator {
    func handleLaunchMarkers() {
        if consumeLaunchMarker(named: "request-permissions") {
            requestPermissionsFromApp()
        }
        if consumeLaunchMarker(named: "write-diagnostics") {
            writeDiagnosticsFromApp()
        }
        let hasCommandLineDemo = CommandLine.arguments.contains("--demo-session")
        let shouldOpenCommandLineDemo = hasCommandLineDemo && !didHandleCommandLineDemo
        didHandleCommandLineDemo = didHandleCommandLineDemo || hasCommandLineDemo
        if shouldOpenCommandLineDemo || consumeLaunchMarker(named: "launch-demo") {
            openTutorWindow(session: DemoSessionFactory.make())
        }
    }

    private func requestPermissionsFromApp() {
        _ = PermissionService.requestScreenCapturePermission()
        PermissionService.requestAccessibilityPermission()
        PermissionService.openPrivacySettings()
        showSettings()
    }

    private func writeDiagnosticsFromApp() {
        let config = configLoader.currentConfig(settings: settingsStore.settings)
        let settings = settingsStore.settings
        let shortcut = settingsStore.shortcutRegistrationResult
        Task {
            let items = await DiagnosticsService.runWithCaptureProbe(
                settings: settings,
                shortcut: shortcut,
                config: config
            )
            let lines = ["Runtime=\(RuntimeLog.runtimeIdentity())"] + items.map {
                "\($0.title)=\($0.state.rawValue) \($0.detail)"
            }
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".tutorclip", isDirectory: true)
            let file = directory.appendingPathComponent("diagnostics.txt")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func consumeLaunchMarker(named name: String) -> Bool {
        let marker = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tutorclip", isDirectory: true)
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: marker.path) else { return false }
        try? FileManager.default.removeItem(at: marker)
        return true
    }
}
