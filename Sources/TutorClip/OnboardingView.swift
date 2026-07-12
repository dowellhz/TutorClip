import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, capture, token, ready
    }

    @ObservedObject var viewModel: SettingsViewModel
    var onFinish: () -> Void
    @State private var step: Step = .welcome
    @State private var saveKeyLocally = true

    private var language: AppLanguage { viewModel.settings.appLanguage }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 700, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { viewModel.refreshPermissions() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 22))
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("TutorClip")
                    .font(.system(size: 19, weight: .semibold))
                Text(stepTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(step.rawValue + 1) / \(Step.allCases.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .capture: captureStep
        case .token: tokenStep
        case .ready: readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(language.text("欢迎使用 TutorClip", "Welcome to TutorClip"))
                .font(.system(size: 28, weight: .bold))
            Text(language.text(
                "TutorClip 是会主动安排练习的 SAT 私教，也可以从任何题目页面截图提问。完成下面设置后即可开始。",
                "TutorClip is an adaptive SAT tutor that also accepts questions from screenshots. Complete setup to begin."
            ))
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            helpRow("1", language.text("按 Shift + Command + O 框选题目", "Press Shift + Command + O to select a question"))
            helpRow("2", language.text("Apple Vision 在本机识别文字，不保存截图", "Apple Vision recognizes text locally; screenshots are not saved"))
            helpRow("3", language.text("DeepSeek 用中文按 SAT 老师方式讲解", "DeepSeek explains it like an SAT tutor"))
            Spacer()
            Picker("", selection: $viewModel.settings.appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
    }

    private var captureStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(language.text("设置截图与权限", "Set Up Capture and Permissions"))
                .font(.system(size: 24, weight: .bold))
            Text(language.text("屏幕录制权限仅用于读取你主动框选的区域。Esc 可随时取消截图。", "Screen Recording is used only for the region you select. Press Esc to cancel capture at any time."))
                .foregroundStyle(.secondary)
            setupBox {
                statusLine(language.text("屏幕录制", "Screen Recording"), allowed: viewModel.hasScreenCapturePermission, required: true)
                HStack {
                    Button(language.text("请求权限", "Request Permission")) { viewModel.requestScreenCapturePermission() }
                    Button(language.text("打开系统设置", "Open System Settings")) { viewModel.openScreenRecordingSettings() }
                    Button(language.text("刷新状态", "Refresh")) { viewModel.refreshPermissions() }
                }
            }
            setupBox {
                Text(language.text("截图快捷键", "Capture Shortcut"))
                    .font(.system(size: 14, weight: .semibold))
                ShortcutRecorderView(
                    keyCode: $viewModel.settings.shortcutKeyCode,
                    modifiers: $viewModel.settings.shortcutModifiers,
                    validationMessage: $viewModel.shortcutValidationMessage,
                    language: language
                )
                Text(viewModel.settings.shortcutDisplay)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            setupBox {
                statusLine(language.text("辅助功能", "Accessibility"), allowed: viewModel.hasAccessibilityPermission, required: false)
                Button(language.text("可选：请求辅助功能权限", "Optional: Request Accessibility")) { viewModel.requestAccessibilityPermission() }
            }
        }
    }

    private var tokenStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(language.text("连接 DeepSeek", "Connect DeepSeek"))
                .font(.system(size: 24, weight: .bold))
            Text(language.text("Token 不会写入日志、历史或源码。你可以只在本次运行使用，也可以保存到本机 config.json。", "The token is never written to logs, history, or source code. Keep it for this run only or save it in local config.json."))
                .foregroundStyle(.secondary)
            setupBox {
                Text("DeepSeek API Key")
                    .font(.system(size: 14, weight: .semibold))
                SecureField(language.text("输入 API Key", "Enter API Key"), text: $viewModel.temporaryAPIKey)
                    .textFieldStyle(.roundedBorder)
                Toggle(language.text("保存到本机 config.json（下次启动继续使用）", "Save to local config.json for future launches"), isOn: $saveKeyLocally)
                Text(language.text("当前来源：\(viewModel.keySource)", "Current source: \(viewModel.keySource)"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(viewModel.configPath())
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !viewModel.saveStatusMessage.isEmpty {
                Text(viewModel.saveStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.saveStatusIsError ? .red : .secondary)
            }
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(language.text("设置完成", "You're Ready"))
                .font(.system(size: 28, weight: .bold))
            helpRow("✓", language.text("TutorClip 将常驻菜单栏", "TutorClip stays in the menu bar"))
            helpRow("✓", language.text("使用 \(viewModel.settings.shortcutDisplay) 开始截图", "Use \(viewModel.settings.shortcutDisplay) to capture"))
            helpRow("✓", language.text("可从菜单中的“帮助与首次设置”重新打开本向导", "Reopen this guide from Help & Setup in the menu"))
            Text(language.text("提示：macOS 更改屏幕录制权限后，可能需要重新启动 TutorClip。", "Tip: macOS may require restarting TutorClip after changing Screen Recording permission."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            setupBox {
                Toggle(language.text("保存学习进度", "Save learning progress"), isOn: $viewModel.settings.learningProgressEnabled)
                Toggle(language.text("保存题目和对话历史", "Save question and chat history"), isOn: $viewModel.settings.historyEnabled)
                Text(language.text(
                    "两项可以独立关闭。截图永不保存；学习进度只包含答题、掌握状态、复习日期和生词。",
                    "These are independent. Screenshots are never saved; learning progress contains only answers, mastery, review dates, and vocabulary."
                ))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(language.text("上一步", "Back")) { move(-1) }
                .disabled(step == .welcome)
            Spacer()
            if step == .capture && !viewModel.hasScreenCapturePermission {
                Text(language.text("可稍后授权", "You can grant permission later"))
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            if step == .ready {
                Button(language.text("开始使用", "Start Using TutorClip")) { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
            } else {
                Button(language.text("继续", "Continue")) { move(1) }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .disabled(step == .token && !viewModel.hasConfiguredAPIKey)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 66)
    }

    private func move(_ offset: Int) {
        if step == .capture { viewModel.refreshPermissions() }
        if step == .token { viewModel.save() }
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        step = next
    }

    private func finish() {
        guard viewModel.completeOnboarding(saveKeyLocally: saveKeyLocally) else { return }
        onFinish()
    }

    private func helpRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Text(symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.teal)
                .frame(width: 28, height: 28)
                .background(Color.teal.opacity(0.1), in: Circle())
            Text(text).font(.system(size: 15, weight: .medium))
        }
    }

    private func statusLine(_ title: String, allowed: Bool, required: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(allowed ? language.text("已允许", "Allowed") : (required ? language.text("需要授权", "Required") : language.text("可选", "Optional")))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(allowed ? .teal : (required ? .red : .secondary))
        }
    }

    private func setupBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var stepTitle: String {
        switch step {
        case .welcome: return language.text("欢迎与使用帮助", "Welcome and Help")
        case .capture: return language.text("截图与系统权限", "Capture and Permissions")
        case .token: return language.text("DeepSeek Token", "DeepSeek Token")
        case .ready: return language.text("完成", "Ready")
        }
    }
}
