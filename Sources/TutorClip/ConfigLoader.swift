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

    private let configURL: URL

    init(baseDirectory: URL? = nil) {
        let directory = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tutorclip", isDirectory: true)
        configURL = directory.appendingPathComponent("config.json")
    }

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

    func persistTemporaryAPIKey(settings: AppSettings) throws {
        let key = temporaryAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ConfigPersistenceError.emptyAPIKey }
        var config = readFileConfig() ?? FileConfig()
        config.deepseekApiKey = key
        config.deepseekBaseURL = settings.deepseekBaseURL
        config.model = settings.deepseekModel
        try writeFileConfig(config)
    }

    func removePersistedAPIKey() throws {
        guard var config = readFileConfig() else { return }
        config.deepseekApiKey = nil
        try writeFileConfig(config)
    }

    private func readFileConfig() -> FileConfig? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(FileConfig.self, from: data)
    }

    private func writeFileConfig(_ config: FileConfig) throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private struct FileConfig: Codable {
        var deepseekApiKey: String?
        var deepseekBaseURL: String?
        var model: String?
    }
}

enum ConfigPersistenceError: LocalizedError {
    case emptyAPIKey

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey: return "API Key is empty."
        }
    }
}
