//
//  MainViewModelTests.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-11.
//

import XCTest
import Combine
import Speech
import AVFoundation
@testable import VoiceTranslation

@MainActor
final class MainViewModelTests: XCTestCase {
    
    var viewModel: MainViewModel!
    var mockSpeechRecognizer: MockSpeechRecognizer!
    var mockTranslationService: MockTranslationService!
    var mockHistoryManager: MockHistoryManager!
    var mockAppSettings: MockAppSettings!
    var mockErrorHandler: MockErrorHandler!
    var cancellables: Set<AnyCancellable>!

    private func clearTestDefaults() {
        let keys = [
            Constants.UserDefaults.openAIApiKey,
            Constants.UserDefaults.customAPIKey,
            Constants.UserDefaults.customAPIBaseURL,
            Constants.UserDefaults.customAPIModel,
            Constants.UserDefaults.apiProvider,
            Constants.UserDefaults.selectedLanguageDirection,
            Constants.UserDefaults.keepHistory,
            Constants.UserDefaults.maxHistoryItems,
            Constants.UserDefaults.autoDetectLanguage,
            Constants.UserDefaults.showTranslationAnimation,
            Constants.UserDefaults.audioInputSource,
            Constants.UserDefaults.hasCompletedOnboarding,
            "stored_\(Constants.UserDefaults.openAIApiKey)",
            "stored_\(Constants.UserDefaults.customAPIKey)",
            "simultaneousTranslation",
            "simultaneousThreshold",
            "translationGlossary",
            "useTranslationContext"
        ]

        let suites = [UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)]
        for defaults in suites.compactMap({ $0 }) {
            keys.forEach { defaults.removeObject(forKey: $0) }
            defaults.synchronize()
        }
    }
    
    override func setUpWithError() throws {
        clearTestDefaults()

        // 创建Mock对象
        mockSpeechRecognizer = MockSpeechRecognizer()
        mockTranslationService = MockTranslationService()
        mockHistoryManager = MockHistoryManager()
        mockAppSettings = MockAppSettings()
        mockErrorHandler = MockErrorHandler()
        
        // 创建带Mock依赖的ViewModel
        viewModel = MainViewModel(
            speechRecognizer: mockSpeechRecognizer,
            translationService: mockTranslationService,
            historyManager: mockHistoryManager,
            appSettings: mockAppSettings,
            errorHandler: mockErrorHandler
        )
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockSpeechRecognizer = nil
        mockTranslationService = nil
        mockHistoryManager = nil
        mockAppSettings = nil
        mockErrorHandler = nil
        cancellables = nil
        clearTestDefaults()
    }
    
    // MARK: - 初始化测试
    
    func testMainViewModelInitialization() throws {
        XCTAssertEqual(viewModel.currentTab, .main)
        XCTAssertFalse(viewModel.showSettings)
        XCTAssertFalse(viewModel.showHistory)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertNotNil(viewModel.speechRecognizer)
        XCTAssertNotNil(viewModel.translationService)
        XCTAssertNotNil(viewModel.historyManager)
        XCTAssertNotNil(viewModel.appSettings)
        XCTAssertNotNil(viewModel.errorHandler)
    }
    
    // MARK: - 翻译流程测试
    
    @MainActor
    func testStartTranslationWithValidApiKey() throws {
        // 设置有效的API Key
        mockAppSettings.canTranslate = true
        mockAppSettings.selectedLanguageDirection = .englishToChinese
        
        viewModel.startTranslation()
        
        XCTAssertTrue(mockSpeechRecognizer.startRecordingCalled)
        XCTAssertTrue(mockSpeechRecognizer.setLanguageCalled)
        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertEqual(mockSpeechRecognizer.lastLanguageSet, "en-US")
    }
    
    @MainActor
    func testStartTranslationWithoutApiKey() throws {
        // 设置无效的API Key
        mockAppSettings.canTranslate = false
        
        viewModel.startTranslation()
        
        XCTAssertFalse(mockSpeechRecognizer.startRecordingCalled)
        XCTAssertTrue(mockErrorHandler.handleErrorCalled)
        XCTAssertFalse(viewModel.isProcessing)
    }
    
    @MainActor
    func testStopTranslationWithText() throws {
        let expectation = self.expectation(description: "Translation completed")

        // 设置有识别到的文本
        mockSpeechRecognizer.recognizedText = "Hello world"
        mockTranslationService.onTranslateText = {
            expectation.fulfill()
        }
        
        viewModel.stopTranslation()

        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertTrue(mockSpeechRecognizer.stopRecordingCalled)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertTrue(mockTranslationService.translateTextCalled)
        XCTAssertEqual(mockTranslationService.lastTranslatedText, "Hello world")
    }
    
    @MainActor
    func testStopTranslationWithoutText() throws {
        // 没有识别到文本
        mockSpeechRecognizer.recognizedText = ""
        
        viewModel.stopTranslation()
        
        XCTAssertTrue(mockSpeechRecognizer.stopRecordingCalled)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertFalse(mockTranslationService.translateTextCalled)
    }
    
    @MainActor
    func testToggleRecordingStart() throws {
        mockSpeechRecognizer.isRecording = false
        mockAppSettings.canTranslate = true
        
        viewModel.toggleRecording()
        
        XCTAssertTrue(mockSpeechRecognizer.startRecordingCalled)
        XCTAssertTrue(viewModel.isProcessing)
    }
    
    @MainActor
    func testToggleRecordingStop() throws {
        mockSpeechRecognizer.isRecording = true
        mockSpeechRecognizer.recognizedText = "Test text"
        
        viewModel.toggleRecording()
        
        XCTAssertTrue(mockSpeechRecognizer.stopRecordingCalled)
        XCTAssertFalse(viewModel.isProcessing)
    }
    
    // MARK: - 文本管理测试
    
    @MainActor
    func testClearText() throws {
        mockSpeechRecognizer.recognizedText = "Some text"
        mockTranslationService.translatedText = "Some translation"
        
        viewModel.clearText()
        
        XCTAssertEqual(mockSpeechRecognizer.recognizedText, "")
        XCTAssertEqual(mockTranslationService.translatedText, "")
    }
    
    // MARK: - 历史记录管理测试
    
    @MainActor
    func testSaveCurrentTranslationWithValidData() throws {
        let expectation = self.expectation(description: "History saved")

        mockSpeechRecognizer.recognizedText = "Hello"
        mockTranslationService.mockTranslatedText = "你好"
        mockAppSettings.selectedLanguageDirection = .englishToChinese
        mockAppSettings.keepHistory = true
        mockHistoryManager.onSaveTranslation = {
            expectation.fulfill()
        }
        
        viewModel.triggerTranslation()

        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertTrue(mockHistoryManager.saveTranslationCalled)
        XCTAssertNotNil(mockHistoryManager.lastSavedRecord)
        XCTAssertEqual(mockHistoryManager.lastSavedRecord?.originalText, "Hello")
        XCTAssertEqual(mockHistoryManager.lastSavedRecord?.translatedText, "你好")
    }
    
    @MainActor
    func testSaveCurrentTranslationWithEmptyData() throws {
        mockSpeechRecognizer.recognizedText = ""
        mockTranslationService.translatedText = ""
        
        viewModel.saveCurrentTranslation()
        
        XCTAssertFalse(mockHistoryManager.saveTranslationCalled)
    }
    
    @MainActor
    func testSaveCurrentTranslationWithPartialData() throws {
        mockSpeechRecognizer.recognizedText = "Hello"
        mockTranslationService.translatedText = ""
        
        viewModel.saveCurrentTranslation()
        
        XCTAssertFalse(mockHistoryManager.saveTranslationCalled)
    }
    
    // MARK: - 语言切换测试
    
    @MainActor
    func testSwitchLanguageDirectionFromEnglishToChinese() throws {
        mockAppSettings.selectedLanguageDirection = .englishToChinese
        mockSpeechRecognizer.recognizedText = "Some text"
        mockTranslationService.translatedText = "Some translation"
        
        viewModel.switchLanguageDirection()
        
        XCTAssertEqual(mockAppSettings.selectedLanguageDirection, .chineseToEnglish)
        XCTAssertEqual(mockSpeechRecognizer.recognizedText, "")
        XCTAssertEqual(mockTranslationService.translatedText, "")
    }
    
    @MainActor
    func testSwitchLanguageDirectionFromChineseToEnglish() throws {
        mockAppSettings.selectedLanguageDirection = .chineseToEnglish
        
        viewModel.switchLanguageDirection()
        
        XCTAssertEqual(mockAppSettings.selectedLanguageDirection, .englishToChinese)
    }
    
    // MARK: - 响应式绑定测试
    
    @MainActor
    func testSpeechRecognitionTextBinding() throws {
        let expectation = self.expectation(description: "Translation triggered")
        
        // 设置翻译服务响应
        mockTranslationService.onTranslateText = {
            expectation.fulfill()
        }
        
        // finalizedText 是当前自动翻译的可靠触发边界
        mockSpeechRecognizer.isRecording = true
        mockSpeechRecognizer.finalizedText = "Hello world"
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    @MainActor
    func testTranslationCompletedBinding() throws {
        let expectation = self.expectation(description: "History saved")

        mockAppSettings.keepHistory = true
        mockSpeechRecognizer.recognizedText = "Hello"
        mockTranslationService.mockTranslatedText = "你好"
        mockHistoryManager.onSaveTranslation = {
            expectation.fulfill()
        }
        
        viewModel.triggerTranslation()
        
        wait(for: [expectation], timeout: 2.0)
    }

    @MainActor
    func testAutomaticFinalizedTranslationSavesToHistory() throws {
        let expectation = self.expectation(description: "Automatic history saved")

        mockAppSettings.keepHistory = true
        mockTranslationService.mockTranslatedText = "你好世界"
        mockHistoryManager.onSaveTranslation = {
            expectation.fulfill()
        }

        mockSpeechRecognizer.isRecording = true
        mockSpeechRecognizer.finalizedText = "Hello world"

        wait(for: [expectation], timeout: 3.0)

        XCTAssertTrue(mockHistoryManager.saveTranslationCalled)
        XCTAssertEqual(mockHistoryManager.lastSavedRecord?.originalText, "Hello world")
        XCTAssertEqual(mockHistoryManager.lastSavedRecord?.translatedText, "你好世界")
        XCTAssertEqual(mockHistoryManager.lastSavedRecord?.direction, .englishToChinese)
    }

    @MainActor
    func testExportCurrentSessionIncludesDisplayedEntries() throws {
        viewModel.displayEntries = [
            TranslationEntryModel(
                originalText: "Hello world",
                translatedText: "你好世界",
                timestamp: "10:00:00"
            ),
            TranslationEntryModel.errorEntry("网络异常")
        ]

        let exportText = viewModel.exportCurrentSession()

        XCTAssertTrue(exportText.contains("本次识别记录"))
        XCTAssertTrue(exportText.contains("翻译方向"))
        XCTAssertTrue(exportText.contains("Hello world"))
        XCTAssertTrue(exportText.contains("你好世界"))
        XCTAssertTrue(exportText.contains("网络异常"))
    }
    
    @MainActor
    func testTranslationErrorBinding() throws {
        let expectation = self.expectation(description: "Error handled")
        
        mockErrorHandler.onHandleError = {
            expectation.fulfill()
        }
        
        // 触发翻译错误
        mockTranslationService.error = .networkError("Test error")
        
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertFalse(viewModel.isProcessing)
    }
    
    @MainActor
    func testRecordingStateBinding() throws {
        let expectation = self.expectation(description: "Processing state updated")
        
        // 监听处理状态变化
        viewModel.$isProcessing
            .dropFirst()
            .removeDuplicates()
            .filter { !$0 }
            .prefix(1)
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        
        // 模拟录音状态变化
        mockSpeechRecognizer.isRecording = false
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - 边界条件测试
    
    @MainActor
    func testHandleWhitespaceOnlyText() throws {
        mockSpeechRecognizer.recognizedText = "   \n\t   "
        
        viewModel.stopTranslation()
        
        XCTAssertFalse(mockTranslationService.translateTextCalled)
    }
    
    @MainActor
    func testHandleVeryLongText() throws {
        let expectation = self.expectation(description: "Long text translated")

        let longText = String(repeating: "This is a very long text ", count: 1000)
        mockSpeechRecognizer.recognizedText = longText
        mockTranslationService.onTranslateText = { [weak self] in
            self?.mockTranslationService.onTranslateText = nil
            expectation.fulfill()
        }
        
        viewModel.stopTranslation()

        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertTrue(mockTranslationService.translateTextCalled)
        let originals = viewModel.displayEntries.map(\.originalText).joined(separator: " ")
        XCTAssertEqual(originals.split(whereSeparator: \.isWhitespace), longText.split(whereSeparator: \.isWhitespace))
        XCTAssertTrue(viewModel.displayEntries.count > 1, "Long continuous speech is split into bounded lines")
    }
    
    // MARK: - Tab管理测试
    
    func testTabEnumValues() throws {
        XCTAssertEqual(MainViewModel.Tab.main.rawValue, "主界面")
        XCTAssertEqual(MainViewModel.Tab.history.rawValue, "历史记录")
        XCTAssertEqual(MainViewModel.Tab.settings.rawValue, "设置")
        
        XCTAssertEqual(MainViewModel.Tab.main.systemImage, "mic.circle.fill")
        XCTAssertEqual(MainViewModel.Tab.history.systemImage, "clock.fill")
        XCTAssertEqual(MainViewModel.Tab.settings.systemImage, "gearshape.fill")
    }
    
    // MARK: - 内存管理测试
    
    func testMemoryManagement() throws {
        weak var weakViewModel: MainViewModel?
        
        autoreleasepool {
            let tempViewModel = MainViewModel()
            weakViewModel = tempViewModel
            tempViewModel.clearText()
            tempViewModel.switchLanguageDirection()
        }
        
        XCTAssertNil(weakViewModel, "MainViewModel should be deallocated")
    }
}

// MARK: - Mock Classes

class MockSpeechRecognizer: SpeechRecognizer {
    var startRecordingCalled = false
    var stopRecordingCalled = false
    var setLanguageCalled = false
    var lastLanguageSet: String?
    var lastAudioSourceSet: AudioInputSource?

    override func setAudioInputSource(_ source: AudioInputSource) {
        lastAudioSourceSet = source
        super.setAudioInputSource(source)
    }
    
    override func startRecording() {
        startRecordingCalled = true
        isRecording = true
    }
    
    override func stopRecording() {
        stopRecordingCalled = true
        isRecording = false
        isListening = false
    }
    
    override func setLanguage(_ languageCode: String) {
        setLanguageCalled = true
        lastLanguageSet = languageCode
    }
}

class MockTranslationService: TranslationService {
    override func makeWorker() -> TranslationService {
        let worker = MockTranslationService()
        worker.mockTranslatedText = mockTranslatedText
        return worker
    }
    var translateTextCalled = false
    var lastTranslatedText: String?
    var lastDirection: LanguageDirection?
    var mockTranslatedText = ""
    var onTranslateText: (() -> Void)?
    
    override func translateText(_ text: String, direction: LanguageDirection, appendToExisting: Bool = false) async {
        translateTextCalled = true
        lastTranslatedText = text
        lastDirection = direction
        
        await MainActor.run {
            self.isTranslating = true
        }
        
        // 模拟异步翻译
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await MainActor.run {
            self.translatedText = self.mockTranslatedText.isEmpty ? "Mock translation of: \(text)" : self.mockTranslatedText
            self.isTranslating = false
        }
        
        onTranslateText?()
    }
}

class MockHistoryManager: HistoryManager {
    var saveTranslationCalled = false
    var lastSavedRecord: TranslationRecord?
    var onSaveTranslation: (() -> Void)?
    
    override func saveTranslation(_ record: TranslationRecord) {
        saveTranslationCalled = true
        lastSavedRecord = record
        onSaveTranslation?()
    }
}

class MockAppSettings: AppSettings {
    override var canTranslate: Bool {
        get { _canTranslate }
        set { _canTranslate = newValue }
    }
    
    private var _canTranslate = true
    
    override init() {
        super.init()
        selectedLanguageDirection = .englishToChinese
    }
}

class MockErrorHandler: ErrorHandler {
    var handleErrorCalled = false
    var lastError: TranslationError?
    var onHandleError: (() -> Void)?
    
    override func handleError(_ error: TranslationError) {
        handleErrorCalled = true
        lastError = error
        super.handleError(error)
        onHandleError?()
    }
}

final class LiveTranscriptTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1000)

    func testShortAnswersAndNumbersAreMeaningful() {
        for text in ["No", "OK", "I", "不", "好", "2027", "3.14", "-5", "50%"] {
            XCTAssertTrue(LiveTranscript.isMeaningful(text), text)
        }
        for text in ["", " \n", "...", "，！？", "🎵"] {
            XCTAssertFalse(LiveTranscript.isMeaningful(text), text)
        }
    }

    func testRollingPhrasesAndAggregatedFinalDoNotDuplicateText() {
        var recognition = RecognitionTranscript()
        var transcript = LiveTranscript()
        var results: [UUID: String] = [:]
        let events: [(String, Double, Double)] = [
            ("No", 0, 0.5), ("OK", 2, 2.5), ("20", 5, 5.5), ("27", 7, 7.5),
            ("The", 10, 10.3),
            ("The first review is complete and the project team is ready", 10, 15),
            ("The first review is complete and the project team is ready to finish the work", 10, 18),
            ("The first review is complete and the project team is ready to finish the work", 10, 18)
        ]
        for (i, event) in events.enumerated() {
            let full = recognition.observe(event.0, start: event.1, end: event.2)
            let now = start.addingTimeInterval(Double(i) * 3)
            transcript.observe(full, at: now)
            for line in transcript.drain(at: now.addingTimeInterval(2), force: true) { results[line.id] = line.text }
        }
        let final = recognition.observe("No OK 2027 The first review is complete and the project team is ready to finish the work",
            start: 0, end: 18)
        XCTAssertEqual(final, "No OK 2027 The first review is complete and the project team is ready to finish the work")
        XCTAssertEqual(results.values.filter { $0.contains("first review") }.count, 1)
    }

    func testOverlappingRecognitionRevisionKeepsPreviousPhrase() {
        var recognition = RecognitionTranscript()
        _ = recognition.observe("No", start: 0, end: 0.5)
        _ = recognition.observe("We can go", start: 2, end: 4)
        XCTAssertEqual(recognition.observe("We may go", start: 2, end: 4.2), "No We may go")
    }

    func testActualZeroTimedDraftsPreserveShortAnswersAndRevisions() {
        var recognition = RecognitionTranscript()
        XCTAssertEqual(recognition.observe("No", start: 0, end: 0), "No")
        XCTAssertEqual(recognition.observe("No", start: 0.24, end: 0.75), "No")
        XCTAssertEqual(recognition.observe("OK", start: 0, end: 0), "No OK")
        XCTAssertEqual(recognition.observe("OK", start: 5.28, end: 6.09), "No OK")
        _ = recognition.observe("2020", start: 0, end: 0)
        XCTAssertEqual(recognition.observe("2027", start: 0, end: 0), "No OK 2027")
        XCTAssertEqual(recognition.observe("2027", start: 9.48, end: 11.04), "No OK 2027")
        _ = recognition.observe("The", start: 0, end: 0)
        _ = recognition.observe("The first review is complete", start: 0, end: 0)
        let settled = recognition.observe("The first review is complete", start: 14.55, end: 18)
        XCTAssertEqual(settled, "No OK 2027 The first review is complete")
    }

    func testSettledResultDoesNotDropWordsAlreadyHeard() {
        var recognition = RecognitionTranscript()
        let draft = "The first review is complete and the project team is ready to begin the next stage of the presentation"
        _ = recognition.observe(draft, start: 0, end: 0)
        XCTAssertEqual(recognition.observe("The first review is complete and the to begin the next dictation", start: 2, end: 15), draft)
        _ = recognition.observe("We can go", start: 0, end: 0)
        XCTAssertTrue(recognition.observe("We may go", start: 20, end: 22).hasSuffix("We may go"))
    }

    func testRevisedBoundariesNeverSplitAnEnglishWord() {
        var transcript = LiveTranscript()
        let original = "The first review is complete and the project team is ready to begin the next stage of the presentation because everyone has confirmed the schedule"
        transcript.observe(original, at: start)
        _ = transcript.drain(at: start)
        let revised = "The first review is complete and the to begin the next dictation because everyone has confirmed the schedule"
        transcript.observe(revised, at: start.addingTimeInterval(1))
        _ = transcript.drain(at: start.addingTimeInterval(1), force: true)
        let chars = Array(revised)
        for line in transcript.lines where line.end > 0 && line.end < chars.count {
            XCTAssertFalse(chars[line.end - 1].isLetter && chars[line.end].isLetter, "Cut inside a word at \(line.end)")
        }
        XCTAssertEqual(transcript.lines.map(\.text).joined().filter { !$0.isWhitespace }, revised.filter { !$0.isWhitespace })
    }

    func testSameLengthCorrectionReplacesOriginalLine() {
        var transcript = LiveTranscript()
        transcript.observe("We can go.", at: start)
        let original = transcript.drain(at: start)
        transcript.observe("We may go.", at: start.addingTimeInterval(1))
        let corrected = transcript.drain(at: start.addingTimeInterval(1))
        XCTAssertEqual(corrected.map(\.id), original.map(\.id))
        XCTAssertEqual(corrected.map(\.text), ["We may go."])
        XCTAssertTrue(transcript.drain(at: start.addingTimeInterval(2)).isEmpty)
    }

    func testInsertedAndDeletedWordsKeepFollowingSentence() {
        var transcript = LiveTranscript()
        transcript.observe("We go. They stay.", at: start)
        let original = transcript.drain(at: start)
        transcript.observe("We will go. They stay.", at: start.addingTimeInterval(1))
        let inserted = transcript.drain(at: start.addingTimeInterval(1))
        XCTAssertEqual(inserted.map(\.text), ["We will go."])
        XCTAssertEqual(inserted.first?.id, original.first?.id)
        transcript.observe("We go. They stay.", at: start.addingTimeInterval(2))
        XCTAssertEqual(transcript.drain(at: start.addingTimeInterval(2)).map(\.text), ["We go."])
        XCTAssertEqual(transcript.lines.map(\.text), ["We go.", "They stay."])
    }

    func testPauseFlushesSingleCharacterAndRepeatedAnswersKeepSeparateIDs() {
        var transcript = LiveTranscript()
        transcript.observe("好", at: start)
        XCTAssertTrue(transcript.drain(at: start.addingTimeInterval(0.5)).isEmpty)
        let first = transcript.drain(at: start.addingTimeInterval(0.9))
        XCTAssertEqual(first.map(\.text), ["好"])
        transcript.observe("好 好", at: start.addingTimeInterval(1))
        let second = transcript.drain(at: start.addingTimeInterval(2))
        XCTAssertEqual(second.map(\.text), ["好"])
        XCTAssertNotEqual(first.first?.id, second.first?.id)
    }

    func testContinuousSpeechTranslatesWithoutWaitingForSilence() {
        for source in ["we are discussing the new plan and we need to finish the review before tomorrow morning",
                       "我们今天继续讨论这个新的计划然后确认所有需要处理的问题以及明天早上的安排"] {
            var transcript = LiveTranscript()
            transcript.observe(source, at: start)
            transcript.observe(source + " more", at: start.addingTimeInterval(3.9))
            let lines = transcript.drain(at: start.addingTimeInterval(4.1))
            XCTAssertFalse(lines.isEmpty, source)
            XCTAssertFalse(transcript.pendingText.isEmpty)
            let remaining = transcript.drain(at: start.addingTimeInterval(4.2), force: true)
            let joined = transcript.lines.map(\.text).joined().filter { !$0.isWhitespace }
            XCTAssertEqual(joined, (source + " more").filter { !$0.isWhitespace })
        }
    }

    func testDecimalAndAbbreviationDoNotSplitSentence() {
        var transcript = LiveTranscript()
        transcript.observe("Dr. Chen expects 3.14 percent growth", at: start)
        XCTAssertTrue(transcript.drain(at: start).isEmpty)
        XCTAssertEqual(transcript.drain(at: start, force: true).map(\.text),
                       ["Dr. Chen expects 3.14 percent growth"])
    }

    func testFinalFlushIncludesTailExactlyOnce() {
        var transcript = LiveTranscript()
        transcript.observe("First sentence. unfinished tail", at: start)
        XCTAssertEqual(transcript.drain(at: start).map(\.text), ["First sentence."])
        XCTAssertEqual(transcript.drain(at: start, force: true).map(\.text), ["unfinished tail"])
        XCTAssertTrue(transcript.drain(at: start, force: true).isEmpty)
    }
}

