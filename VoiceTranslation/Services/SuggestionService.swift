//
//  SuggestionService.swift
//  VoiceTranslation
//
//  Generates context-aware conversation suggestions by calling the
//  same OpenAI API that the translation service uses. Suggestions
//  are generated based on recent conversation entries, ensuring
//  they are relevant to what was actually said.
//
//  Created on 2026-03-05.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class SuggestionService: ObservableObject {

    // MARK: - Published Properties

    @Published var suggestions: [ChatSuggestion] = []
    @Published var isExpanded: Bool = false
    @Published var isGenerating: Bool = false

    /// Configurable debounce delay (seconds). Range: 0.5 ~ 10.0
    /// Lower = faster suggestions, Higher = wait for more context
    @Published var debounceDelay: TimeInterval {
        didSet {
            UserDefaults.standard.set(debounceDelay, forKey: "suggestion_debounce_delay")
        }
    }

    // MARK: - Private Properties

    /// Debounce timer to avoid regenerating on every keystroke
    private var generateTimer: Timer?
    private var generationTask: Task<Void, Never>?
    private var generation = UUID()
    var session: URLSession = .shared

    /// Maximum number of suggestions to generate per request
    private let maxSuggestions = 4

    /// AppSettings reference for API configuration (set externally)
    var appSettings: AppSettings?

    /// Track the last context hash to avoid regenerating for same content
    private var lastContextHash: Int = 0

    /// Minimum interval between API calls — dynamically follows debounceDelay
    private var minGenerateInterval: TimeInterval {
        return max(debounceDelay, 2.0)
    }
    private var lastGenerateTime: Date = .distantPast

    // MARK: - Init

    init() {
        let saved = UserDefaults.standard.double(forKey: "suggestion_debounce_delay")
        self.debounceDelay = saved > 0 ? saved : 2.0
    }

    // MARK: - Public Methods

    /// Generate suggestions based on recent conversation entries.
    /// Debounces using configurable delay.
    func generateSuggestions(
        from entries: [TranslationEntryModel],
        direction: LanguageDirection
    ) {
        // Debounce: cancel any pending generation
        generateTimer?.invalidate()
        let token = generation
        generateTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.generationTask = Task { await self.performGeneration(from: entries, direction: direction, token: token) }
            }
        }
    }

    /// Manually refresh suggestions (user taps refresh button)
    func refresh(
        from entries: [TranslationEntryModel],
        direction: LanguageDirection
    ) {
        // Force refresh: reset hash so it won't skip
        lastContextHash = 0
        generationTask?.cancel()
        let token = generation
        generationTask = Task {
            await performGeneration(from: entries, direction: direction, token: token)
        }
    }

    func clearDeletedContent() {
        generation = UUID()
        generateTimer?.invalidate()
        generateTimer = nil
        generationTask?.cancel()
        generationTask = nil
        suggestions = []
        isGenerating = false
        lastContextHash = 0
        lastGenerateTime = .distantPast
    }

    /// Toggle expanded/collapsed state
    func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isExpanded.toggle()
        }
    }

    // MARK: - Core Generation (OpenAI API)

    private func performGeneration(
        from entries: [TranslationEntryModel],
        direction: LanguageDirection,
        token: UUID
    ) async {
        guard generation == token, !Task.isCancelled else { return }
        // Don't generate if no conversation yet
        guard !entries.isEmpty else {
            withAnimation(.easeInOut(duration: 0.2)) {
                suggestions = []
            }
            return
        }

        // Rate limit: don't call API too frequently
        let elapsed = Date().timeIntervalSince(lastGenerateTime)
        guard elapsed >= minGenerateInterval else {
            print("💡 建议生成跳过：距上次生成仅 \(String(format: "%.1f", elapsed))s")
            return
        }

        // Build context from recent entries
        let context = buildContext(from: entries, direction: direction)

        // Check if context has changed
        let contextHash = context.hashValue
        guard contextHash != lastContextHash else {
            print("💡 建议生成跳过：对话内容无变化")
            return
        }

        // Check API availability
        guard let settings = appSettings, settings.canTranslate else {
            print("💡 建议生成跳过：API 未配置")
            return
        }

        // Start generation
        isGenerating = true
        lastContextHash = contextHash
        lastGenerateTime = Date()

        print("💡 开始生成上下文建议...")

        do {
            let newSuggestions = try await callOpenAIForSuggestions(
                context: context,
                direction: direction,
                settings: settings
            )

            guard generation == token, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                suggestions = newSuggestions
                isGenerating = false
            }

            print("💡 生成了 \(newSuggestions.count) 条上下文建议")

        } catch {
            guard generation == token, !Task.isCancelled else { return }
            print("💡 建议生成失败: \(error.localizedDescription)")
            isGenerating = false
            // Reset hash so next attempt won't be skipped
            lastContextHash = 0
        }
    }

    // MARK: - Context Building

    /// Build a conversation context string from recent entries
    private func buildContext(
        from entries: [TranslationEntryModel],
        direction: LanguageDirection
    ) -> String {
        // Take the last 6 entries max for context
        let recentEntries = entries.suffix(6)

        var lines: [String] = []
        for entry in recentEntries {
            if !entry.originalText.isEmpty {
                lines.append("原文: \(entry.originalText)")
            }
            if !entry.translatedText.isEmpty {
                lines.append("翻译: \(entry.translatedText)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - OpenAI API Call

    private func callOpenAIForSuggestions(
        context: String,
        direction: LanguageDirection,
        settings: AppSettings
    ) async throws -> [ChatSuggestion] {

        let apiKey = settings.currentAPIKey
        guard !apiKey.isEmpty else {
            throw SuggestionError.apiKeyMissing
        }

        guard let url = URL(string: settings.currentAPIBaseURL) else {
            throw SuggestionError.invalidURL
        }

        // Build the prompt — use distinct prompts per direction with concrete examples
        // to ensure the AI generates in the correct language
        let systemPrompt: String
        let userMessage: String

        switch direction {
        case .englishToChinese:
            // The other person speaks ENGLISH → suggestions must be in ENGLISH
            // with Chinese translation as reference for the user
            systemPrompt = """
            You are a conversation reply suggestion assistant.
            Based on the conversation context, generate \(maxSuggestions) reply suggestions.

            CRITICAL LANGUAGE RULES:
            - "primary" field MUST be in English (because the other person speaks English, I need to reply in English)
            - "secondary" field MUST be in Chinese (中文翻译，帮助我理解)
            - DO NOT put Chinese in the "primary" field
            - DO NOT put English in the "secondary" field

            Each suggestion has a tag: reply, question, action, or confirm.
            Suggestions must be closely related to the conversation, not generic templates.
            Keep each suggestion concise (under 25 words).

            Output format (strict JSON array only, no other text):
            [
              {"tag": "reply", "primary": "That sounds great, let me check the timeline.", "secondary": "听起来不错，让我看看时间线。"},
              {"tag": "question", "primary": "What's the expected deadline for this?", "secondary": "这个的预期截止日期是什么时候？"}
            ]
            """
            userMessage = "Conversation context:\n\(context)\n\nGenerate \(maxSuggestions) reply suggestions in English with Chinese translations."

        case .chineseToEnglish:
            // The other person speaks CHINESE → suggestions must be in CHINESE
            // with English translation as reference for the user
            systemPrompt = """
            你是一个对话回复建议助手。根据对话上下文，生成\(maxSuggestions)条回复建议。

            语言规则（必须严格遵守）：
            - "primary" 字段必须是中文（因为对方说中文，我需要用中文回复对方）
            - "secondary" 字段必须是英文（English translation，帮助我理解）
            - 绝对不要在 "primary" 中使用英文
            - 绝对不要在 "secondary" 中使用中文

            每条建议有一个标签：reply（回复）、question（提问）、action（行动）、confirm（确认）。
            建议必须和对话内容紧密相关，不要生成泛泛的模板。
            每条建议简短实用（不超过25个字）。

            输出格式（严格JSON数组，不要其他文字）：
            [
              {"tag": "reply", "primary": "好的，我来看看时间安排。", "secondary": "Sure, let me check the schedule."},
              {"tag": "question", "primary": "预期的截止日期是什么时候？", "secondary": "What's the expected deadline?"}
            ]
            """
            userMessage = "对话上下文：\n\(context)\n\n请生成\(maxSuggestions)条中文回复建议，附带英文翻译。"
        }

        // Build request (same structure as TranslationService)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        struct APIRequest: Codable {
            let model: String
            let messages: [APIMessage]
            let stream: Bool
            let temperature: Double
            let max_tokens: Int
        }
        struct APIMessage: Codable {
            let role: String
            let content: String
        }

        let body = APIRequest(
            model: settings.currentModel,
            messages: [
                APIMessage(role: "system", content: systemPrompt),
                APIMessage(role: "user", content: userMessage)
            ],
            stream: false,  // Non-streaming for suggestions (simpler to parse)
            temperature: 0.8,
            max_tokens: 500
        )

        request.httpBody = try JSONEncoder().encode(body)

        // Call API
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SuggestionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SuggestionError.apiError(httpResponse.statusCode)
        }

        // Parse response
        return try parseSuggestionResponse(data)
    }

    // MARK: - Response Parsing

    private func parseSuggestionResponse(_ data: Data) throws -> [ChatSuggestion] {
        // Standard OpenAI response structure
        struct APIResponse: Codable {
            let choices: [Choice]
            struct Choice: Codable {
                let message: Message?
            }
            struct Message: Codable {
                let content: String?
            }
        }

        let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)

        guard let content = apiResponse.choices.first?.message?.content else {
            throw SuggestionError.emptyResponse
        }

        // Extract JSON array from the response content
        // The model might wrap it in markdown code blocks
        let cleanedContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanedContent.data(using: .utf8) else {
            throw SuggestionError.parseError
        }

        struct SuggestionDTO: Codable {
            let tag: String
            let primary: String
            let secondary: String
        }

        let dtos = try JSONDecoder().decode([SuggestionDTO].self, from: jsonData)

        return dtos.prefix(maxSuggestions).map { dto in
            let tag: SuggestionTag
            switch dto.tag.lowercased() {
            case "reply":    tag = .reply
            case "question": tag = .question
            case "action":   tag = .action
            case "confirm":  tag = .confirm
            default:         tag = .reply
            }

            return ChatSuggestion(
                tag: tag,
                primaryText: dto.primary,
                secondaryText: dto.secondary
            )
        }
    }
}

// MARK: - Suggestion Errors

enum SuggestionError: LocalizedError {
    case apiKeyMissing
    case invalidURL
    case invalidResponse
    case apiError(Int)
    case emptyResponse
    case parseError

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:   return "API Key 未配置"
        case .invalidURL:      return "无效的 API URL"
        case .invalidResponse: return "无效的响应"
        case .apiError(let c): return "API 错误 (HTTP \(c))"
        case .emptyResponse:   return "响应内容为空"
        case .parseError:      return "建议解析失败"
        }
    }
}
