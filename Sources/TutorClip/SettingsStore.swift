import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings = AppSettings()
    @Published private(set) var persistenceError: String?
    @Published var shortcutRegistrationResult: ShortcutRegistrationResult = .unregistered

    private let url: URL

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tutorclip", isDirectory: true)
        url = base.appendingPathComponent("settings.json")
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            persistenceError = error.localizedDescription
            RuntimeLog.write("settings-directory-create-failed \(error.localizedDescription)")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder.tutorClip.decode(AppSettings.self, from: data)
            var migrated = decoded
            if migrated.ocrLanguage == .chinese {
                migrated.ocrLanguage = .english
            }
            if migrated.shortcutKeyCode == KeyCodeDisplay.legacyDefaultKeyCode,
               migrated.shortcutModifiers == KeyCodeDisplay.legacyDefaultModifiers {
                migrated.shortcutKeyCode = KeyCodeDisplay.defaultKeyCode
                migrated.shortcutModifiers = KeyCodeDisplay.defaultModifiers
            }
            settings = migrated
            if migrated != decoded {
                _ = persist(migrated)
            }
        } catch {
            persistenceError = error.localizedDescription
            RuntimeLog.write("settings-load-failed \(error.localizedDescription)")
        }
    }

    @discardableResult
    func update(_ transform: (inout AppSettings) -> Void) -> Bool {
        var copy = settings
        transform(&copy)
        guard persist(copy) else { return false }
        settings = copy
        return true
    }

    private func persist(_ value: AppSettings) -> Bool {
        do {
            let data = try JSONEncoder.tutorClip.encode(value)
            try data.write(to: url, options: [.atomic])
            persistenceError = nil
            return true
        } catch {
            persistenceError = error.localizedDescription
            RuntimeLog.write("settings-save-failed \(error.localizedDescription)")
            return false
        }
    }
}

extension JSONEncoder {
    static var tutorClip: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var tutorClip: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