@MainActor
final class LiveTranslationFlowTests: XCTestCase {
    private func makeFlow() -> (MainViewModel, MockSpeechRecognizer, MockTranslationService) {
        let speech = MockSpeechRecognizer()
        let service = MockTranslationService()
        let settings = MockAppSettings()
        settings.keepHistory = false
        let model = MainViewModel(speechRecognizer: speech, translationService: service,
                                 historyManager: MockHistoryManager(), appSettings: settings)
        return (model, speech, service)
    }

    private func settle(_ seconds: Double = 0.4) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testCapturedSystemRecognitionSequenceDoesNotLoseOrDuplicateLines() async throws {
        let (model, speech, _) = makeFlow()
        speech.isRecording = true
        var recognition = RecognitionTranscript()
        let events: [(String, Double, Double)] = [
            ("No", 0, 0), ("No", 0.24, 0.75),
            ("OK", 0, 0), ("OK", 5.28, 6.09),
            ("2020", 0, 0), ("2027", 0, 0), ("2027", 9.48, 11.04),
            ("The", 0, 0), ("The first review is complete", 0, 0),
            ("The first review is complete", 14.55, 18)
        ]
        for event in events {
            let text = recognition.observe(event.0, start: event.1, end: event.2)
            speech.recognizedText = text
            if event.2 > event.1 { speech.finalizedText = text }
        }
        try await settle(0.7)
        XCTAssertEqual(model.displayEntries.map(\.originalText), ["No", "OK", "2027", "The first review is complete"])
        for entry in model.displayEntries {
            XCTAssertEqual(entry.translatedText, "Mock translation of: \(entry.originalText)")
        }
        model.stopTranslation()
    }

    func testSpeechEventsAreAppliedBeforeClearAndNewSpeech() async throws {
        let (model, speech, _) = makeFlow()
        speech.isRecording = true
        speech.recognizedText = "Old sentence."
        model.clearText()
        speech.recognizedText = "New sentence."
        try await settle()
        XCTAssertEqual(model.displayEntries.map(\.originalText), ["New sentence."])
        model.stopTranslation()
    }

    func testCorrectionDuringRequestCannotDisplayStaleTranslation() async throws {
        let (model, speech, _) = makeFlow()
        speech.isRecording = true
        speech.recognizedText = "We can go."
        try await settle(0.04)
        let id = model.displayEntries.first?.id
        speech.recognizedText = "We may go."
        try await settle()
        XCTAssertEqual(model.displayEntries.count, 1)
        XCTAssertEqual(model.displayEntries.first?.id, id)
        XCTAssertEqual(model.displayEntries.first?.originalText, "We may go.")
        XCTAssertEqual(model.displayEntries.first?.translatedText, "Mock translation of: We may go.")
        model.stopTranslation()
    }

