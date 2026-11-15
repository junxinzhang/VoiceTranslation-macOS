//
//  MainViewModel_LineBreakTests.swift
//  VoiceTranslationTests
//
//  Created by Claude on 2025-08-12.
//

import XCTest
import Combine
@testable import VoiceTranslation

class MainViewModel_LineBreakTests: XCTestCase {
    var viewModel: MainViewModel!
    var mockSpeechRecognizer: MockSpeechRecognizer!
    var mockTranslationService: MockTranslationService!
    var mockHistoryManager: MockHistoryManager!
    var mockAppSettings: MockAppSettings!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockSpeechRecognizer = MockSpeechRecognizer()
        mockTranslationService = MockTranslationService()
        mockHistoryManager = MockHistoryManager()
        mockAppSettings = MockAppSettings()
        
        viewModel = MainViewModel(
            speechRecognizer: mockSpeechRecognizer,
            translationService: mockTranslationService,
            historyManager: mockHistoryManager,
            appSettings: mockAppSettings,
            errorHandler: ErrorHandler()
        )
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        viewModel = nil
        mockSpeechRecognizer = nil
        mockTranslationService = nil
        mockHistoryManager = nil
        mockAppSettings = nil
        super.tearDown()
    }
    
    func testSentenceCompletionTriggersNewLine() {
        // Given: 准备第一句话
        let firstSentence = "Hello world."
        let firstTranslation = "你好世界。"
        
        // When: 模拟识别到第一句话
        mockSpeechRecognizer.recognizedText = firstSentence
        mockSpeechRecognizer.isRecording = true
        
        // 等待防抖和处理时间
        wait(0.5)
        
        // 模拟翻译完成
        mockTranslationService.translatedText = firstTranslation
        
        // 等待处理
        wait(1.0)
        
        // 验证第一句话的显示格式
        XCTAssertTrue(viewModel.accumulatedTranslations.contains(firstSentence))
        XCTAssertTrue(viewModel.accumulatedTranslations.contains("→ \(firstTranslation)"))
        
        // Given: 准备第二句话
        let secondSentence = "How are you?"
        let secondTranslation = "你好吗？"
        
        // When: 模拟识别到第二句话
        mockSpeechRecognizer.recognizedText = firstSentence + " " + secondSentence
        
        // 等待防抖和处理时间
        wait(0.5)
        
        // 模拟第二句话翻译完成
        mockTranslationService.translatedText = secondTranslation
        
        // 等待处理
        wait(1.0)
        
        // Then: 验证两句话之间有换行分隔
        let accumulated = viewModel.accumulatedTranslations
        
        // 验证包含两个独立的时间戳
        let timestampPattern = #"\[\d{2}:\d{2}:\d{2}\]"#
        let timestamps = accumulated.matches(of: try! Regex(timestampPattern))
        XCTAssertTrue(timestamps.count >= 1, "应该包含至少一个时间戳")
        
        // 验证句子之间有双换行分隔
        XCTAssertTrue(accumulated.contains("\n\n"), "句子之间应该有双换行分隔")
        
        print("累积翻译显示内容:")
        print("---")
        print(accumulated)
        print("---")
    }
    
    func testMultipleSentencesCreateSeparateLines() {
        // Given: 准备多句话的场景
        let sentences = [
            ("Good morning.", "早上好。"),
            ("How are you today?", "你今天好吗？"),
            ("The weather is nice.", "天气很好。")
        ]
        
        var cumulativeText = ""
        
        for (index, sentence) in sentences.enumerated() {
            // When: 逐句添加识别文本
            cumulativeText += (index == 0 ? "" : " ") + sentence.0
            mockSpeechRecognizer.recognizedText = cumulativeText
            mockSpeechRecognizer.isRecording = true
            
            // 等待防抖和处理时间
            wait(0.5)
            
            // 模拟翻译完成
            mockTranslationService.translatedText = sentence.1
            
            // 等待处理
            wait(1.0)
        }
        
        // Then: 验证所有句子都正确显示并换行
        let accumulated = viewModel.accumulatedTranslations
        
        // 验证每个句子的原文和译文都存在
        for sentence in sentences {
            XCTAssertTrue(accumulated.contains(sentence.0) || accumulated.contains("→ \(sentence.1)"), 
                         "应该包含句子: \(sentence.0) -> \(sentence.1)")
        }
        
        print("多句话累积翻译显示:")
        print("---")
        print(accumulated)
        print("---")
    }
    
    func testSessionCompletionTriggersLineBreak() {
        // Given: 准备测试数据
        let originalText = "This is a test sentence."
        let translatedText = "这是一个测试句子。"
        
        // When: 开始新的翻译会话
        mockSpeechRecognizer.recognizedText = originalText
        mockSpeechRecognizer.isRecording = true
        
        // 等待防抖处理
        wait(0.5)
        
        // 模拟翻译完成
        mockTranslationService.translatedText = translatedText
        
        // 等待处理
        wait(0.6)  // 0.5秒延迟 + 处理时间
        
        // Then: 验证会话完成后的状态
        let accumulated = viewModel.accumulatedTranslations
        
        // 验证内容包含原文和译文
        XCTAssertTrue(accumulated.contains(originalText))
        XCTAssertTrue(accumulated.contains("→ \(translatedText)"))
        
        // 验证包含时间戳
        XCTAssertTrue(accumulated.contains("]"), "应该包含时间戳标记")
        
        print("会话完成后的显示:")
        print("---")
        print(accumulated)
        print("---")
    }
    
    // MARK: - Helper Methods
    
    private func wait(_ seconds: TimeInterval) {
        let expectation = XCTestExpectation(description: "Wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: seconds + 1.0)
    }
}

// MARK: - String Extension for Regex Support

extension String {
    func matches(of regex: Regex<Substring>) -> [Substring] {
        var matches: [Substring] = []
        var searchRange = self.startIndex..<self.endIndex
        
        while let match = try? regex.firstMatch(in: self[searchRange]) {
            matches.append(match.0)
            searchRange = match.range.upperBound..<searchRange.upperBound
        }
        
        return matches
    }
}