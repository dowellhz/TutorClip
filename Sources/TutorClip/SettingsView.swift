import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var onClose: () -> Void = {}
    var onRestartOnboarding: () -> Void = {}

    private let panelBackground = Color(nsColor: .windowBackgroundColor)
    private let surface = Color.primary.opacity(0.045)
    private let divider = Color.primary.opacity(0.08)
    private var language: AppLanguage { viewModel.settings.appLanguage }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    helpSection
                    permissionsSection
                    shortcutSection
                    deepSeekSection
                    generalSection
                    diagnosticsSection
                }
                .padding(18)
            }
            footer
        }
        .background(panelBackground)
        .frame(width: 560, height: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(language.text("帮助与设置", "Help & Settings"))
                .font(.system(size: 18, weight: .semibold))
            Spacer()
            statusPill(viewModel.keySource, color: .teal)
            Button("×") { onClose() }
                .buttonStyle(ChromeSettingsButtonStyle())
                .focusable(false)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(Color.primary.opacity(0.02))
        .overlay(alignment: .bottom) {
            Rectangle().fill(divider).frame(height: 1)
        }
    }

    private var helpSection: some View {
        section(language.text("快速开始", "Quick Start")) {
            Text(language.text(
                "按 \(viewModel.settings.shortcutDisplay) 框选 SAT 题目；Esc 取消截图。OCR 在本机完成，随后 DeepSeek 会用中文讲解。",
                "Press \(viewModel.settings.shortcutDisplay) to select an SAT question; Esc cancels capture. OCR runs locally, then DeepSeek explains it."
            ))
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                chromeButton(language.text("重新运行首次设置", "Run Setup Again"), action: onRestartOnboarding)
                Text(language.text("适合重新检查权限、快捷键和 Token。", "Recheck permissions, shortcut, and token."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var permissionsSection: some View {
        section(language.text("权限", "Permissions")) {
            statusRow(
                title: language.text("屏幕录制", "Screen Recording"),
                detail: viewModel.hasScreenCapturePermission ? language.text("已允许", "Allowed") : language.text("需要授权", "Needs Permission"),
                color: viewModel.hasScreenCapturePermission ? .teal : .red
            )
            HStack(spacing: 8) {
                chromeButton(language.text("请求授权", "Request")) { viewModel.requestScreenCapturePermission() }
                chromeButton(language.text("打开系统设置", "Open System Settings")) { viewModel.openScreenRecordingSettings() }
                chromeButton(language.text("刷新", "Refresh")) { viewModel.refreshPermissions() }
            }

            Divider().opacity(0.6)

            statusRow(
                title: language.text("辅助功能", "Accessibility"),
                detail: viewModel.hasAccessibilityPermission ? language.text("已允许", "Allowed") : language.text("可选", "Optional"),
                color: viewModel.hasAccessibilityPermission ? .teal : .orange
            )
            chromeButton(language.text("请求辅助功能", "Request Accessibility")) { viewModel.requestAccessibilityPermission() }
        }
    }

    private var shortcutSection: some View {
        section(language.text("快捷键", "Shortcut")) {
            ShortcutRecorderView(
                keyCode: $viewModel.settings.shortcutKeyCode,
                modifiers: $viewModel.settings.shortcutModifiers,
                validationMessage: $viewModel.shortcutValidationMessage,
                language: language
            )
            statusRow(
                title: viewModel.settings.shortcutDisplay,
                detail: viewModel.shortcutIsRegistered ? language.text("已注册", "Registered") : viewModel.shortcutRegistrationMessage,
                color: viewModel.shortcutIsRegistered ? .teal : .red
            )
        }
    }

    private var deepSeekSection: some View {
        section("DeepSeek") {
            labeledField(language.text("临时 API Key", "Temporary API Key")) {
                SecureField(language.text("仅保存在内存", "Kept only in memory"), text: $viewModel.temporaryAPIKey)
                    .textFieldStyle(.plain)
            }
            HStack(spacing: 8) {
                chromeButton(language.text("保存到本地配置", "Save to Local Config")) { viewModel.persistAPIKeyToConfig() }
                    .disabled(viewModel.temporaryAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                chromeButton(language.text("删除本地 Key", "Remove Local Key")) { viewModel.removeAPIKeyFromConfig() }
                Text(viewModel.configPath())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            labeledField("Base URL") {
                TextField("https://api.deepseek.com", text: $viewModel.settings.deepseekBaseURL)
                    .textFieldStyle(.plain)
            }
            labeledField(language.text("模型", "Model")) {
                Picker("", selection: deepSeekModelSelection) {
                    ForEach(DeepSeekModel.allCases) { model in
                        Text(model.title(language: language)).tag(model)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            HStack(spacing: 10) {
                Text("Temperature")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Slider(value: $viewModel.settings.temperature, in: 0...1)
                Text(viewModel.settings.temperature.formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
        }
    }

    private var deepSeekModelSelection: Binding<DeepSeekModel> {
        Binding(
            get: { DeepSeekModel(modelID: viewModel.settings.deepseekModel) },
            set: { viewModel.settings.deepseekModel = $0.rawValue }
        )
    }

    private var generalSection: some View {
        section(language.text("通用", "General")) {
            Picker(language.text("界面语言", "Language"), selection: $viewModel.settings.appLanguage) {
                ForEach(AppLanguage.allCases) { appLanguage in
                    Text(appLanguage.displayName).tag(appLanguage)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appLanguage")

            Picker(language.text("OCR 语言", "OCR Language"), selection: $viewModel.settings.ocrLanguage) {
                ForEach(OCRLanguage.allCases) { ocrLanguage in
                    Text(ocrLanguage.rawValue.capitalized).tag(ocrLanguage)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.ocrLanguage")

            Toggle(language.text("保存学习进度", "Save learning progress"), isOn: $viewModel.settings.learningProgressEnabled)
                .accessibilityIdentifier("settings.learningProgress")
            Text(language.text("保存答题证据、掌握状态、复习日期和生词，不包含截图。", "Saves answer evidence, mastery, review dates, and vocabulary; never screenshots."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Toggle(language.text("保存题目和对话历史", "Save question and chat history"), isOn: $viewModel.settings.historyEnabled)
                .accessibilityIdentifier("settings.history")
            Text(language.text("保存 OCR 文字、结构化文字、题目和对话，不包含截图。", "Saves OCR text, structured text, questions, and chats; never screenshots."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Toggle(language.text("登录时启动", "Launch at Login"), isOn: $viewModel.settings.launchAtLogin)
            Text(viewModel.launchAtLoginMessage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            chromeButton(
                viewModel.isClearingHistory
                    ? language.text("正在清空…", "Clearing…")
                    : language.text("清空历史", "Clear History")
            ) { viewModel.clearHistory() }
                .disabled(viewModel.isClearingHistory)
                .accessibilityIdentifier("settings.clearHistory")
            chromeButton(
                viewModel.isClearingLearningProgress
                    ? language.text("正在清空学习进度…", "Clearing learning progress…")
                    : language.text("清空学习进度", "Clear Learning Progress")
            ) { viewModel.clearLearningProgress() }
                .disabled(viewModel.isClearingLearningProgress)
                .accessibilityIdentifier("settings.clearLearningProgress")
            if !viewModel.historyStatusMessage.isEmpty {
                Text(viewModel.historyStatusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(viewModel.historyStatusIsError ? Color.red : Color.secondary)
            }
        }
    }

    private var diagnosticsSection: some View {
        section(language.text("诊断", "Diagnostics")) {
            HStack {
                chromeButton(
                    viewModel.isRunningDiagnostics
                        ? language.text("诊断中…", "Running…")
                        : language.text("运行诊断", "Run Diagnostics")
                ) { viewModel.runDiagnostics() }
                    .disabled(viewModel.isRunningDiagnostics)
                    .accessibilityIdentifier("settings.runDiagnostics")
                Spacer()
            }
            ForEach(viewModel.diagnostics) { item in
                VStack(alignment: .leading, spacing: 4) {
                    statusRow(title: item.title, detail: stateTitle(item.state), color: color(for: item.state))
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("截图不会保存，API Key 不会写入 Keychain。", "Screenshots are not saved. API keys are not written to Keychain."))
                    .foregroundStyle(.secondary)
                if !viewModel.saveStatusMessage.isEmpty {
                    Text(viewModel.saveStatusMessage)
                        .foregroundStyle(viewModel.saveStatusIsError ? Color.red : Color.teal)
                        .lineLimit(2)
                }
            }
            .font(.system(size: 12))
            Spacer()
            Button(language.text("保存", "Save")) { viewModel.save() }
                .accessibilityIdentifier("settings.save")
                .buttonStyle(PrimaryCapsuleSettingsButtonStyle())
                .focusable(false)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 56)
        .overlay(alignment: .top) {
            Rectangle().fill(divider).frame(height: 1)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func statusRow(title: String, detail: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder field: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            field()
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private func chromeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(ChromeSettingsButtonStyle())
            .focusable(false)
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(surface)
        .clipShape(Capsule())
    }

    private func color(for state: DiagnosticItem.State) -> Color {
        switch state {
        case .pass: return .teal
        case .warn: return .orange
        case .fail: return .red
        }
    }

    private func stateTitle(_ state: DiagnosticItem.State) -> String {
        switch state {
        case .pass: return language.text("通过", "PASS")
        case .warn: return language.text("警告", "WARN")
        case .fail: return language.text("失败", "FAIL")
        }
    }
}

private struct ChromeSettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : Color.primary.opacity(0.07))
            .clipShape(Capsule())
    }
}

private struct PrimaryCapsuleSettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background(configuration.isPressed ? Color.teal.opacity(0.82) : Color.teal)
            .clipShape(Capsule())
    }
}