    func testCorrectionAfterCompletionReplacesLine() async throws {
        let (model, speech, _) = makeFlow()
        speech.isRecording = true
        speech.recognizedText = "We can go."
        try await settle()
        let id = model.displayEntries.first?.id
        speech.recognizedText = "We may go."
        try await settle()
        XCTAssertEqual(model.displayEntries.count, 1)
        XCTAssertEqual(model.displayEntries.first?.id, id)
        XCTAssertEqual(model.displayEntries.first?.translatedText, "Mock translation of: We may go.")
        model.stopTranslation()
    }

    func testShortAnswerAndStopFlushForBothAudioSources() async throws {
        for source in AudioInputSource.allCases {
            let (model, speech, service) = makeFlow()
            model.appSettings.audioInputSource = source
            try await settle(0.35)
            speech.isRecording = true
            speech.recognizedText = "No"
            try await settle(1.2)
            XCTAssertEqual(service.lastTranslatedText, "No")
            speech.recognizedText = "No 2027"
            model.stopTranslation()
            try await settle()
            XCTAssertEqual(model.displayEntries.map(\.originalText), ["No", "2027"])
            XCTAssertTrue(model.displayEntries.allSatisfy { !$0.translatedText.isEmpty })
        }
    }

    func testClearWhileRequestIsRunningDoesNotRestoreOldText() async throws {
        let (model, speech, _) = makeFlow()
        speech.isRecording = true
        speech.recognizedText = "Old words."
        try await settle(0.04)
        model.clearText()
        try await settle()
        XCTAssertTrue(model.displayEntries.isEmpty)
        speech.recognizedText = "New words."
        try await settle()
        XCTAssertEqual(model.displayEntries.map(\.originalText), ["New words."])
        XCTAssertEqual(model.displayEntries.first?.translatedText, "Mock translation of: New words.")
        model.stopTranslation()
    }

    func testQueuedSentencesKeepTheirOwnTranslations() async throws {
        let (model, speech, _) = makeFlow()
        speech.isRecording = true
        speech.recognizedText = "No. OK. 2027!"
        try await settle(0.7)
        XCTAssertEqual(model.displayEntries.map(\.originalText), ["No.", "OK.", "2027!"])
        for entry in model.displayEntries {
            XCTAssertEqual(entry.translatedText, "Mock translation of: \(entry.originalText)")
        }
        model.stopTranslation()
    }
}

final class TranslationGlossaryTests: XCTestCase {
    func testGlossaryValidationAndCanonicalReverseNames() throws {
        let terms = try Glossary.parse("Jensen Huang = 黄仁勋\nRAG = 检索增强生成\nrag = 检索增强生成")
        XCTAssertEqual(terms.count, 2)
        XCTAssertEqual(try Glossary.parse(Glossary.text(terms)), terms)
        XCTAssertThrowsError(try Glossary.parse("RAG = 检索增强生成\nrag = 其他译名"))
        XCTAssertThrowsError(try Glossary.parse("missing separator"))
        XCTAssertThrowsError(try Glossary.parse("RAG = "))
        XCTAssertEqual(terms[0].pair(for: .chineseToEnglish).target, "Jensen Huang")
        let aliases = terms + [GlossaryTerm(english: "Jensen", chinese: "黄仁勋")]
        let relevant = TranslationContext(terms: aliases).relevantTerms(to: "黄仁勋介绍了检索增强生成", direction: .chineseToEnglish)
        XCTAssertEqual(relevant.filter { $0.chinese == "黄仁勋" }.map(\.english), ["Jensen Huang"])
    }

    func testRelevantTermsMatchWholeWordsAndRecentContext() {
        let ai = GlossaryTerm(english: "AI", chinese: "人工智能")
        XCTAssertTrue(GlossaryTerm(english: "retrieval-augmented generation", chinese: "检索增强生成")
            .occurs(in: "retrieval augmented generation", direction: .englishToChinese))
        XCTAssertFalse(ai.occurs(in: "said chair", direction: .englishToChinese))
        XCTAssertTrue(ai.occurs(in: "AI-powered tools", direction: .englishToChinese))
        let context = TranslationContext(recent: [.init(original: "Jensen Huang presented RAG.", translation: "黄仁勋介绍检索增强生成。")],
            terms: [GlossaryTerm(english: "Jensen Huang", chinese: "黄仁勋"), GlossaryTerm(english: "RAG", chinese: "检索增强生成")])
        XCTAssertEqual(context.relevantTerms(to: "He will explain it.", direction: .englishToChinese).count, 2)
    }
}

private final class TranslationHTTPStub: URLProtocol {
    struct Reply {
        var status = 200
        var headers: [String: String] = ["Content-Type": "text/event-stream"]
        var data = Data()
        var error: Error?
        var delay: TimeInterval = 0
    }
    private var delivery: DispatchWorkItem?
    static var handler: ((URLRequest) -> Reply)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let reply = Self.handler?(request) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let error = reply.error { self.client?.urlProtocol(self, didFailWithError: error); return }
            let response = HTTPURLResponse(url: self.request.url!, statusCode: reply.status,
                                          httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: reply.data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        delivery = work
        if reply.delay > 0 { DispatchQueue.global().asyncAfter(deadline:.now()+reply.delay,execute:work) }
        else { work.perform() }
    }
    override func stopLoading() { delivery?.cancel(); delivery = nil }

    static func translated(_ value: String, complete: Bool = true) -> Data {
        let json = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": value]]]])
        return Data(("data: " + String(data: json, encoding: .utf8)! + "\n\n" + (complete ? "data: [DONE]\n\n" : "")).utf8)
    }
}

@MainActor
final class TranslationRecoveryTests: XCTestCase {
    private func setupFlow(delays: [TimeInterval] = [0.02, 0.02, 0.02]) -> (MainViewModel, MockSpeechRecognizer, TranslationService, AppSettings) {
        let settings = MockAppSettings()
        settings.customAPIKey = "test-key-for-local-stub"
        settings.customAPIBaseURL = "https://translation.test/v1/chat/completions"
        settings.apiProvider = .customAPI
        settings.keepHistory = false
        settings.audioInputSource = .microphone
        settings.translationGlossary = []
        settings.useTranslationContext = true
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranslationHTTPStub.self]
        let service = TranslationService(appSettings: settings, session: URLSession(configuration: config))
        let speech = MockSpeechRecognizer()
        let model = MainViewModel(speechRecognizer: speech, translationService: service,
                                 historyManager: MockHistoryManager(), appSettings: settings, retryDelays: delays)
        return (model, speech, service, settings)
    }
    private func pause(_ seconds: Double = 0.3) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testAudioSourceIsAppliedBeforeRecordingCanStart() {
        let (model, speech, _, settings) = setupFlow()
        withExtendedLifetime(model) {
            settings.audioInputSource = .systemAudio
            XCTAssertEqual(speech.lastAudioSourceSet, .systemAudio)
            settings.audioInputSource = .microphone
            XCTAssertEqual(speech.lastAudioSourceSet, .microphone)
        }
    }

    func testTransientFailureRetriesOriginalRowWhileNextSentenceContinues() async throws {
        let (model, speech, _, _) = setupFlow()
        var requests = 0
        TranslationHTTPStub.handler = { _ in
            requests += 1
            if requests == 1 { return .init(status: 503) }
            return .init(data: TranslationHTTPStub.translated("译文"))
        }
        speech.isRecording = true
        speech.recognizedText = "First sentence. Second sentence."
        let ids = model.displayEntries.map(\.id)
        try await pause(1)
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(model.displayEntries.map(\.id), ids)
        XCTAssertEqual(model.displayEntries.map(\.translatedText), ["译文", "译文"])
        XCTAssertEqual(model.untranslatedCount, 0)
        XCTAssertFalse(model.errorHandler.showErrorAlert)
        model.stopTranslation()
    }

    func testRetryLimitAndManualRecovery() async throws {
        let (model, speech, _, _) = setupFlow(delays: [0.01, 0.01])
        var calls = 0
        var recovered = false
        TranslationHTTPStub.handler = { _ in
            calls += 1
            return recovered ? .init(data: TranslationHTTPStub.translated("恢复后的译文")) : .init(status: 500)
        }
        speech.isRecording = true
        speech.finalizedText = "Keep this sentence."
        try await pause(1)
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(model.untranslatedCount, 1)
        XCTAssertTrue(model.displayEntries[0].statusMessage.contains("点击补译"))
        let id = model.displayEntries[0].id
        recovered = true
        model.retryFailedTranslations()
        try await pause()
        XCTAssertEqual(model.displayEntries[0].id, id)
        XCTAssertEqual(model.displayEntries[0].translatedText, "恢复后的译文")
        XCTAssertEqual(model.untranslatedCount, 0)
        model.stopTranslation()
    }

    func testUnauthorizedDoesNotRetryAndClearCancelsPendingBackfill() async throws {
        let (model, speech, _, _) = setupFlow()
        var calls = 0
        TranslationHTTPStub.handler = { _ in calls += 1; return .init(status: 401) }
        speech.isRecording = true
        speech.finalizedText = "Authorization fails."
        try await pause(0.7)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.displayEntries[0].statusMessage.contains("检查翻译设置"))
        TranslationHTTPStub.handler = { _ in calls += 1; return .init(status: 503) }
        speech.finalizedText = "Temporary failure."
        try await pause(0.05)
        model.clearText()
        let count = calls
        try await pause(0.7)
        XCTAssertEqual(calls, count)
        XCTAssertTrue(model.displayEntries.isEmpty)
        model.stopTranslation()
    }

    func testTruncatedStreamCannotBecomeSuccessfulPartialTranslation() async throws {
        let (_, _, service, _) = setupFlow()
        TranslationHTTPStub.handler = { _ in .init(data: TranslationHTTPStub.translated("不完整", complete: false)) }
        await service.translateText("Hello", direction: .englishToChinese)
        XCTAssertNotNil(service.error)
        XCTAssertTrue(service.shouldRetryFailure)
        XCTAssertTrue(service.translatedText.isEmpty)
        TranslationHTTPStub.handler = { _ in .init(data: TranslationHTTPStub.translated("完整译文")) }
        await service.translateText("Hello", direction: .englishToChinese)
        XCTAssertNil(service.error)
        XCTAssertEqual(service.translatedText, "完整译文")
        XCTAssertEqual(service.getFullTranslatedText(), "完整译文")
    }

    func testContextContainsOnlyEarlierSuccessfulSameDirectionLines() async throws {
        let (model, speech, _, settings) = setupFlow()
        settings.translationGlossary = [GlossaryTerm(english: "RAG", chinese: "检索增强生成")]
        TranslationHTTPStub.handler = { _ in .init(data: TranslationHTTPStub.translated("已完成的译文")) }
        speech.isRecording = true
        speech.finalizedText = "RAG is the first topic."
        try await pause()
        speech.recognizedText = "RAG is the first topic. We will discuss it next."
        speech.finalizedText = speech.recognizedText
        try await pause()
        let id = model.displayEntries.last!.id
        let context = model.contextForSession(id)
        XCTAssertEqual(context.recent.map(\.original), ["RAG is the first topic."])
        XCTAssertEqual(context.terms, settings.translationGlossary)
        settings.useTranslationContext = false
        XCTAssertTrue(model.contextForSession(id).recent.isEmpty)
        XCTAssertEqual(model.contextForSession(id).terms, settings.translationGlossary)
        model.clearText()
        XCTAssertTrue(model.displayEntries.isEmpty)
        model.stopTranslation()
    }

    func testPromptKeepsReferenceOutOfCurrentTextAndReversesGlossary() throws {
        let (_, _, service, _) = setupFlow()
        service.context = TranslationContext(recent: [.init(original: "Earlier line", translation: "前一句")],
            terms: [GlossaryTerm(english: "RAG", chinese: "检索增强生成")])
        let request = try service.createOpenAIRequest(text: "检索增强生成很好。", direction: .chineseToEnglish, apiKey: "test")
        let body = try JSONDecoder().decode(TranslationService.OpenAIRequest.self, from: request.httpBody!)
        XCTAssertTrue(body.messages[0].content.contains("Earlier line"))
        XCTAssertTrue(body.messages[0].content.contains("\"检索增强生成\" => \"RAG\""))
        XCTAssertFalse(body.messages[1].content.contains("Earlier line"))
    }

    func testRetryAfterAndEmptyResponseAreClassified() async throws {
        let (_, _, service, _) = setupFlow()
        TranslationHTTPStub.handler = { _ in .init(status: 429, headers: ["Retry-After": "7"]) }
        await service.translateText("Hello", direction: .englishToChinese)
        XCTAssertTrue(service.shouldRetryFailure)
        XCTAssertEqual(service.retryAfter, 7)
        TranslationHTTPStub.handler = { _ in .init(data: Data("data: [DONE]\n\n".utf8)) }
        await service.translateText("Hello", direction: .englishToChinese)
        XCTAssertNotNil(service.error)
        XCTAssertTrue(service.translatedText.isEmpty)
        XCTAssertEqual(TranslationService.retryDelay("-1"), 0)
        XCTAssertNil(TranslationService.retryDelay("invalid"))
    }
}

@MainActor
final class TranslationSettingsAcceptanceTests: XCTestCase {
    func testGlossarySavesReloadsAndRejectsConflictsWithoutOverwriting() throws {
        let settings = AppSettings()
        let original = settings.translationGlossary
        defer { settings.translationGlossary = original }
        let viewModel = SettingsViewModel(appSettings: settings, translationService: TranslationService(appSettings: settings))
        viewModel.glossaryText = "Project Aurora = 晨光计划\nRAG = 检索增强生成"
        XCTAssertTrue(viewModel.saveGlossary())
        XCTAssertEqual(AppSettings().translationGlossary, settings.translationGlossary)
        let saved = settings.translationGlossary
        viewModel.glossaryText = "RAG = 检索增强生成\nRAG = 不同译法"
        XCTAssertFalse(viewModel.saveGlossary())
        XCTAssertEqual(settings.translationGlossary, saved)
        XCTAssertTrue(viewModel.glossaryHasError)
    }
}

