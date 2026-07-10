import Foundation

struct DeepSeekConfig {
    enum KeySource: String {
        case environment = "Environment"
        case configFile = "Config file"
        case memory = "Temporary memory"
        case missing = "Not configured"
    }

    var apiKey: String?
    var baseURL: String
    var model: String
    var keySource: KeySource
}

@MainActor
final class ConfigLoader: ObservableObject {
    @Published var temporaryAPIKey: String = ""

    private let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".tutorclip", isDirectory: true)
        .appendingPathComponent("config.json")

    func currentConfig(settings: AppSettings) -> DeepSeekConfig {
        if let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty {
            return DeepSeekConfig(apiKey: key, baseURL: settings.deepseekBaseURL, model: settings.deepseekModel, keySource: .environment)
        }

        if let fileConfig = readFileConfig(), let key = fileConfig.deepseekApiKey, !key.isEmpty {
            return DeepSeekConfig(
                apiKey: key,
                baseURL: fileConfig.deepseekBaseURL ?? settings.deepseekBaseURL,
                model: fileConfig.model ?? settings.deepseekModel,
                keySource: .configFile
            )
        }

        if !temporaryAPIKey.isEmpty {
            return DeepSeekConfig(apiKey: temporaryAPIKey, baseURL: settings.deepseekBaseURL, model: settings.deepseekModel, keySource: .memory)
        }

        return DeepSeekConfig(apiKey: nil, baseURL: settings.deepseekBaseURL, model: settings.deepseekModel, keySource: .missing)
    }

    func configFilePath() -> String {
        configURL.path
    }

    private func readFileConfig() -> FileConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(FileConfig.self, from: data)
    }

    private struct FileConfig: Codable {
        var deepseekApiKey: String?
        var deepseekBaseURL: String?
        var model: String?
    }
}
