import Foundation

enum OCRLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case chinese
    case automatic

    var id: String { rawValue }

    var recognitionLanguages: [String] {
        switch self {
        case .english: return ["en-US"]
        case .chinese: return ["zh-Hans", "en-US"]
        case .automatic: return []
        }
    }

}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    func text(_ chinese: String, _ english: String) -> String {
        switch self {
        case .chinese: return chinese
        case .english: return english
        }
    }
}

struct AppSettings: Codable, Equatable {
    var shortcutKeyCode: UInt32 = KeyCodeDisplay.defaultKeyCode
    var shortcutModifiers: UInt32 = KeyCodeDisplay.defaultModifiers
    var historyEnabled: Bool = true
    var learningProgressEnabled: Bool = true
    var launchAtLogin: Bool = false
    var ocrLanguage: OCRLanguage = .english
    var appLanguage: AppLanguage = .chinese
    var deepseekBaseURL: String = "https://api.deepseek.com"
    var deepseekModel: String = "deepseek-chat"
    var temperature: Double = 0.3
    var hasCompletedOnboarding: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        shortcutKeyCode = try values.decodeIfPresent(UInt32.self, forKey: .shortcutKeyCode) ?? shortcutKeyCode
        shortcutModifiers = try values.decodeIfPresent(UInt32.self, forKey: .shortcutModifiers) ?? shortcutModifiers
        historyEnabled = try values.decodeIfPresent(Bool.self, forKey: .historyEnabled) ?? historyEnabled
        learningProgressEnabled = try values.decodeIfPresent(Bool.self, forKey: .learningProgressEnabled) ?? learningProgressEnabled
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        ocrLanguage = try values.decodeIfPresent(OCRLanguage.self, forKey: .ocrLanguage) ?? ocrLanguage
        appLanguage = try values.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? appLanguage
        deepseekBaseURL = try values.decodeIfPresent(String.self, forKey: .deepseekBaseURL) ?? deepseekBaseURL
        deepseekModel = try values.decodeIfPresent(String.self, forKey: .deepseekModel) ?? deepseekModel
        temperature = try values.decodeIfPresent(Double.self, forKey: .temperature) ?? temperature
        hasCompletedOnboarding = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }

    var shortcutDisplay: String {
        let parts: [(UInt32, String)] = [
            (4096, "Control"),
            (2048, "Option"),
            (512, "Shift"),
            (256, "Command")
        ]
        let modifierText = parts.filter { shortcutModifiers & $0.0 != 0 }.map(\.1)
        let key = KeyCodeDisplay.name(for: shortcutKeyCode)
        return (modifierText + [key]).joined(separator: " + ")
    }
}
