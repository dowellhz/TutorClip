import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @Binding var validationMessage: String
    var language: AppLanguage = .chinese
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(display)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(language.text("默认", "Default")) {
                    keyCode = KeyCodeDisplay.defaultKeyCode
                    modifiers = KeyCodeDisplay.defaultModifiers
                    validate()
                }
                Button(isRecording ? language.text("取消", "Cancel") : language.text("录制", "Record")) {
                    toggleRecording()
                }
            }
            if isRecording {
                Text(language.text("请按下包含 Command、Option、Control 或 Shift 的快捷键。", "Press a key with Command, Option, Control, or Shift."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(.system(size: 12))
                    .foregroundColor(validationMessage == okMessage ? .secondary : .red)
            }
        }
        .onAppear { validate() }
        .onDisappear {
            stopRecording()
        }
    }

    private var display: String {
        var settings = AppSettings()
        settings.shortcutKeyCode = keyCode
        settings.shortcutModifiers = modifiers
        return settings.shortcutDisplay
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let carbonModifiers = carbonFlags(from: event.modifierFlags)
            let candidateKey = UInt32(event.keyCode)
            guard carbonModifiers != 0 else {
                validationMessage = language.text("快捷键至少需要一个修饰键。", "Shortcut must include at least one modifier.")
                return nil
            }
            guard !KeyCodeDisplay.isDisallowedShortcutKey(candidateKey) else {
                validationMessage = language.text("\(KeyCodeDisplay.name(for: candidateKey)) 不适合作为全局快捷键。", "\(KeyCodeDisplay.name(for: candidateKey)) is not a good global shortcut key.")
                return nil
            }
            keyCode = candidateKey
            modifiers = carbonModifiers
            validate()
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= 256 }
        if flags.contains(.shift) { value |= 512 }
        if flags.contains(.option) { value |= 2048 }
        if flags.contains(.control) { value |= 4096 }
        return value
    }

    private func validate() {
        if modifiers == 0 {
            validationMessage = language.text("快捷键至少需要一个修饰键。", "Shortcut must include at least one modifier.")
        } else if KeyCodeDisplay.isDisallowedShortcutKey(keyCode) {
            validationMessage = language.text("\(KeyCodeDisplay.name(for: keyCode)) 不适合作为全局快捷键。", "\(KeyCodeDisplay.name(for: keyCode)) is not a good global shortcut key.")
        } else if modifiers == KeyCodeDisplay.defaultModifiers && keyCode == KeyCodeDisplay.defaultKeyCode {
            validationMessage = language.text("快捷键可用。", "Shortcut looks good.")
        } else {
            validationMessage = okMessage
        }
    }

    private var okMessage: String {
        language.text("快捷键可用。", "Shortcut looks good.")
    }
}