@MainActor
final class ConversationPersistenceTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("voice-conversation-tests-\(UUID())")
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    private func makeModel(history: HistoryManager, service: TranslationService? = nil) -> (MainViewModel, MockSpeechRecognizer) {
        let settings = MockAppSettings()
        settings.keepHistory = true
        settings.audioInputSource = .microphone
        let speech = MockSpeechRecognizer()
        let model = MainViewModel(speechRecognizer: speech, translationService: service ?? MockTranslationService(), historyManager: history, appSettings: settings)
        return (model, speech)
    }
    private func conversation(count: Int = 1, completed: Bool = false, draft: String = "") -> SavedConversation {
        let rows = (0..<count).map { i -> TranslationSession in
            var row = TranslationSession(originalText: "Source \(i)", direction: i % 2 == 0 ? .englishToChinese : .chineseToEnglish)
            row.isCompleted = completed
            row.translatedText = completed ? "译文 \(i)" : "partial text must not survive"
            return row
        }
        return SavedConversation(id: UUID(), startedAt: Date(), updatedAt: Date(), lines: rows, draft: draft, draftDirection: .englishToChinese)
    }
    func testWholeConversationSurvivesFreshManagerBeyondHundredLines() {
        let history = HistoryManager(conversationDirectory: directory)
        let saved = conversation(count: 230, completed: true)
        history.saveConversation(saved)
        let reopened = HistoryManager(conversationDirectory: directory)
        XCTAssertEqual(reopened.activeConversation()?.lines.count, 230)
        XCTAssertEqual(reopened.savedConversations.count, 1)
        XCTAssertEqual(reopened.savedConversations.first?.lines.last?.translatedText, "译文 229")
    }
    func testDraftSavedBeforeSegmentationAndResumedWithoutMicrophone() async throws {
        let history = HistoryManager(conversationDirectory: directory)
        var (model, speech) = makeModel(history: history)
        speech.isRecording = true
        speech.recognizedText = "Still speaking without punctuation"
        XCTAssertEqual(HistoryManager(conversationDirectory: directory).activeConversation()?.draft, "Still speaking without punctuation")
        let (reopened, nextSpeech) = makeModel(history: HistoryManager(conversationDirectory: directory))
        XCTAssertFalse(nextSpeech.startRecordingCalled)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(reopened.displayEntries.count, 1)
        XCTAssertEqual(reopened.displayEntries.first?.originalText, "Still speaking without punctuation")
        XCTAssertFalse(reopened.displayEntries.first?.translatedText.isEmpty ?? true)
        withExtendedLifetime((model,speech)) {}
    }
    func testResumeUnfinishedLineKeepsIDAndReplacesPartialTranslation() async throws {
        let history = HistoryManager(conversationDirectory: directory)
        let saved = conversation()
        history.saveConversation(saved)
        let (model, speech) = makeModel(history: history)
        XCTAssertEqual(model.displayEntries.first?.id, saved.lines.first?.id)
        XCTAssertEqual(model.displayEntries.first?.translatedText, "")
        XCTAssertFalse(speech.startRecordingCalled)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(model.displayEntries.count, 1)
        XCTAssertEqual(model.displayEntries.first?.translatedText, "Mock translation of: Source 0")
        XCTAssertEqual(history.activeConversation()?.lines.first?.isCompleted, true)
    }
    func testCompletedLinesNotRetranslatedOnReopen() async throws {
        let history = HistoryManager(conversationDirectory: directory)
        history.saveConversation(conversation(count: 4, completed: true))
        let service = MockTranslationService()
        let (model, _) = makeModel(history: history, service: service)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(service.translateTextCalled)
        XCTAssertEqual(model.displayEntries.count, 4)
    }
    func testClearStartsNewConversationButKeepsPreviousWholeRecord() async throws {
        let history = HistoryManager(conversationDirectory: directory)
        let old = conversation(count: 3, completed: true)
        history.saveConversation(old)
        let (model, speech) = makeModel(history: history)
        model.clearText()
        XCTAssertNil(history.activeConversation())
        XCTAssertEqual(history.savedConversations.count, 1)
        speech.isRecording = true
        speech.recognizedText = "A new conversation."
        let current = history.activeConversation()
        XCTAssertNotEqual(current?.id, old.id)
        XCTAssertEqual(current?.lines.count, 1)
        XCTAssertEqual(history.savedConversations.count, 2)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(history.savedConversations.first(where: { $0.id == old.id })?.lines.count, 3)
    }
    func testRepeatedCheckpointsUpdateOneWholeRecord() {
        let history = HistoryManager(conversationDirectory: directory)
        var saved = conversation()
        for _ in 0..<5 { history.saveConversation(saved) }
        saved.lines[0].translatedText = "完成"; saved.lines[0].isCompleted = true
        history.saveConversation(saved)
        XCTAssertEqual(HistoryManager(conversationDirectory: directory).savedConversations.count, 1)
        XCTAssertEqual(history.activeConversation()?.lines.first?.translatedText, "完成")
    }
    func testCorruptActiveFileRemainsAvailableAndShowsError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("active.json")
        try Data("broken".utf8).write(to: url)
        let history = HistoryManager(conversationDirectory: directory)
        XCTAssertNil(history.activeConversation())
        XCTAssertFalse(history.saveError.isEmpty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken")
    }
    func testWriteFailureIsVisibleInsteadOfClaimingSaved() throws {
        try Data("not a directory".utf8).write(to: directory)
        let history = HistoryManager(conversationDirectory: directory)
        history.saveConversation(conversation())
        XCTAssertFalse(history.saveError.isEmpty)
    }
    func testDisablingHistoryDoesNotSaveNewConversation() {
        let history = HistoryManager(conversationDirectory: directory)
        let (model, speech) = makeModel(history: history)
        model.appSettings.keepHistory = false
        speech.isRecording = true; speech.recognizedText = "Do not save this."
        model.checkpointConversation()
        XCTAssertNil(history.activeConversation())
        XCTAssertTrue(history.savedConversations.isEmpty)
    }
    func testSaveFailureDoesNotDiscardCurrentConversationWhenCleared() throws {
        try Data("not a directory".utf8).write(to: directory)
        let history = HistoryManager(conversationDirectory: directory)
        let (model, speech) = makeModel(history: history)
        speech.isRecording = true
        speech.recognizedText = "Keep this source when the disk cannot save it."
        model.clearText()
        XCTAssertFalse(model.displayEntries.isEmpty)
        XCTAssertTrue(model.displayEntries.contains { $0.originalText.contains("Keep this source") })
        XCTAssertFalse(history.saveError.isEmpty)
    }

    func testOpeningConversationRestoresItsLanguageDirection() {
        let history = HistoryManager(conversationDirectory: directory)
        let (model, _) = makeModel(history: history)
        model.appSettings.selectedLanguageDirection = .englishToChinese
        var saved = conversation(completed: true)
        saved.draftDirection = .chineseToEnglish
        model.restoreConversation(saved)
        XCTAssertEqual(model.appSettings.selectedLanguageDirection, .chineseToEnglish)
        XCTAssertEqual(model.displayEntries.first?.originalText, saved.lines.first?.originalText)
    }

    func testHistoryClearAlsoClearsWholeConversations() {
        let history = HistoryManager(conversationDirectory: directory)
        history.saveConversation(conversation())
        history.clearAllHistory()
        XCTAssertNil(history.activeConversation())
        XCTAssertTrue(HistoryManager(conversationDirectory: directory).savedConversations.isEmpty)
    }
}

@MainActor
final class RecordingRecoveryTests: XCTestCase {
    func testSilentBuffersAreDistinguishedFromMissingBuffers() {
        let heartbeat = AudioHeartbeat()
        let now = Date()
        heartbeat.mark(hasSound: false, at: now)
        XCTAssertEqual(heartbeat.snapshot().bufferAt, now)
        XCTAssertNil(heartbeat.snapshot().soundAt)
        heartbeat.mark(hasSound: true, at: now.addingTimeInterval(1))
        XCTAssertEqual(heartbeat.snapshot().soundAt, now.addingTimeInterval(1))
        heartbeat.reset()
        XCTAssertNil(heartbeat.snapshot().bufferAt)
    }
    func testPermissionFailureDoesNotClaimRecording() {
        let speech = SpeechRecognizer()
        speech.authorizationStatus = .denied
        speech.startRecording()
        XCTAssertFalse(speech.isRecording)
        XCTAssertFalse(speech.isListening)
        XCTAssertEqual(speech.recordingPhase, .failed)
    }
    func testStopCancelsPendingRecoveryAndWakeDoesNotStartAgain() async throws {
        let speech = SpeechRecognizer()
        speech.isRecording = true
        speech.scheduleCaptureRecovery(reason: "测试恢复")
        XCTAssertEqual(speech.recordingPhase, .recovering)
        XCTAssertFalse(speech.isListening)
        speech.stopRecording()
        speech.resumeAfterWake()
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertFalse(speech.isRecording)
        XCTAssertEqual(speech.recordingPhase, .idle)
    }
    func testSleepAndWakePreserveIntentButDoNotClaimReceivingSound() {
        let speech = SpeechRecognizer()
        speech.isRecording = true
        speech.prepareForSleep()
        XCTAssertTrue(speech.isRecording)
        XCTAssertEqual(speech.recordingPhase, .sleeping)
        XCTAssertFalse(speech.isListening)
        speech.resumeAfterWake()
        XCTAssertEqual(speech.recordingPhase, .recovering)
        speech.stopRecording()
    }
    func testSleepWhenStoppedNeverStartsRecording() {
        let speech = SpeechRecognizer()
        speech.prepareForSleep()
        speech.resumeAfterWake()
        XCTAssertFalse(speech.isRecording)
        XCTAssertEqual(speech.recordingPhase, .idle)
    }
}

