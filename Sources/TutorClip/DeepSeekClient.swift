import Foundation

@MainActor
protocol DeepSeekStreaming {
    func stream(messages: [DeepSeekMessage], onToken: @escaping @MainActor (String) -> Void) async throws
    func stream(messages: [DeepSeekMessage], temperatureOverride: Double?, onToken: @escaping @MainActor (String) -> Void) async throws
    func stream(messages: [DeepSeekMessage], temperatureOverride: Double?, modelOverride: String?, onToken: @escaping @MainActor (String) -> Void) async throws
    func stream(messages: [DeepSeekMessage], temperatureOverride: Double?, modelOverride: String?, thinkingMode: DeepSeekThinkingMode, onToken: @escaping @MainActor (String) -> Void) async throws
}

extension DeepSeekStreaming {
    func stream(messages: [DeepSeekMessage], temperatureOverride: Double?, onToken: @escaping @MainActor (String) -> Void) async throws {
        try await stream(messages: messages, onToken: onToken)
    }

    func stream(messages: [DeepSeekMessage], temperatureOverride: Double?, modelOverride: String?, onToken: @escaping @MainActor (String) -> Void) async throws {
        try await stream(messages: messages, temperatureOverride: temperatureOverride, onToken: onToken)
    }

    func stream(messages: [DeepSeekMessage], temperatureOverride: Double?, modelOverride: String?, thinkingMode: DeepSeekThinkingMode, onToken: @escaping @MainActor (String) -> Void) async throws {
        try await stream(messages: messages, temperatureOverride: temperatureOverride, modelOverride: modelOverride, onToken: onToken)
    }

}

enum DeepSeekThinkingMode: Equatable {
    case disabled
    case high
}

enum DeepSeekError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case badResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "DeepSeek API Key is not configured."
        case .invalidURL:
            return "DeepSeek Base URL is invalid."
        case .badResponse(let message):
            return message
        case .network(let message):
            return message
        }
    }
}

@MainActor
final class DeepSeekClient: DeepSeekStreaming {
    static let requestTimeout: TimeInterval = 30

    private let configLoader: ConfigLoader
    private let settingsStore: SettingsStore
    private let transport = DeepSeekTransport()

    init(configLoader: ConfigLoader, settingsStore: SettingsStore) {
        self.configLoader = configLoader
        self.settingsStore = settingsStore
    }

    func stream(messages: [DeepSeekMessage], onToken: @escaping @MainActor (String) -> Void) async throws {
        try await stream(messages: messages, temperatureOverride: nil, modelOverride: nil, onToken: onToken)
    }

    func stream(messages: [DeepSeekMessage], temperatureOverride: Double?, onToken: @escaping @MainActor (String) -> Void) async throws {
        try await stream(messages: messages, temperatureOverride: temperatureOverride, modelOverride: nil, onToken: onToken)
    }

    func stream(messages: [DeepSeekMessage], temperatureOverride: Double?, modelOverride: String?, onToken: @escaping @MainActor (String) -> Void) async throws {
        try await stream(
            messages: messages,
            temperatureOverride: temperatureOverride,
            modelOverride: modelOverride,
            thinkingMode: .disabled,
            onToken: onToken
        )
    }

    func stream(messages: [DeepSeekMessage], temperatureOverride: Double?, modelOverride: String?, thinkingMode: DeepSeekThinkingMode, onToken: @escaping @MainActor (String) -> Void) async throws {
        let config = configLoader.currentConfig(settings: settingsStore.settings)
        let language = settingsStore.settings.appLanguage
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw DeepSeekError.badResponse(language.text("DeepSeek API Key 未配置。", "DeepSeek API Key is not configured."))
        }
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw DeepSeekError.badResponse(language.text("DeepSeek Base URL 无效。", "DeepSeek Base URL is invalid."))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let model = modelOverride ?? DeepSeekModel.pro.rawValue
        let body = DeepSeekRequest(
            model: model,
            messages: messages,
            temperature: temperatureOverride ?? settingsStore.settings.temperature,
            stream: true,
            thinking: thinkingMode.requestThinking,
            reasoningEffort: thinkingMode.reasoningEffort
        )
        request.httpBody = try JSONEncoder().encode(body)

