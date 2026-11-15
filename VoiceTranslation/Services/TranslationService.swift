import Foundation
import Combine

@MainActor
class TranslationService: ObservableObject {
    @Published var translatedText = ""
    @Published var isTranslating = false
    @Published var error: TranslationError?
    private(set) var failureIsRetryable = false
    private(set) var retryAfter: TimeInterval?
    var shouldRetryFailure: Bool { failureIsRetryable }
    var context = TranslationContext()

    private let session: URLSession
    private let appSettings: AppSettings
    private var fullTranslatedText = ""
    private var generation = 0

    struct OpenAIRequest: Codable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double
        let max_tokens: Int
    }
    struct Message: Codable { let role: String; let content: String }
    struct OpenAIResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable {
            let delta: Delta?
            let message: ChatMessage?
            let finish_reason: String?
        }
        struct Delta: Codable { let content: String? }
        struct ChatMessage: Codable { let content: String? }
    }
    private struct Failure: Error {
        let error: TranslationError
        let retryable: Bool
        var after: TimeInterval? = nil
    }

    init(appSettings: AppSettings = AppSettings(), session: URLSession = .shared) {
        self.appSettings = appSettings
        self.session = session
    }

    /// Independent stream state, sharing the same credentials and URLSession connection pool.
    func makeWorker() -> TranslationService {
        TranslationService(appSettings: appSettings, session: session)
    }

    func getFullTranslatedText() -> String { fullTranslatedText }

    func clearTranslation() {
        generation += 1
        translatedText = ""
        fullTranslatedText = ""
        isTranslating = false
        error = nil
        failureIsRetryable = false
        retryAfter = nil
        context = TranslationContext()
    }

    func translateText(_ text: String, direction: LanguageDirection, appendToExisting: Bool = false) async {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LiveTranscript.isMeaningful(source), !isTranslating, !Task.isCancelled else { return }
        generation += 1
        let run = generation
        isTranslating = true
        translatedText = ""
        error = nil
        failureIsRetryable = false
        retryAfter = nil
        defer { if generation == run { isTranslating = false } }
        do {
            guard !appSettings.currentAPIKey.isEmpty else {
                throw Failure(error: .apiKeyMissing, retryable: false)
            }
            let request = try createOpenAIRequest(text: source, direction: direction, apiKey: appSettings.currentAPIKey)
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw Failure(error: .invalidResponse, retryable: true)
            }
            guard response.statusCode == 200 else { throw Self.failure(for: response) }
            var complete = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard generation == run else { return }
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                if payload == "[DONE]" { complete = true; break }
                guard let data = payload.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(OpenAIResponse.self, from: data) else {
                    throw Failure(error: .invalidResponse, retryable: true)
                }
                if let part = chunk.choices.first?.delta?.content { translatedText += part }
                if let finish = chunk.choices.first?.finish_reason {
                    guard finish == "stop" else {
                        throw Failure(error: .networkError("这段翻译未完成，正在尝试补译。"), retryable: true)
                    }
                    complete = true
                    break
                }
            }
            try Task.checkCancellation()
            guard generation == run else { return }
            guard complete, !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Failure(error: .networkError("翻译回复中断或为空。"), retryable: true)
            }
            fullTranslatedText += translatedText
        } catch {
            guard generation == run else { return }
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            let failure = (error as? Failure) ?? Failure(error: .networkError(error.localizedDescription),
                retryable: Self.isTransient(error))
            translatedText = ""
            failureIsRetryable = failure.retryable
            retryAfter = failure.after
            self.error = failure.error
        }
    }

    func createOpenAIRequest(text: String, direction: LanguageDirection, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: appSettings.currentAPIBaseURL),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            throw Failure(error: .networkError("翻译服务地址不正确，请检查设置。"), retryable: false)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let user = direction == .englishToChinese ? "Translate to Chinese: \(text)" : "翻译成英文: \(text)"
        let system = direction.prompt + context.instruction(for: text, direction: direction)
        let body = OpenAIRequest(model: appSettings.currentModel,
            messages: [Message(role: "system", content: system), Message(role: "user", content: user)],
            stream: true,
            temperature: appSettings.apiProvider == .openAI ? Constants.OpenAI.temperature : Constants.CustomAPI.temperature,
            max_tokens: appSettings.apiProvider == .openAI ? Constants.OpenAI.maxTokens : Constants.CustomAPI.maxTokens)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func failure(for response: HTTPURLResponse) -> Failure {
        let code = response.statusCode
        let retryable = [408, 425, 429].contains(code) || (500...599).contains(code)
        let error: TranslationError
        switch code {
        case 401, 403: error = .openAIError("翻译服务未授权，请检查设置中的密钥。")
        case 429: error = .rateLimitExceeded
        default: error = .openAIError("翻译服务暂未完成请求（\(code)）。")
        }
        return Failure(error: error, retryable: retryable, after: retryDelay(response.value(forHTTPHeaderField: "Retry-After")))
    }

    static func retryDelay(_ header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header else { return nil }
        if let seconds = Double(header), seconds.isFinite { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: header).map { max(0, $0.timeIntervalSince(now)) }
    }

    private static func isTransient(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable,
                .internationalRoamingOff, .dataNotAllowed].contains(error.code)
    }
}