final class NaturalSentenceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1800)
    func testArticlePauseWaitsForCompleteThought() {
        var t = LiveTranscript()
        t.observe("Before the", at: start)
        XCTAssertTrue(t.drain(at: start.addingTimeInterval(1)).isEmpty)
        t.observe("Before the presentation Alice Chen will confirm the budget", at: start.addingTimeInterval(1.1))
        let result = t.drain(at: start.addingTimeInterval(2.6))
        XCTAssertEqual(result.map(\.text), ["Before the presentation Alice Chen will confirm the budget"])
    }
    func testVerbTailDoesNotBecomeStrayTranslation() {
        var t = LiveTranscript()
        t.observe("After the headphones disconnected the built in microphone keeps", at: start)
        XCTAssertTrue(t.drain(at: start.addingTimeInterval(1)).isEmpty)
        t.observe("After the headphones disconnected the built in microphone keeps recording this new sentence.", at: start.addingTimeInterval(1.1))
        XCTAssertEqual(t.drain(at: start.addingTimeInterval(1.1)).map(\.text), ["After the headphones disconnected the built in microphone keeps recording this new sentence."])
    }
    func testRecentProvisionalFragmentGrowsOnSameRow() {
        var t = LiveTranscript()
        t.observe("Before the", at: start)
        let first = t.drain(at: start.addingTimeInterval(2.9))
        XCTAssertEqual(first.count, 1)
        t.observe("Before the presentation starts Alice Chen will review the budget.", at: start.addingTimeInterval(3.1))
        let next = t.drain(at: start.addingTimeInterval(3.1))
        XCTAssertEqual(next.map(\.id), first.map(\.id))
        XCTAssertEqual(t.lines.count, 1)
        XCTAssertTrue(next[0].text.hasSuffix("budget."))
    }
    func testNamePauseCanGrowIntoTheFullSentenceOnSameRow() {
        var t = LiveTranscript()
        t.observe("Alice Chen", at:start)
        let first = t.drain(at:start.addingTimeInterval(0.9))
        t.observe("Alice Chen approved 2500 dollars.",at:start.addingTimeInterval(1.2))
        let next = t.drain(at:start.addingTimeInterval(1.2))
        XCTAssertEqual(next.first?.id,first.first?.id)
        XCTAssertEqual(next.first?.text,"Alice Chen approved 2500 dollars.")
        XCTAssertEqual(t.lines.count,1)
    }

    func testNamesInitialsAndThousandsAreNotSentenceBoundaries() {
        var t = LiveTranscript()
        let source = "Dr. J. Chen approved 1,250.50 dollars. The meeting is on May 21."
        t.observe(source, at: start)
        XCTAssertEqual(t.drain(at: start).map(\.text), ["Dr. J. Chen approved 1,250.50 dollars.", "The meeting is on May 21."])
    }
    func testShortAnswersRemainPromptAndSeparate() {
        for source in ["Yes", "No", "OK", "2500", "好", "可以"] {
            var t = LiveTranscript(); t.observe(source, at: start)
            XCTAssertEqual(t.drain(at: start.addingTimeInterval(0.9)).map(\.text), [source])
            t.observe(source + " " + source, at: start.addingTimeInterval(1))
            XCTAssertEqual(t.drain(at: start.addingTimeInterval(2)).map(\.text), [source])
            XCTAssertEqual(t.lines.count, 2)
        }
    }
    func testExplicitSpokenCorrectionUpdatesRecentNumberAnswer() {
        var t = LiveTranscript(); t.observe("150", at: start)
        let first = t.drain(at: start.addingTimeInterval(0.9))
        t.observe("150 sorry I mean 250 dollars.", at: start.addingTimeInterval(1.3))
        let correction = t.drain(at: start.addingTimeInterval(1.3))
        XCTAssertEqual(correction.first?.id, first.first?.id)
        XCTAssertEqual(correction.first?.text, "150 sorry I mean 250 dollars.")
        XCTAssertEqual(t.lines.count, 1)
    }
    func testAndInsideAnAmountDoesNotBecomeAClauseBoundary() {
        var t = LiveTranscript()
        let source = "The budget is one thousand two hundred fifty dollars and fifty cents"
        t.observe(source,at:start)
        t.observe(source + " today",at:start.addingTimeInterval(3.9))
        XCTAssertTrue(t.drain(at:start.addingTimeInterval(4.1)).isEmpty)
        XCTAssertEqual(t.drain(at:start.addingTimeInterval(5.4)).map(\.text),[source + " today"])
    }

    func testExplicitCorrectionAfterLongerRecognitionPauseRevisesCompleteSentence() {
        var t = LiveTranscript(); t.observe("The final amount is 1500 dollars.",at:start)
        let first = t.drain(at:start)
        t.observe("The final amount is 1500 dollars. No I mean 2500 dollars.",at:start.addingTimeInterval(6))
        let updated = t.drain(at:start.addingTimeInterval(7.5))
        XCTAssertEqual(updated.first?.id,first.first?.id)
        XCTAssertEqual(t.lines.count,1)
        XCTAssertTrue(updated.first?.text.contains("No I mean 2500 dollars.") == true)
    }

    func testNaturalClauseBoundaryAndHardDeadlineBothMakeProgress() {
        var t = LiveTranscript()
        let natural = "Alice Chen will present the forecast, and the finance team will confirm the final budget tomorrow"
        t.observe(natural, at: start)
        t.observe(natural + " morning", at: start.addingTimeInterval(3.9))
        XCTAssertEqual(t.drain(at: start.addingTimeInterval(4.1)).first?.text, "Alice Chen will present the forecast,")
        var continuous = LiveTranscript()
        let noClause = "Alice Chen will explain every detail of the proposed annual schedule for all project teams tomorrow morning"
        continuous.observe(noClause, at: start)
        continuous.observe(noClause + " in the office", at: start.addingTimeInterval(7.9))
        XCTAssertFalse(continuous.drain(at: start.addingTimeInterval(8.1)).isEmpty)
        _ = continuous.drain(at: start.addingTimeInterval(8.2), force: true)
        XCTAssertEqual(continuous.lines.map(\.text).joined().filter { !$0.isWhitespace }, (noClause + " in the office").filter { !$0.isWhitespace })
    }
    func testProtectedCorrectedTwoSentenceRowKeepsFollowingSpeechSeparate() {
        var t = LiveTranscript(); t.observe("The amount is 1500 dollars.",at:start)
        let id = t.drain(at:start)[0].id
        t.observe("The amount is 1500 dollars. Sorry I mean 2500 dollars.",at:start.addingTimeInterval(5))
        _ = t.drain(at:start.addingTimeInterval(6.5)); t.protect(id)
        t.observe("The amount is 3500 dollars. Sorry I mean 2500 dollars. Bob arrives tomorrow.",at:start.addingTimeInterval(7))
        _ = t.drain(at:start.addingTimeInterval(7),force:true)
        XCTAssertEqual(t.lines.first?.id,id)
        XCTAssertTrue(t.lines.dropFirst().map(\.text).joined().contains("Bob arrives tomorrow."))
    }

    func testProtectedCutDoesNotSwallowFollowingSpeechWhenRecognizerRevisesPrefix() {
        var t = LiveTranscript()
        t.observe("Alex Chan approved 1500 dollars.", at: start)
        let first = t.drain(at: start)[0]; t.protect(first.id)
        t.observe("Alice Chen approved 2500 dollars. Bob will present tomorrow.", at: start.addingTimeInterval(1))
        _ = t.drain(at: start.addingTimeInterval(1), force: true)
        XCTAssertEqual(t.lines.first?.id, first.id)
        XCTAssertTrue(t.lines.dropFirst().map(\.text).joined().contains("Bob will present tomorrow."))
    }
}

@MainActor
final class ManualOriginalEditingTests: XCTestCase {
    private func flow(directory: URL? = nil, service: TranslationService? = nil) -> (MainViewModel, MockSpeechRecognizer, HistoryManager) {
        let settings = MockAppSettings()
        settings.keepHistory = directory != nil
        settings.selectedLanguageDirection = .englishToChinese
        settings.audioInputSource = .microphone
        settings.customAPIKey = "test-editing-local-key"
        settings.customAPIBaseURL = "https://editing.test/v1/chat/completions"
        settings.apiProvider = .customAPI
        let speech = MockSpeechRecognizer()
        let history = HistoryManager(conversationDirectory: directory)
        let model = MainViewModel(speechRecognizer: speech, translationService: service ?? MockTranslationService(), historyManager: history, appSettings: settings)
        return (model,speech,history)
    }
    func testHumanNameAndNumberEditRetranslatesAndResistsLaterRecognition() async throws {
        let (model,speech,_) = flow()
        speech.isRecording = true
        speech.recognizedText = "Alex Chan approved 1500 dollars."
        try await Task.sleep(nanoseconds: 180_000_000)
        let id = try XCTUnwrap(model.displayEntries.first?.id)
        XCTAssertTrue(model.updateOriginalText(entryID: id, text: "Alice Chen approved 2500 dollars."))
        speech.recognizedText = "Alex Chan approved 3500 dollars. Bob will present tomorrow."
        try await Task.sleep(nanoseconds: 350_000_000)
        let fixed = try XCTUnwrap(model.displayEntries.first(where: { $0.id == id }))
        XCTAssertEqual(fixed.originalText, "Alice Chen approved 2500 dollars.")
        XCTAssertEqual(fixed.translatedText, "Mock translation of: Alice Chen approved 2500 dollars.")
        XCTAssertTrue(fixed.isManuallyEdited)
        XCTAssertTrue(model.displayEntries.contains { $0.originalText.contains("Bob will present tomorrow.") })
        XCTAssertEqual(model.displayEntries.filter { $0.id == id }.count, 1)
    }
    func testEditingDuringRequestDiscardsOldReply() async throws {
        let settings = MockAppSettings(); settings.customAPIKey = "test-editing-local-key"
        settings.customAPIBaseURL = "https://editing.test/v1/chat/completions"; settings.apiProvider = .customAPI
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [TranslationHTTPStub.self]
        let service = TranslationService(appSettings: settings, session: URLSession(configuration: configuration))
        var requests = 0
        TranslationHTTPStub.handler = { request in
            requests += 1
            return .init(data: TranslationHTTPStub.translated(requests == 1 ? "过期译文" : "爱丽丝确认2500美元。"), delay: requests == 1 ? 0.4 : 0.01)
        }
        let (model,speech,_) = flow(service: service)
        speech.isRecording = true; speech.recognizedText = "Alex confirmed 1500 dollars."
        try await Task.sleep(nanoseconds: 60_000_000)
        let id = try XCTUnwrap(model.displayEntries.first?.id)
        XCTAssertTrue(model.updateOriginalText(entryID: id, text: "Alice confirmed 2500 dollars."))
        try await Task.sleep(nanoseconds: 550_000_000)
        XCTAssertEqual(model.displayEntries.count, 1)
        XCTAssertEqual(model.displayEntries.first?.translatedText, "爱丽丝确认2500美元。")
        XCTAssertEqual(requests, 2)
    }
    func testInvalidEditLeavesCompletedOriginalUntouched() async throws {
        let (model,speech,_) = flow(); speech.isRecording = true; speech.recognizedText = "The meeting starts tomorrow."
        try await Task.sleep(nanoseconds: 150_000_000)
        let entry = try XCTUnwrap(model.displayEntries.first)
        XCTAssertFalse(model.updateOriginalText(entryID: entry.id, text: " \n..."))
        XCTAssertFalse(model.updateOriginalText(entryID: entry.id, text: String(repeating: "x",count:4001)))
        XCTAssertEqual(model.displayEntries.first, entry)
    }
    func testManualOverrideSurvivesReopenWithoutRepeatingSuccessfulTranslation() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-round4-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (model,speech,history) = flow(directory: dir)
        speech.isRecording = true; speech.recognizedText = "Alex approved 1500 dollars."
        try await Task.sleep(nanoseconds: 160_000_000)
        let id = try XCTUnwrap(model.displayEntries.first?.id)
        XCTAssertTrue(model.updateOriginalText(entryID: id, text: "Alice approved 2500 dollars."))
        try await Task.sleep(nanoseconds: 170_000_000)
        let saved = try XCTUnwrap(HistoryManager(conversationDirectory: dir).activeConversation())
        XCTAssertEqual(saved.lines.first?.manualOriginal,"Alice approved 2500 dollars.")
        XCTAssertFalse(history.translationHistory.contains { $0.originalText == "Alex approved 1500 dollars." })
        let (reopened, nextSpeech,_) = flow(directory: dir)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(reopened.displayEntries.first?.id,id)
        XCTAssertEqual(reopened.displayEntries.first?.originalText,"Alice approved 2500 dollars.")
        XCTAssertTrue(reopened.displayEntries.first?.isManuallyEdited == true)
        XCTAssertFalse(nextSpeech.startRecordingCalled)
        nextSpeech.isRecording = true; nextSpeech.recognizedText = "Another sentence arrives."
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertEqual(reopened.displayEntries.first?.originalText,"Alice approved 2500 dollars.")
        XCTAssertEqual(reopened.displayEntries.count,2)
    }
    func testRepeatedManualEditsKeepTheLatestValueAndOnlyOneRow() async throws {
        let (model,speech,_) = flow(); speech.isRecording = true
        speech.recognizedText = "Alice approved 1500 dollars."
        try await Task.sleep(nanoseconds:160_000_000)
        let id = try XCTUnwrap(model.displayEntries.first?.id)
        XCTAssertTrue(model.updateOriginalText(entryID:id,text:"Alice approved 2500 dollars."))
        XCTAssertTrue(model.updateOriginalText(entryID:id,text:"Alice approved 3500 dollars."))
        speech.recognizedText = "Alice approved 4500 dollars."
        try await Task.sleep(nanoseconds:300_000_000)
        XCTAssertEqual(model.displayEntries.count,1)
        XCTAssertEqual(model.displayEntries.first?.originalText,"Alice approved 3500 dollars.")
        XCTAssertEqual(model.displayEntries.first?.translatedText,"Mock translation of: Alice approved 3500 dollars.")
    }

    func testHumanEditIsPreservedWhenTranslationFails() async throws {
        let settings = MockAppSettings(); settings.customAPIKey = "test-editing-local-key"
        settings.customAPIBaseURL = "https://editing.test/v1/chat/completions"; settings.apiProvider = .customAPI
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TranslationHTTPStub.self]
        let service = TranslationService(appSettings:settings,session:URLSession(configuration:config))
        TranslationHTTPStub.handler = { _ in .init(status:503) }
        let (model,speech,_) = flow(service:service)
        speech.isRecording = true; speech.recognizedText = "Alice approved 1500 dollars."
        try await Task.sleep(nanoseconds:70_000_000)
        let id = try XCTUnwrap(model.displayEntries.first?.id)
        XCTAssertTrue(model.updateOriginalText(entryID:id,text:"Alice approved 2500 dollars."))
        speech.recognizedText = "Alice approved 4500 dollars."
        try await Task.sleep(nanoseconds:120_000_000)
        XCTAssertEqual(model.displayEntries.first?.originalText,"Alice approved 2500 dollars.")
        XCTAssertTrue(model.displayEntries.first?.isManuallyEdited == true)
        XCTAssertTrue(model.displayEntries.first?.translatedText.isEmpty == true)
        model.clearText()
    }

    func testEditingOldHistoryReplacesOnlyItsOwnLegacyRecord() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-legacy-edit-\(UUID())")
        defer { try? FileManager.default.removeItem(at:dir) }
        let history = HistoryManager(conversationDirectory:dir)
        var row = TranslationSession(originalText:"Alex confirmed 1500 dollars.",direction:.englishToChinese)
        row.translatedText = "旧译文"; row.isCompleted = true
        history.saveTranslation(TranslationRecord(originalText:row.originalText,translatedText:row.translatedText,direction:row.direction,timestamp:row.createdAt))
        let unrelated = TranslationRecord(originalText:"Another record at the same time.",translatedText:"另一条记录",direction:row.direction,timestamp:row.createdAt)
        history.saveTranslation(unrelated)
        history.saveConversation(SavedConversation(id:UUID(),startedAt:Date(),updatedAt:Date(),lines:[row],draft:"",draftDirection:.englishToChinese))
        let (model,_,reloadedHistory) = flow(directory:dir)
        XCTAssertTrue(model.updateOriginalText(entryID:row.id,text:"Alice confirmed 2500 dollars."))
        try await Task.sleep(nanoseconds:170_000_000)
        XCTAssertFalse(reloadedHistory.translationHistory.contains { $0.originalText == row.originalText })
        XCTAssertTrue(reloadedHistory.translationHistory.contains { $0.id == unrelated.id })
        XCTAssertTrue(reloadedHistory.translationHistory.contains { $0.id == row.id && $0.originalText == "Alice confirmed 2500 dollars." })
    }

    func testOldConversationWithoutManualFieldStillDecodes() throws {
        let row = TranslationSession(originalText:"Old saved sentence.",direction:.englishToChinese)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String:Any])
        object.removeValue(forKey:"manualOriginal")
        let decoded = try JSONDecoder().decode(TranslationSession.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(decoded.manualOriginal)
        XCTAssertEqual(decoded.id,row.id)
    }
}


