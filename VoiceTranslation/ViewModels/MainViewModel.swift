//
//  MainViewModel.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation
import SwiftUI
import Combine
import Speech
import AVFoundation
import ScreenCaptureKit
import CoreGraphics

// MARK: - Feedback Message Types
enum FeedbackMessageType {
    case info
    case success  
    case warning
    case error
    
    var color: Color {
        switch self {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
    
    var icon: String {
        switch self {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.circle"
        }
    }
}

// MARK: - Translation Session Model
struct TranslationSession: Codable {
    let id: UUID
    var originalText: String
    let direction: LanguageDirection
    let timestamp: String
    var translatedText: String
    var isCompleted: Bool
    var retryCount = 0
    var retryAt: Date?
    var failureMessage: String?
    var statusMessage = ""
    var manualOriginal: String?
    let createdAt: Date
    
    // Shared formatter — avoids creating DateFormatter per session
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    init(originalText: String, direction: LanguageDirection, createdAt: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.originalText = originalText
        self.direction = direction
        self.timestamp = Self.timestampFormatter.string(from: createdAt)
        self.translatedText = ""
        self.isCompleted = false
        self.createdAt = createdAt
    }
}

@MainActor
class MainViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentTab: Tab = .main
    @Published var showSettings = false
    @Published var showHistory = false
    @Published var isProcessing = false
    @Published var showFloatingWindow = false
    @Published var audioSourceFallbackMessage: String = ""
    
    private let permissionManager = PermissionManager.shared
    let audioQualityMonitor = AudioQualityMonitor()
    @Published var permissionGuideVisible = false
    @Published var permissionStatusSummary: String = PermissionManager.shared.getPermissionSummary()
    
    // 用户反馈机制
    @Published var extendedFeedbackMessage: String = ""
    @Published var feedbackMessageType: FeedbackMessageType = .info
    @Published var audioQualityStatus: String = AudioQualityStatus.silent.description
    @Published var systemAudioQualityScore: Float = Float(AudioQualityStatus.silent.percentage)
    
    // MARK: - Dependencies
    
    let speechRecognizer: SpeechRecognizer
    let translationService: TranslationService
    let historyManager: HistoryManager
    @Published var appSettings: AppSettings
    @Published var errorHandler: ErrorHandler
    let suggestionService = SuggestionService()
    
    // MARK: - Private Properties
    
    private var conversationID = UUID()
    private var conversationStartedAt = Date()
    private var isRestoringConversation = false
    private var lastSavedConversationData: Data?
    @Published var restoredConversationMessage = ""
    private let retryDelays: [TimeInterval]
    private var transcript = LiveTranscript()
    private var automaticSessionIDs = Set<UUID>()
    private var activeRequestText: String?
    private var translationTask: Task<Void, Never>?
    private var secondaryTask: Task<Void, Never>?
    private var secondaryService: TranslationService?
    private var secondarySessionID: UUID?
    private var secondaryRequestText: String?
    private var secondaryToken = UUID()
    private var secondarySubscription: AnyCancellable?
    private var translationPauseUntil: Date?

    private var transcriptEpoch = UUID()
    private var savedSessionRecords: [UUID: TranslationRecord] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // 结构化翻译条目 — 替代字符串拼接，性能更好，无需序列化/反序列化
    @Published var displayEntries: [TranslationEntryModel] = []
    
    // 兼容旧代码：从 displayEntries 生成纯文本（仅用于清空判断等场景）
    var accumulatedTranslations: String {
        displayEntries.map { $0.plainText }.joined(separator: "\n\n")
    }
    
    // FIFO 翻译队列系统
    private var translationQueue: [TranslationSession] = []
    private var currentSessionId: UUID?

    // 等待翻译的句子队列（翻译服务忙时暂存，避免丢句）
    private var pendingSentenceQueue: [UUID] = []
    
    // 原文管道：存储当前翻译会话的原文
    private var currentOriginalText = ""
    // 译文管道：存储当前翻译会话的译文
    private var currentTranslatedText = ""
    // 当前会话的时间戳
    private var currentSessionTimestamp = ""
    
    // MARK: - Initialization
    
    init(speechRecognizer: SpeechRecognizer? = nil,
         translationService: TranslationService? = nil,
         historyManager: HistoryManager? = nil,
         appSettings: AppSettings? = nil,
         errorHandler: ErrorHandler? = nil,
         retryDelays: [TimeInterval] = [2, 5, 12]) {
        
        let resolvedAppSettings = appSettings ?? AppSettings()
        let resolvedSpeechRecognizer = speechRecognizer ?? SpeechRecognizer()
        let resolvedTranslationService = translationService ?? TranslationService(appSettings: resolvedAppSettings)
        let resolvedHistoryManager = historyManager ?? HistoryManager()
        let resolvedErrorHandler = errorHandler ?? ErrorHandler()

        self.retryDelays = retryDelays
        self.speechRecognizer = resolvedSpeechRecognizer
        self.appSettings = resolvedAppSettings
        self.translationService = resolvedTranslationService
        self.historyManager = resolvedHistoryManager
        self.errorHandler = resolvedErrorHandler
        
        // 将 appSettings 注入到建议服务
        self.suggestionService.appSettings = resolvedAppSettings
        
        setupBindings()
        
        // 初始化音频输入源
        self.speechRecognizer.setAudioInputSource(self.appSettings.audioInputSource)
        
        if let saved = historyManager?.activeConversation() ?? resolvedHistoryManager.activeConversation() {
            restoreConversation(saved)
        }
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.checkpointConversation() }
            .store(in: &cancellables)
        // 保持用户设置的语言方向，不强制覆盖
    }
    
    
    // MARK: - Setup Bindings
    
