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

enum DeepSeekModel: String, Codable, CaseIterable, Identifiable {
    case flash = "deepseek-v4-flash"
    case pro = "deepseek-v4-pro"

    var id: String { rawValue }

    init(modelID: String) {
        self = modelID == Self.pro.rawValue ? .pro : .flash
    }

    static func normalizedModelID(_ modelID: String) -> String {
        switch modelID {
        case "deepseek-chat", "deepseek-reasoner": return Self.flash.rawValue
        default: return modelID
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .flash: return language.text("Flash（更快）", "Flash (Faster)")
        case .pro: return language.text("Pro（更强推理）", "Pro (Stronger reasoning)")
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
    var deepseekModel: String = DeepSeekModel.flash.rawValue
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
        let storedModel = try values.decodeIfPresent(String.self, forKey: .deepseekModel) ?? deepseekModel
        deepseekModel = DeepSeekModel.normalizedModelID(storedModel)
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