@MainActor
final class RecognitionHintsAndCatchUpTests: XCTestCase {
    private func flow() -> (MainViewModel, MockSpeechRecognizer, AppSettings) {
        let settings = MockAppSettings()
        settings.apiProvider = .customAPI
        settings.customAPIKey = "test-key-local-only"
        settings.customAPIBaseURL = "https://translation.test/v1/chat/completions"
        settings.keepHistory = false
        settings.translationGlossary = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TranslationHTTPStub.self]
        let service = TranslationService(appSettings: settings, session: URLSession(configuration: config))
        let speech = MockSpeechRecognizer()
        return (MainViewModel(speechRecognizer: speech, translationService: service,
                              historyManager: MockHistoryManager(), appSettings: settings, retryDelays: [0.03, 0.03]), speech, settings)
    }
    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    private func source(_ request: URLRequest) -> String {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        guard let body = try? JSONDecoder().decode(TranslationService.OpenAIRequest.self, from: data),
              let message = body.messages.last else { return "unreadable request" }
        return message.content.replacingOccurrences(of: "Translate to Chinese: ", with: "")
    }

    func testGlossaryHintsAreDirectionalDeduplicatedAndBounded() {
        let speech = SpeechRecognizer()
        var terms = [GlossaryTerm(english: "  Alice   Chen  ", chinese: "陈爱丽"),
                     GlossaryTerm(english: "alice chen", chinese: "陈爱丽"),
                     GlossaryTerm(english: String(repeating: "x", count: 81), chinese: "长词")]
        terms += (0..<150).map { GlossaryTerm(english: "Term \($0)", chinese: "术语\($0)") }
        speech.setRecognitionGlossary(terms, direction: .englishToChinese)
        XCTAssertEqual(speech.recognitionHints.count, 100)
        XCTAssertEqual(speech.recognitionHints.first, "Alice Chen")
        XCTAssertFalse(speech.recognitionHints.contains(String(repeating: "x", count: 81)))
        let request = SFSpeechAudioBufferRecognitionRequest()
        speech.configureRecognitionRequest(request)
        XCTAssertEqual(request.contextualStrings, speech.recognitionHints)
        speech.setRecognitionGlossary(terms, direction: .chineseToEnglish)
        XCTAssertEqual(speech.recognitionHints.first, "陈爱丽")
        speech.setAudioInputSource(.systemAudio)
        let restarted = SFSpeechAudioBufferRecognitionRequest()
        speech.configureRecognitionRequest(restarted)
        XCTAssertEqual(restarted.contextualStrings, speech.recognitionHints)
        speech.setRecognitionGlossary([], direction: .chineseToEnglish)
        XCTAssertTrue(speech.recognitionHints.isEmpty)
    }

    func testDeadlineCutsKeepNamesAndTechnicalPhrasesWhole() {
        for phrase in ["Alice Chen", "vector database", "retrieval augmented generation", "检索增强生成", "retrieval-augmented generation"] {
            var transcript = LiveTranscript()
            transcript.protectedPhrases = [phrase]
            let prefix = String(repeating: "We review the plan carefully ", count: 3)
            let source = prefix + phrase + " before the presentation begins and every department confirms the final schedule"
            let start = Date()
            transcript.observe(prefix, at: start)
            transcript.observe(source, at: start.addingTimeInterval(7.9))
            let cap = prefix.count + phrase.count / 2
            _ = transcript.drain(at: start.addingTimeInterval(8), maxWait: 4, maxCharacters: cap)
            XCTAssertFalse(transcript.lines.isEmpty)
            _ = transcript.drain(at: start.addingTimeInterval(12), force: true)
            XCTAssertGreaterThanOrEqual(transcript.lines.count, 2)
            XCTAssertTrue(transcript.lines.contains { $0.text.contains(phrase) }, phrase)
            XCTAssertEqual(transcript.lines.map(\.text).joined().filter { !$0.isWhitespace }, source.filter { !$0.isWhitespace })
        }
    }

    func testSavedGlossaryChangesReachRecognitionWithoutStartingAudio() {
        let (model, speech, settings) = flow()
        settings.translationGlossary = [.init(english: "Jensen Huang", chinese: "黄仁勋")]
        XCTAssertEqual(speech.recognitionHints, ["Jensen Huang"])
        settings.selectedLanguageDirection = .chineseToEnglish
        XCTAssertEqual(speech.recognitionHints, ["黄仁勋"])
        XCTAssertFalse(speech.startRecordingCalled)
        withExtendedLifetime(model) {}
    }

    func testSlowFirstLineDoesNotBlockLaterLinesAndOrderIsStable() async throws {
        let (model, speech, _) = flow()
        TranslationHTTPStub.handler = { request in
            let source = self.source(request)
            return .init(data: TranslationHTTPStub.translated("译：" + source), delay: source.hasPrefix("First") ? 1.2 : 0.04)
        }
        speech.isRecording = true
        speech.recognizedText = "First sentence. Second sentence. Third sentence. Fourth sentence."
        let ids = model.displayEntries.map(\.id)
        try await pause(0.45)
        XCTAssertEqual(model.displayEntries.count, 4)
        XCTAssertTrue(model.displayEntries[0].translatedText.isEmpty)
        XCTAssertTrue(model.displayEntries.dropFirst().allSatisfy { !$0.translatedText.isEmpty })
        XCTAssertEqual(model.pendingTranslationCount, 1)
        try await pause(1)
        XCTAssertEqual(model.displayEntries.map(\.id), ids)
        XCTAssertEqual(model.pendingTranslationCount, 0)
        XCTAssertTrue(model.displayEntries.allSatisfy { !$0.isLive })
        model.stopTranslation()
    }

    func testParallelContextKeepsEarlierMeaningWhileItsReplyIsSlow() async throws {
        let (model, speech, _) = flow()
        TranslationHTTPStub.handler = { request in
            .init(data: TranslationHTTPStub.translated(self.source(request)), delay: 0.4)
        }
        speech.isRecording = true
        speech.recognizedText = "Alice Chen leads Project Aurora. She approves the budget. Future topic is different."
        let second = model.displayEntries[1].id
        let context = model.contextForSession(second)
        XCTAssertEqual(context.recent.map(\.original), ["Alice Chen leads Project Aurora."])
        XCTAssertEqual(context.recent.map(\.translation), [""])
        let instruction = context.instruction(for: "She approves the budget.", direction: .englishToChinese)
        XCTAssertTrue(instruction.contains("Alice Chen leads Project Aurora."))
        XCTAssertFalse(instruction.contains("Future topic"))
        try await pause(1)
        XCTAssertEqual(model.pendingTranslationCount, 0)
        model.stopTranslation()
    }

    func testRapidSpeechHasAtMostTwoRequestsAndCatchesUp() async throws {
        let (model, speech, _) = flow()
        var starts = 0
        TranslationHTTPStub.handler = { request in
            starts += 1
            return .init(data: TranslationHTTPStub.translated("译：" + self.source(request)), delay: 0.2)
        }
        speech.isRecording = true
        speech.recognizedText = (0..<12).map { "Sentence number \($0) is complete." }.joined(separator: " ")
        try await pause(0.08)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(model.displayEntries.count, 12)
        let originals = model.displayEntries.map(\.originalText)
        try await pause(1.5)
        XCTAssertEqual(starts, 12)
        XCTAssertEqual(model.pendingTranslationCount, 0)
        XCTAssertEqual(model.displayEntries.map(\.originalText), originals)
        XCTAssertTrue(model.displayEntries.allSatisfy { !$0.isLive && !$0.translatedText.isEmpty })
        model.stopTranslation()
    }

    func testSecondaryRevisionRemainsQueuedAndLatestWordsWin() async throws {
        let (model, speech, _) = flow()
        TranslationHTTPStub.handler = { request in .init(data: TranslationHTTPStub.translated(self.source(request)), delay: 0.25) }
        speech.isRecording = true
        speech.recognizedText = "First sentence. Alice can approve."
        try await pause(0.05)
        speech.recognizedText = "First sentence. Alice cannot approve."
        try await pause(0.75)
        XCTAssertEqual(model.displayEntries.count, 2)
        XCTAssertEqual(model.displayEntries[1].originalText, "Alice cannot approve.")
        XCTAssertEqual(model.displayEntries[1].translatedText, "Alice cannot approve.")
        XCTAssertEqual(model.pendingTranslationCount, 0)
        model.stopTranslation()
    }

    func testManualEditOfSecondaryDiscardsLateReplyAndClearCancelsBoth() async throws {
        let (model, speech, _) = flow()
        TranslationHTTPStub.handler = { request in .init(data: TranslationHTTPStub.translated(self.source(request)), delay: 0.25) }
        speech.isRecording = true
        speech.recognizedText = "First sentence. Alice approves."
        try await pause(0.05)
        let id = model.displayEntries[1].id
        XCTAssertTrue(model.updateOriginalText(entryID: id, text: "Alice rejects."))
        try await pause(0.6)
        XCTAssertEqual(model.displayEntries[1].translatedText, "Alice rejects.")
        XCTAssertTrue(model.displayEntries[1].isManuallyEdited)
        speech.recognizedText = "First sentence. Alice approves. Third sentence. Fourth sentence."
        try await pause(0.05)
        model.clearText()
        try await pause(0.4)
        XCTAssertTrue(model.displayEntries.isEmpty)
        XCTAssertFalse(model.isTranslating)
        model.stopTranslation()
    }

    func testRateLimitPausesBothWorkersAndRecoversWithoutDroppingRows() async throws {
        let (model, speech, _) = flow()
        var starts = 0
        TranslationHTTPStub.handler = { request in
            starts += 1
            if starts <= 2 { return .init(status:429, headers:["Retry-After":"1"]) }
            return .init(data: TranslationHTTPStub.translated(self.source(request)))
        }
        speech.isRecording = true
        speech.recognizedText = "First sentence. Second sentence. Third sentence."
        try await pause(0.6)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(model.pendingTranslationCount, 3)
        try await pause(2)
        XCTAssertEqual(starts, 5)
        XCTAssertEqual(model.pendingTranslationCount, 0)
        XCTAssertEqual(model.displayEntries.count, 3)
        model.stopTranslation()
    }
}

private final class IsolatedKeyStore: APIKeyStore {
    var values: [String: String] = [:]
    var writesAllowed = true
    var readsUnavailable = false
    var deletes = 0
    func save(value: String, service: String, account: String, allowInteraction: Bool) -> Bool {
        guard writesAllowed else { return false }
        values[account] = value
        return true
    }
    func read(service: String, account: String, allowInteraction: Bool) -> APIKeyReadResult {
        if readsUnavailable && !allowInteraction { return .unavailable }
        return values[account].map(APIKeyReadResult.value) ?? .missing
    }
    func delete(service: String, account: String, allowInteraction: Bool) -> Bool {
        deletes += 1
        guard writesAllowed else { return false }
        values.removeValue(forKey: account)
        return true
    }
}

@MainActor
final class SecureConfigurationTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "VoiceTranslation.SecureConfigurationTests." + UUID().uuidString)!
    }
    func testLegacyKeyMigratesOnlyAfterSecureSaveAndReloads() {
        let store = IsolatedKeyStore(), prefs = defaults()
        let key = Constants.UserDefaults.customAPIKey
        prefs.set("test-private-value", forKey: "stored_" + key)
        let settings = AppSettings(secureStore: store, defaults: prefs)
        XCTAssertEqual(settings.customAPIKey, "test-private-value")
        XCTAssertNil(prefs.object(forKey: "stored_" + key))
        XCTAssertEqual(store.values[key], "test-private-value")
        XCTAssertEqual(AppSettings(secureStore: store, defaults: prefs).customAPIKey, "test-private-value")
    }
    func testUnavailableStoragePreservesLegacyKeyAndShowsWarning() {
        let store = IsolatedKeyStore(), prefs = defaults()
        store.writesAllowed = false
        let key = Constants.UserDefaults.customAPIKey
        prefs.set("old-private-value", forKey: "stored_" + key)
        let settings = AppSettings(secureStore: store, defaults: prefs)
        XCTAssertEqual(settings.customAPIKey, "old-private-value")
        XCTAssertEqual(prefs.string(forKey: "stored_" + key), "old-private-value")
        XCTAssertFalse(settings.apiKeyStorageWarning.isEmpty)
        settings.customAPIKey = "new-value-in-memory"
        XCTAssertEqual(prefs.string(forKey: "stored_" + key), "old-private-value")
        XCTAssertFalse(settings.apiKeyStorageWarning.isEmpty)
    }
    func testNewKeyNeverFallsBackToPlainPreferencesWhenSecureSaveFails() {
        let store = IsolatedKeyStore(), prefs = defaults()
        store.writesAllowed = false
        let settings = AppSettings(secureStore: store, defaults: prefs)
        settings.customAPIKey = "test-key-not-persisted"
        XCTAssertNil(prefs.object(forKey: "stored_" + Constants.UserDefaults.customAPIKey))
        XCTAssertNil(prefs.object(forKey: Constants.UserDefaults.customAPIKey))
        XCTAssertFalse(settings.apiKeyStorageWarning.isEmpty)
    }
    func testOrdinaryPreferenceChangesCannotDeleteAnUnreadableKey() {
        let store = IsolatedKeyStore(), prefs = defaults()
        store.values[Constants.UserDefaults.customAPIKey] = "existing-secure-key"
        store.readsUnavailable = true
        let settings = AppSettings(secureStore: store, defaults: prefs)
        settings.translationGlossary = [.init(english: "Alice", chinese: "爱丽丝")]
        settings.selectedLanguageDirection = .englishToChinese
        XCTAssertEqual(store.deletes, 0)
        XCTAssertEqual(store.values[Constants.UserDefaults.customAPIKey], "existing-secure-key")
        XCTAssertFalse(settings.apiKeyStorageWarning.isEmpty)
    }
    func testSavedKeyCanBeExplicitlyAuthorizedAfterASigningChange() {
        let store = IsolatedKeyStore(), prefs = defaults()
        store.values[Constants.UserDefaults.customAPIKey] = "existing-secure-key"
        store.readsUnavailable = true
        let settings = AppSettings(secureStore: store, defaults: prefs)
        XCTAssertTrue(settings.customAPIKey.isEmpty)
        XCTAssertFalse(settings.apiKeyStorageWarning.isEmpty)
        settings.retryKeychainAccess()
        XCTAssertEqual(settings.customAPIKey, "existing-secure-key")
        XCTAssertTrue(settings.apiKeyStorageWarning.isEmpty)
        XCTAssertEqual(store.deletes, 0)
        XCTAssertNil(prefs.object(forKey: "stored_" + Constants.UserDefaults.customAPIKey))
    }

    func testClearingKeyDeletesOnlyTheSelectedCredential() {
        let store = IsolatedKeyStore(), prefs = defaults()
        store.values = [Constants.UserDefaults.customAPIKey: "custom-private-value", Constants.UserDefaults.openAIApiKey: "openai-private-value"]
        let settings = AppSettings(secureStore: store, defaults: prefs)
        settings.customAPIKey = ""
        XCTAssertNil(store.values[Constants.UserDefaults.customAPIKey])
        XCTAssertEqual(store.values[Constants.UserDefaults.openAIApiKey], "openai-private-value")
        XCTAssertTrue(settings.apiKeyStorageWarning.isEmpty)
    }
}