    private func setupBindings() {
        historyManager.deletions.sink { [weak self] deletion in
            self?.applyHistoryDeletion(deletion)
        }.store(in: &cancellables)

        appSettings.$translationGlossary.combineLatest(appSettings.$selectedLanguageDirection)
            .sink { [weak self] terms, direction in
                guard let self else { return }
                self.speechRecognizer.setRecognitionGlossary(terms, direction: direction)
                self.transcript.protectedPhrases = self.speechRecognizer.recognitionHints
            }.store(in: &cancellables)

        speechRecognizer.$recognizedText
            .sink { [weak self] text in
                guard let self, self.speechRecognizer.isRecording else { return }
                self.observeTranscript(text)
            }
            .store(in: &cancellables)

        speechRecognizer.$recognitionSessionID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.flushTranscript()
                self.transcript = LiveTranscript()
            }
            .store(in: &cancellables)

        speechRecognizer.$finalizedText
            .dropFirst()
            .sink { [weak self] text in
                guard let self, self.speechRecognizer.isRecording else { return }
                self.observeTranscript(text)
                self.flushTranscript()
            }
            .store(in: &cancellables)

        Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                self.processDueRetries(at: now)
                guard self.speechRecognizer.isRecording else { return }
                let wait = self.appSettings.simultaneousTranslation ? 2.0 : 4.0
                self.submitTranscriptLines(self.transcript.drain(at: now, maxWait: wait, maxCharacters: self.automaticCharacterLimit))
            }
            .store(in: &cancellables)

        // 译文管道：监听翻译流式更新 - 使用 FIFO 队列确保时序
        translationService.$translatedText
            .sink { [weak self] translatedText in
                guard let self = self else { return }
                
                // 使用队列系统处理译文更新
                if !translatedText.isEmpty {
                    self.processTranslationUpdate(translatedText)
                }
            }
            .store(in: &cancellables)
        
        // 监听翻译错误
        translationService.$error
            .compactMap { $0 }
            .sink { [weak self] error in
                guard self?.currentSessionId == nil else { return }
                self?.errorHandler.handleError(error)
                self?.isProcessing = false
                // 将错误信息添加到累积记录
                self?.appendErrorToTranslationLog(error: error)
            }
            .store(in: &cancellables)
        
        // 监听语音识别状态变化 - 优化实时响应
        speechRecognizer.$isRecording
            .sink { [weak self] isRecording in
                if !isRecording {
                    self?.isProcessing = false
                    
                    self?.flushTranscript()
                }
            }
            .store(in: &cancellables)
        
        // 监听音频输入源变化
        appSettings.$audioInputSource
            .removeDuplicates()
            .sink { [weak self] audioSource in
                guard let self = self else { return }
                self.speechRecognizer.setAudioInputSource(audioSource)
                print("音频输入源已切换到: \(audioSource.displayName)")
            }
            .store(in: &cancellables)
        
        // 权限管理监控
        setupPermissionMonitoring()
        
        // 音频质量监控
        setupAudioQualityMonitoring()
        
        

    }
    
    // MARK: - Public Methods
    
    func startTranslation() {
        guard appSettings.canTranslate else {
            errorHandler.handleError(.apiKeyMissing)
            return
        }
        
        print("🎤 开始翻译会话 - 翻译方向: \(appSettings.selectedLanguageDirection.displayName)")
        print("🎤 语音识别语言: \(appSettings.selectedLanguageDirection.speechLocale)")
        print("🎤 音频输入源: \(appSettings.audioInputSource.displayName)")
        
        // 清除之前的回退消息
        audioSourceFallbackMessage = ""
        
        // 预检查系统音频权限（如果用户选择了系统音频）
        if appSettings.audioInputSource == .systemAudio,
           !ensureSystemAudioPermission() {
            isProcessing = false
            return
        }
        
        // 设置语音识别语言（确保语言设置与翻译方向同步）
        speechRecognizer.setLanguage(appSettings.selectedLanguageDirection.speechLocale)
        
        // 开始录音
        speechRecognizer.startRecording()
        isProcessing = true
        
        print("🎤 语音识别器已启动，等待语音输入...")
    }
    
    func stopTranslation() {
        observeTranscript(speechRecognizer.recognizedText)
        speechRecognizer.stopRecording()
        isProcessing = false
        
        flushTranscript()

        checkpointConversation()
    }
    
    func toggleRecording() {
        if speechRecognizer.isRecording {
            stopTranslation()
        } else {
            startTranslation()
        }
    }
    
    func clearText() {
        flushTranscript()
        checkpointConversation()
        guard !appSettings.keepHistory || (translationQueue.isEmpty && transcript.pendingText.isEmpty) || historyManager.saveError.isEmpty else { return }
        historyManager.finishActiveConversation()
        resetCurrentConversation()
    }

    private func resetCurrentConversation() {
        isRestoringConversation = true
        conversationID = UUID()
        conversationStartedAt = Date()
        lastSavedConversationData = nil
        restoredConversationMessage = ""
        cancelSecondaryTranslation()
        translationPauseUntil = nil
        translationTask?.cancel()
        translationTask = nil
        transcriptEpoch = UUID()
        transcript = LiveTranscript()
        automaticSessionIDs.removeAll()
        activeRequestText = nil
        savedSessionRecords.removeAll()
        speechRecognizer.clearRecognizedText()
        translationService.clearTranslation()
        // 清空结构化显示条目
        displayEntries = []
        // 重置双管道状态
        currentOriginalText = ""
        currentTranslatedText = ""
        currentSessionTimestamp = ""
        // 清空 FIFO 队列
        translationQueue.removeAll()
        pendingSentenceQueue.removeAll()
        currentSessionId = nil
        isRestoringConversation = false
        print("已重置所有翻译状态，包括增量翻译长度")
    }
    
    // MARK: - 同声传译模式
    
    private var automaticCharacterLimit: Int {
        appSettings.simultaneousTranslation ? max(10, Int(appSettings.simultaneousThreshold)) : 100
    }

    private func observeTranscript(_ text: String) {
        guard !text.isEmpty else { return }
        transcript.protectedPhrases = speechRecognizer.recognitionHints
        transcript.observe(text, at: Date())
        currentOriginalText = currentSessionId == nil ? transcript.pendingText : currentOriginalText
        submitTranscriptLines(transcript.drain(at: Date(), maxCharacters: automaticCharacterLimit))
        rebuildAccumulatedDisplay()
    }

    private func flushTranscript() {
        submitTranscriptLines(transcript.drain(at: Date(), force: true))
    }

    private func submitTranscriptLines(_ lines: [LiveTranscript.Line]) {
        for line in lines {
            guard !historyManager.isDeleted(line.id) else { continue }
            if let index = translationQueue.firstIndex(where: { $0.id == line.id }) {
                guard translationQueue[index].manualOriginal == nil,
                      translationQueue[index].originalText != line.text else { continue }
                translationQueue[index].originalText = line.text
                translationQueue[index].isCompleted = false
                translationQueue[index].retryCount = 0
                translationQueue[index].retryAt = nil
                translationQueue[index].failureMessage = nil
                translationQueue[index].statusMessage = "等待翻译..."
                // A stale translation must not be shown under revised words.
                translationQueue[index].translatedText = ""
                if currentSessionId == line.id {
                    currentOriginalText = line.text
                    currentTranslatedText = ""
                }
                if !pendingSentenceQueue.contains(line.id) { pendingSentenceQueue.append(line.id) }
            } else if LiveTranscript.isMeaningful(line.text) {
                translationQueue.append(TranslationSession(originalText: line.text,
                    direction: appSettings.selectedLanguageDirection, id: line.id))
                automaticSessionIDs.insert(line.id)
                translationQueue[translationQueue.count - 1].statusMessage = "等待翻译..."
                pendingSentenceQueue.append(line.id)
            }
        }
        processNextQueuedSentenceIfNeeded()
        rebuildAccumulatedDisplay()
    }


    
    /// Human edits are authoritative for this row, including later ASR revisions and restarts.
    @discardableResult
    func updateOriginalText(entryID: UUID, text: String) -> Bool {
        let corrected = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LiveTranscript.isMeaningful(corrected), corrected.count <= 4000,
              let index = translationQueue.firstIndex(where: { $0.id == entryID }) else { return false }
        if currentSessionId == entryID {
            translationTask?.cancel()
            translationTask = nil
            transcriptEpoch = UUID()
            translationService.clearTranslation()
            currentSessionId = nil
            activeRequestText = nil
            currentOriginalText = ""
            currentTranslatedText = ""
        }
        if secondarySessionID == entryID { cancelSecondaryTranslation() }
        let previous = translationQueue[index]
        for record in historyManager.translationHistory where record.id == entryID ||
            (record.timestamp == previous.createdAt && record.direction == previous.direction && record.originalText == previous.originalText) {
            historyManager.removeReplacedRecord(record)
        }
        savedSessionRecords.removeValue(forKey: entryID)
        transcript.protect(entryID)
        translationQueue[index].manualOriginal = corrected
        translationQueue[index].originalText = corrected
        translationQueue[index].translatedText = ""
        translationQueue[index].isCompleted = false
        translationQueue[index].failureMessage = nil
        translationQueue[index].retryCount = 0
        translationQueue[index].retryAt = nil
        translationQueue[index].statusMessage = "原文已修改，正在重新翻译..."
        pendingSentenceQueue.removeAll { $0 == entryID }
        pendingSentenceQueue.insert(entryID, at: 0)
        rebuildAccumulatedDisplay()
        processNextQueuedSentenceIfNeeded()
        return true
    }

    func saveCurrentTranslation() {
        if let sessionId = currentSessionId,
           let session = translationQueue.first(where: { $0.id == sessionId }) {
            saveSessionToHistoryIfNeeded(session)
            return
        }

        let originalText = currentOriginalText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            ? speechRecognizer.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            : currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = currentTranslatedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            ? translationService.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            : currentTranslatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !originalText.isEmpty && !translatedText.isEmpty else { return }
        
        let record = TranslationRecord(
            originalText: originalText,
            translatedText: translatedText,
            direction: appSettings.selectedLanguageDirection
        )
        
        historyManager.saveTranslation(record)
    }

    func exportCurrentSession() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        var exportText = "本次识别记录\n"
        exportText += "导出时间: \(dateFormatter.string(from: Date()))\n"
        exportText += "翻译方向: \(appSettings.selectedLanguageDirection.displayName)\n"
        exportText += "条目数量: \(displayEntries.count)\n\n"

        for (index, entry) in displayEntries.enumerated() {
            exportText += "[\(index + 1)] 时间: \(entry.timestamp)\n"

            if entry.isError {
                exportText += "提示: \(entry.originalText)\n\n"
                continue
            }

            exportText += "原文: \(entry.originalText)\n"
            exportText += "译文: \(entry.translatedText.isEmpty ? "翻译中..." : entry.translatedText)\n\n"
        }

        return exportText
    }
    
    func switchLanguageDirection() {
        let oldDirection = appSettings.selectedLanguageDirection
        
        switch appSettings.selectedLanguageDirection {
        case .englishToChinese:
            appSettings.selectedLanguageDirection = .chineseToEnglish
        case .chineseToEnglish:
            appSettings.selectedLanguageDirection = .englishToChinese
        }
        
        let newDirection = appSettings.selectedLanguageDirection
        
        print("🔄 切换翻译方向: \(oldDirection.displayName) → \(newDirection.displayName)")
        print("🎤 语音识别语言: \(oldDirection.speechLocale) → \(newDirection.speechLocale)")
        print("🌍 翻译提示词: \(newDirection.prompt.prefix(50))...")
        
        // 立即更新语音识别语言设置
        speechRecognizer.setLanguage(appSettings.selectedLanguageDirection.speechLocale)
        
        // 如果正在录音，需要重新启动以应用新的语言设置
        if speechRecognizer.isRecording {
            print("🔄 正在录音中，重新启动以应用新语言设置")
            let wasRecording = true
            stopTranslation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if wasRecording {
                    self?.startTranslation()
                }
            }
        }
        
        // 清空当前文本和重置状态
        clearText()
        
        // 强制触发UI更新
        objectWillChange.send()
    }
    
    // FIFO 系统：处理翻译更新
    private func processTranslationUpdate(_ translatedText: String) {
        if let id = currentSessionId, automaticSessionIDs.contains(id) {
            guard let session = translationQueue.first(where: { $0.id == id }),
                  session.originalText == activeRequestText else { return }
        }

        guard let sessionId = currentSessionId else { return }

        guard let sessionIndex = translationQueue.firstIndex(where: { $0.id == sessionId }) else { return }

        // 更新会话的译文
        translationQueue[sessionIndex].translatedText = translatedText
        
        // 只有当前活跃会话的翻译才显示
        if sessionId == currentSessionId {
            currentTranslatedText = translatedText
            print("✅ 译文已更新")
            rebuildAccumulatedDisplay()
        } else {
            print("⚠️ 非当前会话的翻译更新，已忽略 - 会话 ID: \(sessionId)")
        }
    }
    
    private func activateSession(_ sessionId: UUID) {
        guard let sessionIndex = translationQueue.firstIndex(where: { $0.id == sessionId }) else { return }
        let session = translationQueue[sessionIndex]

        currentSessionId = session.id
        currentOriginalText = session.originalText
        currentTranslatedText = session.translatedText
        currentSessionTimestamp = session.timestamp

        rebuildAccumulatedDisplay()
    }

    private func rebuildAccumulatedDisplay() {
        var entries = translationQueue.filter { LiveTranscript.isMeaningful($0.originalText) }
            .sorted { $0.createdAt < $1.createdAt }.map { session in
                TranslationEntryModel(id: session.id, originalText: session.originalText,
                    translatedText: session.translatedText, timestamp: session.timestamp,
                    createdAt: session.createdAt, isLive: !session.isCompleted,
                    statusMessage: session.statusMessage, canEditOriginal: true,
                    isManuallyEdited: session.manualOriginal != nil)
            }
        if currentSessionId == nil, !transcript.pendingText.isEmpty {
            entries.append(TranslationEntryModel(originalText: transcript.pendingText,
                isLive: speechRecognizer.isRecording))
        }
        for error in displayEntries.filter({ $0.isError }) {
            let index = entries.firstIndex(where: { $0.createdAt > error.createdAt }) ?? entries.endIndex
            entries.insert(error, at: index)
        }
        displayEntries = entries
        checkpointConversation()
    }

    // 标记当前会话为完成
    private func markCurrentSessionComplete(processQueue: Bool = true) {
        guard let sessionId = currentSessionId,
              let sessionIndex = translationQueue.firstIndex(where: { $0.id == sessionId }) else {
            return
        }
        
        translationQueue[sessionIndex].isCompleted = true
        translationQueue[sessionIndex].statusMessage = ""
        translationQueue[sessionIndex].failureMessage = nil
        translationQueue[sessionIndex].retryAt = nil
        let completedSession = translationQueue[sessionIndex]
        if !restoredConversationMessage.isEmpty && translationQueue.allSatisfy({ $0.isCompleted }) {
            restoredConversationMessage = "已恢复上次整场内容"
        }
        print("已标记会话完成 - ID: \(sessionId)")
        saveSessionToHistoryIfNeeded(completedSession)

        // 重置当前会话状态，确保下一句话开始新会话
        currentSessionId = nil
        currentOriginalText = ""
        currentTranslatedText = ""
        currentSessionTimestamp = ""

        // 先清空当前会话，再重建显示，确保已完成会话可见
        rebuildAccumulatedDisplay()

        // 处理待翻译队列
        if processQueue {
            processNextQueuedSentenceIfNeeded()
        }
    }

    private func markCurrentSessionCompleteIfCurrent(_ sessionId: UUID, source: String) {
        guard currentSessionId == sessionId else {
            print("⏭️ \(source)完成回调已跳过：当前会话已更新")
            return
        }
        markCurrentSessionComplete()
    }

    // MARK: - Pending Queue Helpers

    /// At most two independent streams. A slow line cannot hold up every later line.
    /// Rows stay in speech order regardless of the order replies arrive.
    private func processNextQueuedSentenceIfNeeded() {
        if let until = translationPauseUntil, until > Date() { return }
        while !pendingSentenceQueue.isEmpty {
            guard currentSessionId == nil || secondarySessionID == nil else { break }
            pendingSentenceQueue.removeAll { id in
                !translationQueue.contains(where: { $0.id == id && !$0.isCompleted })
            }
            guard let next = pendingSentenceQueue.firstIndex(where: { $0 != currentSessionId && $0 != secondarySessionID }) else { break }
            let id = pendingSentenceQueue.remove(at: next)
            guard let session = translationQueue.first(where: { $0.id == id }) else { continue }
            if currentSessionId == nil && !translationService.isTranslating {
                startTranslationSession(for: id, sentence: session.originalText, source: "队列")
            } else if secondarySessionID == nil {
                startSecondaryTranslation(session)
            } else {
                pendingSentenceQueue.insert(id, at: 0)
                break
            }
        }
    }

    private func cancelSecondaryTranslation() {
        secondaryToken = UUID()
        secondaryTask?.cancel()
        secondaryTask = nil
        secondarySubscription = nil
        secondaryService?.clearTranslation()
        secondarySessionID = nil
        secondaryRequestText = nil
    }

    private func startSecondaryTranslation(_ session: TranslationSession) {
        let service = secondaryService ?? translationService.makeWorker()
        secondaryService = service
        service.clearTranslation()
        let token = UUID()
        secondaryToken = token
        secondarySessionID = session.id
        secondaryRequestText = session.originalText
        if let i = translationQueue.firstIndex(where: { $0.id == session.id }) {
            translationQueue[i].statusMessage = session.retryCount > 0 ? "正在补译..." : "翻译中..."
        }
        secondarySubscription = service.$translatedText.sink { [weak self] text in
            guard let self, self.secondaryToken == token, !text.isEmpty,
                  let i = self.translationQueue.firstIndex(where: { $0.id == session.id }),
                  self.translationQueue[i].originalText == session.originalText else { return }
            self.translationQueue[i].translatedText = text
            self.rebuildAccumulatedDisplay()
        }
        service.context = contextForSession(session.id)
        secondaryTask = Task { [weak self] in
            await service.translateText(session.originalText, direction: session.direction)
            guard let self, !Task.isCancelled, self.secondaryToken == token,
                  let i = self.translationQueue.firstIndex(where: { $0.id == session.id }) else { return }
            if self.translationQueue[i].originalText == session.originalText {
                if service.error == nil, !service.isTranslating, !service.translatedText.isEmpty {
                    self.translationQueue[i].translatedText = service.translatedText
                    self.translationQueue[i].isCompleted = true
                    self.translationQueue[i].failureMessage = nil
                    self.translationQueue[i].retryAt = nil
                    self.translationQueue[i].statusMessage = ""
                    self.saveSessionToHistoryIfNeeded(self.translationQueue[i])
                } else {
                    self.recordTranslationFailure(at: i, service: service)
                }
            }
            self.secondarySessionID = nil
            self.secondaryRequestText = nil
            self.secondarySubscription = nil
            self.secondaryTask = nil
            self.rebuildAccumulatedDisplay()
            self.processNextQueuedSentenceIfNeeded()
        }
    }

    private func recordTranslationFailure(at index: Int, service: TranslationService) {
        translationQueue[index].translatedText = ""
        translationQueue[index].failureMessage = service.error?.localizedDescription ?? "翻译回复未完成。"
        let attempt = translationQueue[index].retryCount
        if service.shouldRetryFailure && attempt < retryDelays.count {
            let delay = max(retryDelays[attempt], service.retryAfter ?? 0)
            translationQueue[index].retryCount += 1
            translationQueue[index].retryAt = Date().addingTimeInterval(delay)
            translationQueue[index].statusMessage = "暂未译出，将自动补译（第 \(attempt + 1) 次）"
        } else {
            translationQueue[index].statusMessage = service.shouldRetryFailure
                ? "暂未译出，请稍后点击补译" : "暂未译出，请检查翻译设置后点击补译"
        }
        // Respect service rate limits across both workers, including queued new lines.
        if case .rateLimitExceeded? = service.error {
            let until = Date().addingTimeInterval(max(2, service.retryAfter ?? 2))
            translationPauseUntil = max(translationPauseUntil ?? until, until)
        }
    }

    var pendingTranslationCount: Int { translationQueue.filter { !$0.isCompleted }.count }
    var isTranslating: Bool { currentSessionId != nil || secondarySessionID != nil }

    private func startTranslationSession(for sessionId: UUID, sentence: String, source: String) {
        guard let i = translationQueue.firstIndex(where: { $0.id == sessionId }) else { return }
        translationQueue[i].retryAt = nil
        translationQueue[i].failureMessage = nil
        translationQueue[i].statusMessage = translationQueue[i].retryCount > 0 ? "正在补译..." : "翻译中..."
        activateSession(sessionId)
        activeRequestText = sentence
        let epoch = transcriptEpoch
        let direction = translationQueue[i].direction
        let context = contextForSession(sessionId)
        translationTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            self.translationService.context = context
            await self.translationService.translateText(sentence, direction: direction, appendToExisting: false)
            guard !Task.isCancelled, self.transcriptEpoch == epoch,
                  let index = self.translationQueue.firstIndex(where: { $0.id == sessionId }) else { return }
            guard self.translationQueue[index].originalText == sentence else {
                self.releaseCurrentSession()
                return
            }
            if self.translationService.error == nil, !self.translationService.isTranslating,
               !self.translationService.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.translationQueue[index].translatedText = self.translationService.translatedText
                self.activeRequestText = nil
                self.markCurrentSessionCompleteIfCurrent(sessionId, source: source)
            } else {
                self.recordTranslationFailure(at: index, service: self.translationService)
                self.releaseCurrentSession()
            }
        }
    }

    private func releaseCurrentSession() {
        currentSessionId = nil
        activeRequestText = nil
        currentOriginalText = ""
        currentTranslatedText = ""
        rebuildAccumulatedDisplay()
        processNextQueuedSentenceIfNeeded()
    }

    var untranslatedCount: Int { translationQueue.filter { $0.failureMessage != nil }.count }

    func retryFailedTranslations() {
        for i in translationQueue.indices where translationQueue[i].failureMessage != nil {
            translationQueue[i].retryCount = 0
            translationQueue[i].retryAt = Date()
            translationQueue[i].statusMessage = "等待补译..."
        }
        processDueRetries(at: Date())
    }

    private func processDueRetries(at now: Date) {
        for i in translationQueue.indices {
            guard let due = translationQueue[i].retryAt, due <= now,
                  translationQueue[i].id != currentSessionId, translationQueue[i].id != secondarySessionID else { continue }
            translationQueue[i].retryAt = nil
            translationQueue[i].statusMessage = "等待补译..."
            let id = translationQueue[i].id
            if !pendingSentenceQueue.contains(id) { pendingSentenceQueue.append(id) }
        }
        processNextQueuedSentenceIfNeeded()
        if untranslatedCount > 0 { rebuildAccumulatedDisplay() }
    }

    func contextForSession(_ id: UUID) -> TranslationContext {
        guard let index = translationQueue.firstIndex(where: { $0.id == id }) else { return TranslationContext() }
        let direction = translationQueue[index].direction
        var recent: [TranslationContext.Line] = []
        var budget = 2400
        if appSettings.useTranslationContext {
            for previous in translationQueue[..<index].reversed() where previous.failureMessage == nil
                && previous.direction == direction {
                let original = String(previous.originalText.prefix(600))
                // Parallel work can use an earlier original even before its reply finishes.
                let translation = previous.isCompleted ? String(previous.translatedText.prefix(600)) : ""
                let size = original.count + translation.count
                guard size <= budget else { break }
                recent.insert(.init(original: original, translation: translation), at: 0)
                budget -= size
                if recent.count == 6 { break }
            }
        }
        return TranslationContext(recent: recent, terms: appSettings.translationGlossary)
    }

    private func saveSessionToHistoryIfNeeded(_ session: TranslationSession) {
        guard appSettings.keepHistory else { return }

        let originalText = session.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = session.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !originalText.isEmpty, !translatedText.isEmpty else { return }

        let record = TranslationRecord(
            originalText: originalText,
            translatedText: translatedText,
            direction: session.direction,
            timestamp: session.createdAt, id: session.id
        )

        if let previous = savedSessionRecords[session.id] {
            historyManager.removeReplacedRecord(previous)
        }
        historyManager.saveTranslation(record)
        savedSessionRecords[session.id] = record
    }

    private func applyHistoryDeletion(_ deletion: HistoryManager.Deletion) {
        suggestionService.clearDeletedContent()
        TTSService.shared.stop()
        switch deletion {
        case .all:
            resetCurrentConversation()
        case .records(let ids):
            // Invalidate both workers before removing rows so late replies cannot restore them.
            transcriptEpoch = UUID()
            translationTask?.cancel()
            translationTask = nil
            translationService.clearTranslation()
            cancelSecondaryTranslation()
            currentSessionId = nil
            activeRequestText = nil
            currentOriginalText = ""
            currentTranslatedText = ""
            for id in ids { transcript.protect(id); savedSessionRecords.removeValue(forKey: id) }
            translationQueue.removeAll { ids.contains($0.id) }
            automaticSessionIDs.subtract(ids)
            pendingSentenceQueue = translationQueue.filter { !$0.isCompleted }.map(\.id)
            lastSavedConversationData = nil
            rebuildAccumulatedDisplay()
            checkpointConversation()
            processNextQueuedSentenceIfNeeded()
        }
    }

    func checkpointConversation() {
        guard !isRestoringConversation else { return }
        guard appSettings.keepHistory else { historyManager.finishActiveConversation(); return }
        var lines = translationQueue
        for i in lines.indices where !lines[i].isCompleted { lines[i].translatedText = "" }
        var saved = SavedConversation(id: conversationID, startedAt: conversationStartedAt,
            updatedAt: conversationStartedAt, lines: lines, draft: transcript.pendingText,
            draftDirection: appSettings.selectedLanguageDirection)
        guard let data = try? JSONEncoder().encode(saved), data != lastSavedConversationData else { return }
        saved.updatedAt = Date()
        historyManager.saveConversation(saved)
        if historyManager.saveError.isEmpty { lastSavedConversationData = data }
    }

    func restoreConversation(_ saved: SavedConversation) {
        guard !historyManager.isConversationDeleted(saved.id), !speechRecognizer.isRecording else { return }
        checkpointConversation()
        guard !appSettings.keepHistory || (translationQueue.isEmpty && transcript.pendingText.isEmpty) || historyManager.saveError.isEmpty else { return }
        cancelSecondaryTranslation()
        translationPauseUntil = nil
        translationTask?.cancel()
        translationService.clearTranslation()
        transcriptEpoch = UUID()
        isRestoringConversation = true
        appSettings.selectedLanguageDirection = saved.draftDirection
        conversationID = saved.id
        conversationStartedAt = saved.startedAt
        lastSavedConversationData = nil
        transcript = LiveTranscript()
        currentSessionId = nil
        activeRequestText = nil
        currentOriginalText = ""
        currentTranslatedText = ""
        savedSessionRecords.removeAll()
        displayEntries = []
        translationQueue = saved.lines.filter { !historyManager.isDeleted($0.id) }
        if LiveTranscript.isMeaningful(saved.draft) {
            translationQueue.append(TranslationSession(originalText: saved.draft, direction: saved.draftDirection, createdAt: saved.updatedAt))
        }
        automaticSessionIDs = Set(translationQueue.map(\.id))
        pendingSentenceQueue = []
        for i in translationQueue.indices where !translationQueue[i].isCompleted {
            translationQueue[i].translatedText = ""
            translationQueue[i].failureMessage = nil
            translationQueue[i].retryCount = 0
            translationQueue[i].retryAt = nil
            translationQueue[i].statusMessage = "等待补译..."
            pendingSentenceQueue.append(translationQueue[i].id)
        }
        isRestoringConversation = false
        restoredConversationMessage = pendingSentenceQueue.isEmpty ? "已恢复上次整场内容" : "已恢复上次内容，正在继续补译"
        rebuildAccumulatedDisplay()
        // Restore text automatically, but never start recording without a user action.
        Task { [weak self] in self?.processNextQueuedSentenceIfNeeded() }
    }

    func toggleTranslationLog() {
        showFloatingWindow.toggle()
    }
    
    // 诊断翻译功能状态
    func diagnoseTranslationStatus() {
        print("\n=== 翻译功能诊断报告 ===")
        print("🔧 当前翻译方向: \(appSettings.selectedLanguageDirection.displayName)")
        print("🔧 语音识别语言: \(appSettings.selectedLanguageDirection.speechLocale)")
        print("🔧 API Key状态: \(appSettings.isApiKeyValid ? "有效" : "无效")")
        print("🔧 翻译服务状态: \(translationService.isTranslating ? "正在翻译" : "空闲")")
        print("🔧 语音识别状态: 录音=\(speechRecognizer.isRecording), 监听=\(speechRecognizer.isListening)")
        print("🔧 已识别字数: \(speechRecognizer.recognizedText.count)")
        print("🔧 已翻译字数: \(translationService.translatedText.count)")
        print("🔧 音频输入源: \(appSettings.audioInputSource.displayName)")
        print("=======================\n")
    }

    // 手动触发翻译（空格键触发）
    func triggerTranslation() {
        let text = speechRecognizer.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LiveTranscript.isMeaningful(text) else { NSSound.beep(); return }
        showTranslationTriggered()
        observeTranscript(text)
        flushTranscript()
    }

    // 显示翻译触发的视觉反馈
    @Published var showSpaceKeyFeedback = false
    
    private func showTranslationTriggered() {
        showSpaceKeyFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showSpaceKeyFeedback = false
        }
    }
    
    private func appendErrorToTranslationLog(error: TranslationError) {
        let errorEntry = TranslationEntryModel.errorEntry(
            error.errorDescription ?? "未知错误"
        )
        displayEntries.append(errorEntry)
        print("错误信息已添加到翻译记录")
    }
    
    // MARK: - Audio Source Management
    
    /// Permission failure preserves the user's chosen source and leaves capture stopped.
    @discardableResult
    private func ensureSystemAudioPermission() -> Bool {
        // 仅在 macOS 12.3+ 上支持系统音频
        guard #available(macOS 12.3, *) else {
            showAudioSourceFallbackMessage("系统音频需要 macOS 12.3 或更高版本；麦克风未开启")
            return false
        }

        // macOS 14.2+ 使用 Core Audio Tap，不需要屏幕录制权限
        // Core Audio Tap 使用 AudioHardwareCreateProcessTap API，权限模型完全不同
        if #available(macOS 14.2, *) {
            print("✅ macOS 14.2+ 检测到，将使用 Core Audio Tap（不需要屏幕录制权限）")
            return true
        }

        // macOS 12.3 - 14.1 使用 ScreenCaptureKit，需要屏幕录制权限
        print("📺 macOS 12.3-14.1 检测到，需要屏幕录制权限（使用 ScreenCaptureKit）")

        // 先做静默检查
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        // 未授权时弹出系统权限请求
        print("🪟 未检测到屏幕录制权限，正在请求系统授权弹窗...")
        let granted = CGRequestScreenCaptureAccess()
        print("🪟 屏幕录制权限请求结果: \(granted ? "已授权" : "被拒绝")")

        guard granted else {
            showAudioSourceFallbackMessage("系统音频需要屏幕录制权限，请在系统设置中授权后重试；麦克风未开启")
            return false
        }

        return true
    }
    
    /// 权限检查方法（仅检查状态，不触发弹窗）
    private func checkScreenRecordingPermissionImproved() async -> Bool {
        // 只使用 CGPreflightScreenCaptureAccess 检查权限
        // 这个 API 不会触发权限弹窗
        let cgPreflightResult = CGPreflightScreenCaptureAccess()
        print("📊 屏幕录制权限检查 (CGPreflightScreenCaptureAccess): \(cgPreflightResult)")
        return cgPreflightResult
    }
    
    private func showAudioSourceFallbackMessage(_ message: String) {
        // 使用增强的反馈机制，延长显示时间到10秒
        showExtendedFeedbackMessage(message, type: .warning, duration: 10.0)
        
        // 兼容性：保留原有的短消息机制
        audioSourceFallbackMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if self.audioSourceFallbackMessage == message {
                self.audioSourceFallbackMessage = ""
            }
        }
    }
    
    // MARK: - Permission Management
    
    /// 检查所有权限状态
    func checkAllPermissions() {
        Task { [weak self] in
            guard let self else { return }
            await permissionManager.checkAllPermissions()
            await MainActor.run {
                self.updatePermissionStatusSummary()
            }
        }

        // 注意：移除了系统音频的自动诊断和刷新
        // 这些方法会使用 SCShareableContent.current 触发权限弹窗
        // 只在用户明确请求诊断时才调用 diagnoseSystemAudioPermissions()
    }
    
    /// 显示权限指导
    func showPermissionGuide() {
        permissionGuideVisible = true
    }
    
    /// 手动诊断系统音频权限
    public func diagnoseSystemAudioPermissions() {
        Task {
            let report = await speechRecognizer.diagnoseSystemAudioPermissions()
            print(report)
            
            // 可选：将报告保存到属性以便在UI中显示
            await MainActor.run {
                self.permissionStatusSummary = report
            }
        }
    }
    
    // MARK: - Permission & Audio Quality Monitoring
    
    /// 设置权限监控
    private func setupPermissionMonitoring() {
        permissionManager.permissionStatusChanges
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handlePermissionStatusChange(change)
            }
            .store(in: &cancellables)

        Task { [weak self] in
            guard let self else { return }
            await permissionManager.checkAllPermissions()
            await MainActor.run {
                self.updatePermissionStatusSummary()
            }
        }
    }
    
    /// 设置音频质量监控
    private func setupAudioQualityMonitoring() {
        // 监听音频录制状态变化
        speechRecognizer.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                if isRecording {
                    self?.audioQualityMonitor.startMonitoring()
                } else {
                    self?.audioQualityMonitor.stopMonitoring()
                }
            }
            .store(in: &cancellables)

        audioQualityMonitor.$currentStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateAudioQualityStatus(status)
            }
            .store(in: &cancellables)
    }
    
    private func handlePermissionStatusChange(_ change: PermissionStatusChange) {
        updatePermissionStatusSummary()

        guard change.type == .screenRecording else { return }

        if change.newStatus == .granted {
            audioSourceFallbackMessage = ""
        } else if appSettings.audioInputSource == .systemAudio {
            showExtendedFeedbackMessage("系统音频需要屏幕录制权限，请在系统设置中开启。", type: .warning, duration: 10.0)
        }
    }
    
    /// 更新音频质量状态
    private func updateAudioQualityStatus(_ status: AudioQualityStatus) {
        audioQualityStatus = status.description
        systemAudioQualityScore = Float(status.percentage)
    }
    
    /// 显示延长的反馈消息（替代短暂的audioSourceFallbackMessage）
    private func showExtendedFeedbackMessage(_ message: String, type: FeedbackMessageType, duration: TimeInterval = 8.0) {
        extendedFeedbackMessage = message
        feedbackMessageType = type
        
        // 指定时间后自动清除消息
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if self.extendedFeedbackMessage == message {
                self.extendedFeedbackMessage = ""
            }
        }
    }
    
    /// 获取音频质量诊断信息
    func getAudioQualityDiagnostics() -> String {
        return audioQualityMonitor.getQualityReport()
    }
    
    /// 隐藏权限指导
    func hidePermissionGuide() {
        permissionGuideVisible = false
    }

    /// 打开系统设置
    func openSystemPreferences(for type: PermissionType) {
        permissionManager.openSystemPreferencesForPermission(type)
    }

    /// 更新权限状态摘要
    private func updatePermissionStatusSummary() {
        permissionStatusSummary = permissionManager.getPermissionSummary()
    }
    
    /// 获取音频质量报告
    func getAudioQualityReport() -> String {
        return audioQualityMonitor.getQualityReport()
    }
    
    /// 重置音频质量数据
    func resetAudioQualityData() {
        audioQualityMonitor.resetData()
    }
}

// MARK: - Tab Enum

extension MainViewModel {
    enum Tab: String, CaseIterable {
        case main = "主界面"
        case history = "历史记录"
        case settings = "设置"
        
        var systemImage: String {
            switch self {
            case .main:
                return "mic.circle.fill"
            case .history:
                return "clock.fill"
            case .settings:
                return "gearshape.fill"
            }
        }
    }
}