        do {
            try await transport.stream(request: request, onToken: onToken)
        } catch is CancellationError {
            throw CancellationError()
        } catch DeepSeekTransportError.emptyResponse {
            throw DeepSeekError.badResponse(
                language.text("DeepSeek 返回了空响应，请重试。", "DeepSeek returned an empty response. Try again.")
            )
        } catch DeepSeekTransportError.httpStatus(let statusCode) {
            throw DeepSeekError.badResponse(httpMessage(for: statusCode))
        } catch DeepSeekTransportError.network(let error) {
            if error.code == .cancelled {
                throw CancellationError()
            }
            throw DeepSeekError.network(networkMessage(for: error))
        }
    }

    private func networkMessage(for error: URLError) -> String {
        let language = settingsStore.settings.appLanguage
        switch error.code {
        case .notConnectedToInternet:
            return language.text("网络不可用，请检查网络连接。", "Network unavailable. Check your internet connection.")
        case .timedOut:
            return language.text("DeepSeek 请求超时，请重试。", "DeepSeek request timed out. Try again.")
        case .cannotFindHost, .cannotConnectToHost:
            return language.text("无法连接 DeepSeek，请检查 Base URL 或网络。", "Cannot connect to DeepSeek. Check Base URL or network.")
        default:
            return error.localizedDescription
        }
    }

    private func httpMessage(for statusCode: Int) -> String {
        let language = settingsStore.settings.appLanguage
        switch statusCode {
        case 401:
            return language.text("DeepSeek 鉴权失败，请检查 API Key。", "DeepSeek authentication failed. Check your API key.")
        case 402:
            return language.text("DeepSeek 账户余额不足。", "DeepSeek account has insufficient balance.")
        case 429:
            return language.text("DeepSeek 请求过于频繁，请稍后重试。", "DeepSeek rate limit reached. Try again later.")
        case 500...599:
            return language.text("DeepSeek 服务错误 HTTP \(statusCode)，请重试。", "DeepSeek service error HTTP \(statusCode). Try again.")
        default:
            return language.text("DeepSeek 请求失败，HTTP \(statusCode)。", "DeepSeek request failed with HTTP \(statusCode).")
        }
    }
}

enum DeepSeekTransportError: Error {
    case httpStatus(Int)
    case network(URLError)
    case emptyResponse
}

actor DeepSeekTransport {
    func stream(
        request: URLRequest,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw DeepSeekTransportError.network(error)
        }

        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw DeepSeekTransportError.httpStatus(http.statusCode)
        }

        var contentTracker = DeepSeekStreamContentTracker()
        do {
            streamLoop: for try await line in bytes.lines {
                try Task.checkCancellation()
                switch DeepSeekStreamDecoder.decode(line) {
                case .token(let content):
                    contentTracker.record(content)
                    await onToken(content)
                case .done:
                    break streamLoop
                case .ignored, .malformed:
                    continue
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw DeepSeekTransportError.network(error)
        }

        guard contentTracker.hasVisibleContent else {
            throw DeepSeekTransportError.emptyResponse
        }
    }
}

struct DeepSeekMessage: Codable {
    var role: String
    var content: String
}

private struct DeepSeekRequest: Codable {
    struct Thinking: Codable {
        var type: String

        static let disabled = Thinking(type: "disabled")
    }

    var model: String
    var messages: [DeepSeekMessage]
    var temperature: Double
    var stream: Bool
    var thinking: Thinking?
    var reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case stream
        case thinking
        case reasoningEffort = "reasoning_effort"
    }
}

private extension DeepSeekThinkingMode {
    var requestThinking: DeepSeekRequest.Thinking {
        switch self {
        case .disabled:
            return .disabled
        case .high:
            return DeepSeekRequest.Thinking(type: "enabled")
        }
    }

    var reasoningEffort: String? {
        self == .high ? "high" : nil
    }
}

private struct DeepSeekStreamEvent: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            var content: String?
        }
        var delta: Delta
    }
    var choices: [Choice]
}

enum DeepSeekStreamLine: Equatable {
    case token(String)
    case done
    case ignored
    case malformed
}

enum DeepSeekStreamDecoder {
    static func decode(_ line: String) -> DeepSeekStreamLine {
        guard line.hasPrefix("data:") else { return .ignored }
        var payload = line.dropFirst(5)
        if payload.first == " " {
            payload = payload.dropFirst()
        }
        guard payload != "[DONE]" else { return .done }
        guard let data = String(payload).data(using: .utf8),
              let event = try? JSONDecoder().decode(DeepSeekStreamEvent.self, from: data) else {
            return .malformed
        }
        guard let content = event.choices.first?.delta.content else { return .ignored }
        return .token(content)
    }
}

struct DeepSeekStreamContentTracker {
    private(set) var hasVisibleContent = false

    mutating func record(_ content: String) {
        if content.contains(where: { !$0.isWhitespace }) {
            hasVisibleContent = true
        }
    }
}