/// Opt-in live acceptance: delay one actual provider request without changing system networking.
private final class DelayedLiveTranslationProtocol: URLProtocol {
    static var requestNumber = 0
    static let lock = NSLock()
    private var work: DispatchWorkItem?
    private var requestTask: URLSessionDataTask?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requestNumber += 1
        let number = Self.requestNumber
        Self.lock.unlock()
        var forwarded = request
        if forwarded.httpBody == nil, let stream = forwarded.httpBodyStream {
            stream.open()
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            stream.close()
            forwarded.httpBodyStream = nil
            forwarded.httpBody = data
        }
        let delivery = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.requestTask = URLSession.shared.dataTask(with: forwarded) { [weak self] data, response, error in
                guard let self else { return }
                if let error { self.client?.urlProtocol(self, didFailWithError: error); return }
                guard let response, let data else { return }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            self.requestTask?.resume()
        }
        work = delivery
        DispatchQueue.global().asyncAfter(deadline: .now() + (number == 1 ? 10 : 0), execute: delivery)
    }
    override func stopLoading() { work?.cancel(); requestTask?.cancel() }
}

@MainActor
final class LiveCatchUpAcceptanceTests: XCTestCase {
    func testRealProviderKeepsLaterLinesMovingDuringOneDelayedReply() async throws {
        let fallback = "/tmp/voice-live-acceptance.json"
        guard let path = ProcessInfo.processInfo.environment["VOICE_LIVE_CONFIG"] ??
                (FileManager.default.fileExists(atPath: fallback) ? fallback : nil) else {
            throw XCTSkip("Live service acceptance requires an explicit private configuration path.")
        }
        struct Configuration: Decodable { let endpoint: String; let model: String; let apiKey: String; let report: String? }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let suite = "VoiceTranslation.LiveAcceptance." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let settings = AppSettings(secureStore: IsolatedKeyStore(), defaults: preferences)
        settings.apiProvider = .customAPI
        settings.customAPIKey = config.apiKey
        settings.customAPIBaseURL = config.endpoint
        settings.customAPIModel = config.model
        settings.keepHistory = false
        settings.selectedLanguageDirection = .englishToChinese
        settings.translationGlossary = try Glossary.parse("Jensen Huang = 黄仁勋\nProject Aurora = 晨光计划\nretrieval-augmented generation = 检索增强生成")
        let network = URLSessionConfiguration.ephemeral
        network.protocolClasses = [DelayedLiveTranslationProtocol.self]
        DelayedLiveTranslationProtocol.requestNumber = 0
        let speech = MockSpeechRecognizer()
        let model = MainViewModel(speechRecognizer: speech,
            translationService: TranslationService(appSettings: settings, session: URLSession(configuration: network)),
            historyManager: MockHistoryManager(), appSettings: settings)
        let inputs = ["Jensen Huang leads Project Aurora.",
                      "Project Aurora uses retrieval-augmented generation.",
                      "Jensen Huang will explain retrieval-augmented generation.",
                      "The final Project Aurora budget is 2500 dollars."]
        let started = Date()
        speech.isRecording = true
        speech.recognizedText = inputs.joined(separator: " ")
        let ids = model.displayEntries.map(\.id)
        try await Task.sleep(nanoseconds: 8_000_000_000)
        XCTAssertTrue(model.displayEntries[0].isLive, "The intentionally delayed first line must still be pending.")
        let laterCompletedBeforeFirst = model.displayEntries.dropFirst().filter { !$0.isLive }.count
        XCTAssertGreaterThanOrEqual(laterCompletedBeforeFirst, 1, "At least one later line must finish during the first-line delay.")
        for _ in 0..<100 where model.pendingTranslationCount > 0 {
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        XCTAssertEqual(model.pendingTranslationCount, 0)
        XCTAssertEqual(model.displayEntries.map(\.id), ids)
        XCTAssertEqual(model.displayEntries.map(\.originalText), inputs)
        let translations = model.displayEntries.map(\.translatedText)
        XCTAssertTrue(translations[0].contains("黄仁勋") && translations[0].contains("晨光计划"))
        XCTAssertTrue(translations[1].contains("检索增强生成"))
        XCTAssertTrue(translations[2].contains("黄仁勋") && translations[2].contains("检索增强生成"))
        XCTAssertTrue(translations[3].contains("2500") || translations[3].contains("2,500"))
        if let report = config.report ?? ProcessInfo.processInfo.environment["VOICE_LIVE_REPORT"] {
            let output: [String: Any] = ["elapsed_seconds": Date().timeIntervalSince(started),
                "first_request_delay_seconds": 10, "later_completed_before_first": laterCompletedBeforeFirst,
                "rows": zip(inputs, translations).map { ["original": $0.0, "translation": $0.1] },
                "pending_final": model.pendingTranslationCount]
            try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: report), options: .atomic)
        }
        model.stopTranslation()
        model.clearText()
    }
}


@MainActor
final class MicrophonePermissionFlowTests: XCTestCase {
    func testStoppingBeforeCaptureStartsDoesNotRepeatPreviousRecognition() {
        let speech = SpeechRecognizer()
        speech.authorizationStatus = .authorized
        let settings = MockAppSettings()
        settings.keepHistory = false
        let model = MainViewModel(speechRecognizer: speech,
                                  translationService: MockTranslationService(),
                                  historyManager: MockHistoryManager(),
                                  appSettings: settings,
                                  errorHandler: MockErrorHandler())
        // Previous capture text remains available after stop, as it did in the app.
        speech.recognizedText = "Jensen Huang reviewed Project Aurora."
        speech.startRecording()
        XCTAssertEqual(speech.recognizedText, "")
        // Stop synchronously before preparation or consent can finish.
        model.stopTranslation()
        XCTAssertTrue(model.displayEntries.isEmpty)
        XCTAssertFalse(speech.isRecording)
    }
    func testPermissionWaitDoesNotTriggerRecoveryOrClaimCaptureReady() async throws {
        let speech = SpeechRecognizer()
        speech.isRecording = true
        speech.microphoneAuthorization = { .notDetermined }
        var reply: CheckedContinuation<Bool, Never>?
        let asked = expectation(description: "Microphone consent requested")
        speech.requestMicrophoneAuthorization = { await withCheckedContinuation { reply = $0; asked.fulfill() } }
        let request = Task { try await speech.ensureMicrophonePermission() }
        await fulfillment(of: [asked], timeout: 2)
        XCTAssertTrue(speech.isWaitingForMicrophonePermission)
        XCTAssertTrue(speech.recordingStatus.contains("允许麦克风"))
        XCTAssertFalse(speech.isListening)
        speech.checkCaptureHealth(at: Date().addingTimeInterval(120))
        XCTAssertEqual(speech.recordingPhase, .starting)
        reply?.resume(returning: false)
        do { try await request.value; XCTFail("Denied microphone must stop preparation") } catch {}
        XCTAssertFalse(speech.isRecording)
        XCTAssertFalse(speech.isWaitingForMicrophonePermission)
        XCTAssertEqual(speech.recordingPhase, .failed)
    }
    func testDeniedMicrophoneDoesNotRequestOrRetryAutomatically() async {
        let speech = SpeechRecognizer()
        speech.isRecording = true
        speech.microphoneAuthorization = { .denied }
        var prompts = 0
        speech.requestMicrophoneAuthorization = { prompts += 1; return true }
        do { try await speech.ensureMicrophonePermission(); XCTFail("Denied permission must fail") } catch {}
        XCTAssertEqual(prompts, 0)
        XCTAssertFalse(speech.isRecording)
        XCTAssertTrue(speech.recordingStatus.contains("麦克风尚未授权"))
    }
    func testStoppingDuringPermissionPromptCannotStartAnOldCaptureAttempt() async {
        let speech = SpeechRecognizer()
        speech.isRecording = true
        speech.microphoneAuthorization = { .notDetermined }
        var reply: CheckedContinuation<Bool, Never>?
        let asked = expectation(description: "Microphone consent requested")
        speech.requestMicrophoneAuthorization = { await withCheckedContinuation { reply = $0; asked.fulfill() } }
        let request = Task { try await speech.ensureMicrophonePermission() }
        await fulfillment(of: [asked], timeout: 2)
        speech.stopRecording()
        reply?.resume(returning: true)
        do { try await request.value; XCTFail("Stopped attempt cannot resume") } catch {}
        XCTAssertFalse(speech.isRecording)
        XCTAssertFalse(speech.isWaitingForMicrophonePermission)
    }
}

@MainActor
final class PrivacySecurityRegressionTests: XCTestCase {
    private var directory: URL!
    private var prefs: UserDefaults!
    private var suite: String!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("voice-privacy-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "VoiceTranslation.PrivacyTests.\(UUID())"
        prefs = UserDefaults(suiteName: suite)!
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        prefs.removePersistentDomain(forName: suite)
    }
    private func saved() -> SavedConversation {
        var line = TranslationSession(originalText: "Private synthetic source.", direction: .englishToChinese)
        line.isCompleted = true
        line.translatedText = "虚构私密译文。"
        return SavedConversation(id: UUID(), startedAt: Date(), updatedAt: Date(), lines: [line], draft: "", draftDirection: .englishToChinese)
    }
    private func record(_ line: TranslationSession) -> TranslationRecord {
        TranslationRecord(originalText: line.originalText, translatedText: line.translatedText,
                          direction: line.direction, timestamp: line.createdAt, id: line.id)
    }
    private func makeModel(_ history: HistoryManager) -> MainViewModel {
        let settings = MockAppSettings()
        settings.keepHistory = true
        return MainViewModel(speechRecognizer: MockSpeechRecognizer(), translationService: MockTranslationService(),
                             historyManager: history, appSettings: settings)
    }
    private func assertSourceAbsentOnDisk(_ source: String) throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains(source), url.lastPathComponent)
        }
    }
    func testDeletedRowCannotReturnAfterReopenStaleSaveOrRestore() throws {
        let history = HistoryManager(conversationDirectory: directory)
        var conversation = saved()
        var survivor = TranslationSession(originalText: "Keep this other sentence.", direction: .englishToChinese)
        survivor.isCompleted = true; survivor.translatedText = "保留的译文。"
        conversation.lines.append(survivor)
        history.saveConversation(conversation)
        history.saveTranslation(record(conversation.lines[0]))
        history.saveTranslation(record(survivor))
        let model = makeModel(history)
        history.deleteRecord(record(conversation.lines[0]))
        XCTAssertEqual(model.displayEntries.map(\.originalText), [survivor.originalText])
        model.checkpointConversation()
        history.saveConversation(conversation) // stale queued checkpoint
        history.saveTranslation(record(conversation.lines[0])) // late completion
        let reopened = HistoryManager(conversationDirectory: directory)
        reopened.saveConversation(conversation) // stale object after reopening
        model.restoreConversation(conversation)
        XCTAssertFalse(model.displayEntries.contains { $0.id == conversation.lines[0].id })
        XCTAssertEqual(reopened.activeConversation()?.lines.map(\.id), [survivor.id])
        XCTAssertFalse(reopened.translationHistory.contains { $0.id == conversation.lines[0].id })
        try assertSourceAbsentOnDisk(conversation.lines[0].originalText)
    }
    func testClearAllClearsOpenWindowAndRejectsOldCheckpointsAcrossRestart() throws {
        let history = HistoryManager(conversationDirectory: directory)
        let conversation = saved()
        history.saveConversation(conversation)
        history.saveTranslation(record(conversation.lines[0]))
        let model = makeModel(history)
        XCTAssertFalse(model.displayEntries.isEmpty)
        history.clearAllHistory()
        XCTAssertTrue(model.displayEntries.isEmpty)
        model.checkpointConversation()
        model.restoreConversation(conversation)
        history.saveConversation(conversation)
        let reopened = HistoryManager(conversationDirectory: directory)
        reopened.saveConversation(conversation)
        XCTAssertNil(reopened.activeConversation())
        XCTAssertTrue(reopened.savedConversations.isEmpty)
        XCTAssertTrue(model.displayEntries.isEmpty)
        try assertSourceAbsentOnDisk(conversation.lines[0].originalText)
        // New conversations can still be saved after deleting old ones.
        let fresh = saved()
        reopened.saveConversation(fresh)
        XCTAssertEqual(reopened.activeConversation()?.id, fresh.id)
    }
    func testInternalReplacementDoesNotDeleteConversationOrBlockCorrectedRow() {
        let history = HistoryManager(conversationDirectory: directory)
        let conversation = saved()
        let original = record(conversation.lines[0])
        history.saveConversation(conversation)
        history.saveTranslation(original)
        history.removeReplacedRecord(original)
        let replacement = TranslationRecord(originalText: "Corrected private source.", translatedText: "更正译文。",
                                            direction: original.direction, timestamp: original.timestamp, id: original.id)
        history.saveTranslation(replacement)
        XCTAssertFalse(history.isDeleted(original.id))
        XCTAssertEqual(history.translationHistory.first(where: { $0.id == original.id })?.originalText, replacement.originalText)
        XCTAssertEqual(history.activeConversation()?.lines.count, 1)
    }
    func testSystemPermissionFailureCannotRequestOrStartMicrophone() async {
        let speech = SpeechRecognizer()
        speech.setAudioInputSource(.systemAudio)
        speech.isRecording = true
        speech.screenCaptureAuthorization = { false }
        var microphoneChecks = 0
        speech.microphoneAuthorization = { microphoneChecks += 1; return .authorized }
        do { try await speech.fallbackToScreenCaptureKit(SFSpeechAudioBufferRecognitionRequest()); XCTFail("Must reject unavailable system audio") }
        catch { XCTAssertEqual(error as? SystemAudioError, .permissionDenied) }
        XCTAssertEqual(microphoneChecks, 0)
        XCTAssertFalse(speech.isListening)
        XCTAssertEqual(speech.audioHeartbeat.snapshot().bufferAt, nil)
        speech.stopRecording()
    }
    func testSystemCaptureFailureStaysOnSystemSourceAcrossRetries() async {
        let speech = SpeechRecognizer()
        speech.setAudioInputSource(.systemAudio)
        speech.isRecording = true
        speech.screenCaptureAuthorization = { true }
        var failures = 0, microphoneChecks = 0
        speech.screenCaptureStart = { _ in failures += 1; throw SystemAudioError.streamStartFailed("synthetic failure") }
        speech.microphoneAuthorization = { microphoneChecks += 1; return .authorized }
        for _ in 0..<3 {
            do { try await speech.fallbackToScreenCaptureKit(SFSpeechAudioBufferRecognitionRequest()); XCTFail("Capture must fail") }
            catch { XCTAssertEqual(error as? SystemAudioError, .streamStartFailed("synthetic failure")) }
        }
        XCTAssertEqual(failures, 3)
        XCTAssertEqual(microphoneChecks, 0)
        XCTAssertFalse(speech.isListening)
        XCTAssertNil(speech.audioHeartbeat.snapshot().bufferAt)
        speech.stopRecording()
    }
    func testFullSystemStartupStopsOnDeniedPermissionWithoutMicrophone() async throws {
        let speech = SpeechRecognizer()
        speech.authorizationStatus = .authorized
        speech.setLanguage("en-US")
        speech.setAudioInputSource(.systemAudio)
        speech.coreAudioCaptureStart = { _ in throw SystemAudioError.deviceNotAvailable }
        speech.screenCaptureAuthorization = { false }
        var microphoneChecks = 0
        speech.microphoneAuthorization = { microphoneChecks += 1; return .authorized }
        speech.startRecording()
        for _ in 0..<100 where speech.recordingPhase != .failed {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(speech.recordingPhase, .failed)
        XCTAssertFalse(speech.isRecording)
        XCTAssertFalse(speech.isListening)
        XCTAssertEqual(speech.selectedAudioInputSource, .systemAudio)
        XCTAssertEqual(microphoneChecks, 0)
        XCTAssertNil(speech.audioHeartbeat.snapshot().bufferAt)
        XCTAssertTrue(speech.recordingStatus.contains("麦克风未开启"))
        speech.stopRecording()
    }
    func testClearingDuringDelayedTranslationCannotRestoreDeletedSource() async throws {
        let history = HistoryManager(conversationDirectory: directory)
        let settings = MockAppSettings(); settings.keepHistory = true
        let speech = MockSpeechRecognizer()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationHTTPStub.self]
        TranslationHTTPStub.handler = { _ in .init(data: TranslationHTTPStub.translated("Late private translation"), delay: 0.3) }
        defer { TranslationHTTPStub.handler = nil }
        let model = MainViewModel(speechRecognizer: speech,
            translationService: TranslationService(appSettings: settings, session: URLSession(configuration: configuration)),
            historyManager: history, appSettings: settings)
        speech.isRecording = true
        speech.recognizedText = "Private synthetic source."
        try await Task.sleep(nanoseconds: 40_000_000)
        model.checkpointConversation()
        history.clearAllHistory()
        try await Task.sleep(nanoseconds: 500_000_000)
        model.checkpointConversation()
        XCTAssertTrue(model.displayEntries.isEmpty)
        XCTAssertTrue(history.translationHistory.isEmpty)
        XCTAssertNil(HistoryManager(conversationDirectory: directory).activeConversation())
        XCTAssertFalse(history.exportHistory().contains("Private synthetic source"))
        try assertSourceAbsentOnDisk("Private synthetic source")
        model.stopTranslation()
    }
    func testContinuingRecognitionAndManualEditingCannotResurrectDeletedRow() async throws {
        let history = HistoryManager(conversationDirectory: directory)
        let settings = MockAppSettings(); settings.keepHistory = true
        settings.selectedLanguageDirection = .englishToChinese
        let speech = MockSpeechRecognizer()
        let model = MainViewModel(speechRecognizer: speech, translationService: MockTranslationService(),
                                  historyManager: history, appSettings: settings)
        speech.isRecording = true
        speech.recognizedText = "Private synthetic source."
        try await Task.sleep(nanoseconds: 350_000_000)
        let deleted = try XCTUnwrap(history.translationHistory.first { $0.originalText == "Private synthetic source." })
        history.deleteRecord(deleted)
        speech.recognizedText = "Private synthetic source. Another public sentence."
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertFalse(model.displayEntries.contains { $0.originalText.contains("Private synthetic source") })
        let survivor = try XCTUnwrap(model.displayEntries.first)
        XCTAssertTrue(model.updateOriginalText(entryID: survivor.id, text: "Corrected public sentence."))
        try await Task.sleep(nanoseconds: 350_000_000)
        model.stopTranslation()
        model.checkpointConversation()
        let reopened = HistoryManager(conversationDirectory: directory)
        XCTAssertFalse(reopened.savedConversations.contains { $0.searchText.contains("Private synthetic source") })
        XCTAssertTrue(reopened.savedConversations.contains { $0.searchText.contains("Corrected public sentence") })
        try assertSourceAbsentOnDisk("Private synthetic source")
    }
    func testHistoryDeletionClearsSuggestionsAndDiscardsTheirLateReply() async throws {
        let history = HistoryManager(conversationDirectory: directory)
        let model = makeModel(history)
        model.appSettings.apiProvider = .customAPI
        model.appSettings.customAPIKey = "synthetic-suggestions-test-key"
        model.appSettings.customAPIBaseURL = "https://test.invalid/v1/chat/completions"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationHTTPStub.self]
        model.suggestionService.session = URLSession(configuration: configuration)
        let started = expectation(description: "Suggestion request started")
        let content = "[{\"tag\":\"reply\",\"primary\":\"Private suggestion\",\"secondary\":\"旧建议\"}]"
        let response = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        TranslationHTTPStub.handler = { _ in
            started.fulfill()
            return .init(data: response, delay: 0.3)
        }
        defer { TranslationHTTPStub.handler = nil }
        model.suggestionService.suggestions = [ChatSuggestion(tag: .reply, primaryText: "Private source", secondaryText: "旧建议")]
        model.suggestionService.refresh(from: [TranslationEntryModel(originalText: "Private synthetic source.")], direction: .englishToChinese)
        await fulfillment(of: [started], timeout: 2)
        history.clearAllHistory()
        XCTAssertTrue(model.suggestionService.suggestions.isEmpty)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(model.suggestionService.suggestions.isEmpty)
        XCTAssertFalse(model.suggestionService.isGenerating)
    }
    func testLegacyCleanupWithRealOSKeychainAndSyntheticCredentials() throws {
        let store = NamespacedSystemKeyStore()
        let key = Constants.UserDefaults.customAPIKey
        let value = "synthetic-local-migration-check"
        guard store.save(value: value, service: "ignored", account: key, allowInteraction: false) else {
            throw XCTSkip("System keychain unavailable on this test host")
        }
        defer { _ = store.delete(service: "ignored", account: key, allowInteraction: false) }
        let url = try legacyFile([key: value, "stored_" + key: value, "preserve": "settings"])
        let settings = AppSettings(secureStore: store, defaults: prefs, legacyPreferencesURL: url)
        XCTAssertEqual(settings.customAPIKey, value)
        XCTAssertNil(try readLegacy(url)[key])
        XCTAssertNil(try readLegacy(url)["stored_" + key])
        XCTAssertEqual(try readLegacy(url)["preserve"] as? String, "settings")
        settings.apiProvider = .customAPI
        settings.clearApiKey()
        if case .missing = store.read(service: "ignored", account: key, allowInteraction: false) {} else { XCTFail("Synthetic key must be removed") }
    }
    private func legacyFile(_ values: [String: Any]) throws -> URL {
        let url = directory.appendingPathComponent("legacy.plist")
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0).write(to: url)
        return url
    }
    private func readLegacy(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    }
    func testBothLegacyKeysCleanedAfterVerifiedSecureMigrationAndReload() throws {
        let a = Constants.UserDefaults.openAIApiKey, b = Constants.UserDefaults.customAPIKey
        let url = try legacyFile([a: "synthetic-old-a", "stored_" + a: "synthetic-old-a", b: "synthetic-old-b", "stored_" + b: "synthetic-old-b", "untouched": "preserve me"])
        let store = IsolatedKeyStore()
        _ = AppSettings(secureStore: store, defaults: prefs, legacyPreferencesURL: url)
        XCTAssertEqual(store.values[a], "synthetic-old-a")
        XCTAssertEqual(store.values[b], "synthetic-old-b")
        let remaining = try readLegacy(url)
        XCTAssertEqual(remaining["untouched"] as? String, "preserve me")
        for key in [a,b] { XCTAssertNil(remaining[key]); XCTAssertNil(remaining["stored_" + key]) }
        XCTAssertEqual(AppSettings(secureStore: store, defaults: prefs, legacyPreferencesURL: url).customAPIKey, "synthetic-old-b")
    }
    func testPreviouslyMigratedSettingsStillCleanOldCopyWithoutOverwritingNewKey() throws {
        let key = Constants.UserDefaults.customAPIKey
        let store = IsolatedKeyStore(); store.values[key] = "newer-secure-key"
        prefs.set(LanguageDirection.englishToChinese.rawValue, forKey: Constants.UserDefaults.selectedLanguageDirection)
        let url = try legacyFile([key: "obsolete-copy", Constants.UserDefaults.selectedLanguageDirection: LanguageDirection.chineseToEnglish.rawValue])
        let settings = AppSettings(secureStore: store, defaults: prefs, legacyPreferencesURL: url)
        XCTAssertEqual(settings.customAPIKey, "newer-secure-key")
        XCTAssertEqual(settings.selectedLanguageDirection, .englishToChinese)
        XCTAssertNil(try readLegacy(url)[key])
    }
    func testFailedSecureMigrationKeepsOldCopyAndCanRetrySafely() throws {
        let key = Constants.UserDefaults.customAPIKey
        let store = IsolatedKeyStore(); store.writesAllowed = false
        let url = try legacyFile([key: "only-copy-until-secure"])
        let settings = AppSettings(secureStore: store, defaults: prefs, legacyPreferencesURL: url)
        XCTAssertFalse(settings.apiKeyStorageWarning.isEmpty)
        XCTAssertEqual(try readLegacy(url)[key] as? String, "only-copy-until-secure")
        store.writesAllowed = true
        let retried = AppSettings(secureStore: store, defaults: prefs, legacyPreferencesURL: url)
        XCTAssertEqual(retried.customAPIKey, "only-copy-until-secure")
        XCTAssertNil(try readLegacy(url)[key])
    }
    func testExplicitClearAlsoRemovesOldCopiesWithoutDeletingOtherProvider() throws {
        let a = Constants.UserDefaults.openAIApiKey, b = Constants.UserDefaults.customAPIKey
        let store = IsolatedKeyStore(); store.readsUnavailable = true
        store.values[a] = "secure-a"; store.values[b] = "secure-b"
        let url = try legacyFile([a: "old-a", b: "old-b", "keep": 123])
        let settings = AppSettings(secureStore: store, defaults: prefs, legacyPreferencesURL: url)
        settings.apiProvider = .customAPI
        settings.clearApiKey()
        XCTAssertNil(store.values[b]); XCTAssertEqual(store.values[a], "secure-a")
        let remaining = try readLegacy(url)
        XCTAssertNil(remaining[b]); XCTAssertEqual(remaining[a] as? String, "old-a")
        XCTAssertEqual(remaining["keep"] as? Int, 123)
    }
}

private final class NamespacedSystemKeyStore: APIKeyStore {
    private let system = SystemAPIKeyStore()
    private let namespace = "com.voicetranslation.security-check." + UUID().uuidString
    func save(value: String, service: String, account: String, allowInteraction: Bool) -> Bool {
        system.save(value: value, service: namespace, account: account, allowInteraction: allowInteraction)
    }
    func read(service: String, account: String, allowInteraction: Bool) -> APIKeyReadResult {
        system.read(service: namespace, account: account, allowInteraction: allowInteraction)
    }
    func delete(service: String, account: String, allowInteraction: Bool) -> Bool {
        system.delete(service: namespace, account: account, allowInteraction: allowInteraction)
    }
}
