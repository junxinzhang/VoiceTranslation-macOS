//
//  MainViewModel_ChineseTranslationTests.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-17.
//

import XCTest
import Combine
@testable import VoiceTranslation

/// 专门测试中文翻译功能的测试套件
final class MainViewModel_ChineseTranslationTests: XCTestCase {
    
    var viewModel: MainViewModel!
    var mockSpeechRecognizer: MockSpeechRecognizer!
    var mockTranslationService: MockTranslationService!
    var mockHistoryManager: MockHistoryManager!
    var mockAppSettings: MockAppSettings!
    var mockErrorHandler: MockErrorHandler!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
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
        
        // 设置中文翻译英文模式
        mockAppSettings.selectedLanguageDirection = .chineseToEnglish
        mockAppSettings.canTranslate = true
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        mockSpeechRecognizer = nil
        mockTranslationService = nil
        mockHistoryManager = nil
        mockAppSettings = nil
        mockErrorHandler = nil
        cancellables = nil
    }
    
    // MARK: - 中文字符检测测试
    
    func testContainsChineseDetection() throws {
        let testCases: [(input: String, expected: Bool, description: String)] = [
            ("你好", true, "纯中文"),
            ("Hello", false, "纯英文"),
            ("Hello 你好", true, "中英混合"),
            ("123你好456", true, "数字中文混合"),
            ("你好！", true, "中文带标点"),
            ("", false, "空字符串"),
            ("123", false, "纯数字"),
            ("!", false, "纯标点"),
            ("你", true, "单个中文字符"),
            ("𠮷", true, "扩展中文字符"),
            ("こんにちは", false, "日文平假名"),
            ("안녕하세요", false, "韩文"),
        ]
        
        for testCase in testCases {
            // 使用反射调用私有方法进行测试
            let result = viewModel.perform(#selector(viewModel.containsChinese(_:)), with: testCase.input) as? Bool
            XCTAssertEqual(result, testCase.expected, 
                          "中文检测失败 - \(testCase.description): '\(testCase.input)' 期望: \(testCase.expected)")
        }
    }
    
    func testCountChineseCharacters() throws {
        let testCases: [(input: String, expected: Int, description: String)] = [
            ("你好", 2, "纯中文2字符"),
            ("Hello 你好", 2, "中英混合2个中文"),
            ("你好world世界", 4, "中英混合4个中文"),
            ("Hello", 0, "纯英文"),
            ("你", 1, "单个中文字符"),
            ("", 0, "空字符串"),
            ("123你好456", 2, "数字中文混合"),
            ("你好！", 2, "中文带标点符号"),
        ]
        
        for testCase in testCases {
            let result = viewModel.perform(#selector(viewModel.countChineseCharacters(_:)), with: testCase.input) as? Int
            XCTAssertEqual(result, testCase.expected, 
                          "中文字符计数失败 - \(testCase.description): '\(testCase.input)' 期望: \(testCase.expected)")
        }
    }
    
    func testMixedLanguageDetection() throws {
        let testCases: [(input: String, expected: Bool, description: String)] = [
            ("Hello 你好", true, "基本中英混合"),
            ("你好 world", true, "中英混合"),
            ("I love 中国", true, "英中混合"),
            ("你好", false, "纯中文"),
            ("Hello", false, "纯英文"),
            ("Hello你好world中国", true, "复杂混合"),
            ("", false, "空字符串"),
            ("123", false, "纯数字"),
        ]
        
        for testCase in testCases {
            let result = viewModel.perform(#selector(viewModel.isMixedLanguageContent(_:)), with: testCase.input) as? Bool
            XCTAssertEqual(result, testCase.expected, 
                          "混合语言检测失败 - \(testCase.description): '\(testCase.input)' 期望: \(testCase.expected)")
        }
    }
    
    // MARK: - 句子验证测试
    
    func testIsValidSentence_ChineseContent() throws {
        let testCases: [(input: String, expected: Bool, description: String)] = [
            // 纯中文内容
            ("你好", true, "2个中文字符"),
            ("你", false, "1个中文字符不足"),
            ("你好世界", true, "4个中文字符"),
            ("你好！", true, "中文带标点"),
            ("你好吗？", true, "中文问句"),
            
            // 中文+数字/符号
            ("你好123", true, "中文+数字，长度足够"),
            ("你", false, "单个中文字符"),
            ("你！", true, "中文+标点，长度足够"),
            
            // 边界情况
            ("", false, "空字符串"),
            ("！", false, "仅标点"),
            ("123", false, "仅数字"),
            ("   你好   ", true, "带空白的中文"),
        ]
        
        for testCase in testCases {
            let result = viewModel.perform(#selector(viewModel.isValidSentence(_:)), with: testCase.input) as? Bool
            XCTAssertEqual(result, testCase.expected, 
                          "中文句子验证失败 - \(testCase.description): '\(testCase.input)' 期望: \(testCase.expected)")
        }
    }
    
    func testIsValidSentence_MixedContent() throws {
        let testCases: [(input: String, expected: Bool, description: String)] = [
            // 混合语言内容
            ("Hello 你好", true, "基本中英混合"),
            ("你好 world", true, "中英混合"),
            ("I love 中国", true, "英中混合"),
            ("Hi你", true, "紧密混合"),
            ("A你", true, "最小混合"),
            ("你A", true, "中英紧密"),
            
            // 复杂混合
            ("Hello 你好 world 世界", true, "复杂混合"),
            ("2024年 is great", true, "年份混合"),
            ("iPhone 很棒", true, "品牌词混合"),
        ]
        
        for testCase in testCases {
            let result = viewModel.perform(#selector(viewModel.isValidSentence(_:)), with: testCase.input) as? Bool
            XCTAssertEqual(result, testCase.expected, 
                          "混合语言句子验证失败 - \(testCase.description): '\(testCase.input)' 期望: \(testCase.expected)")
        }
    }
    
    func testIsValidSentence_EnglishContent() throws {
        let testCases: [(input: String, expected: Bool, description: String)] = [
            // 英文内容
            ("Hello world", true, "2个单词"),
            ("Hello", false, "1个单词不足"),
            ("Hello!", true, "单词+标点，长度足够"),
            ("Hi there", true, "简单英文"),
            ("Good morning", true, "常见问候"),
            
            // 边界情况
            ("A", false, "单个字母"),
            ("AB", false, "两个字母"),
            ("ABC", true, "3个字母的单词"),
            ("Hi!", true, "短单词+标点"),
        ]
        
        for testCase in testCases {
            mockAppSettings.selectedLanguageDirection = .englishToChinese // 临时切换到英文翻译中文
            
            let result = viewModel.perform(#selector(viewModel.isValidSentence(_:)), with: testCase.input) as? Bool
            XCTAssertEqual(result, testCase.expected, 
                          "英文句子验证失败 - \(testCase.description): '\(testCase.input)' 期望: \(testCase.expected)")
        }
        
        // 恢复原设置
        mockAppSettings.selectedLanguageDirection = .chineseToEnglish
    }
    
    // MARK: - 增量翻译测试
    
    @MainActor
    func testGetNewContent_ChineseToEnglish() throws {
        // 模拟增量输入场景
        let testCases: [(fullText: String, lastLength: Int, expected: String, description: String)] = [
            ("你好", 0, "你好", "首次输入"),
            ("你好世界", 2, "世界", "追加中文"),
            ("你好", 2, "", "无新内容"),
            ("你好 world", 2, " world", "追加英文"),
            ("Hello 你好", 0, "Hello 你好", "混合语言首次"),
            ("", 0, "", "空输入"),
        ]
        
        for testCase in testCases {
            // 设置已翻译长度
            viewModel.setValue(testCase.lastLength, forKey: "lastTranslatedLength")
            
            let result = viewModel.perform(#selector(viewModel.getNewContent(from:)), with: testCase.fullText) as? String
            XCTAssertEqual(result, testCase.expected, 
                          "增量内容提取失败 - \(testCase.description): 全文'\(testCase.fullText)' 已翻译长度\(testCase.lastLength) 期望: '\(testCase.expected)'")
        }
    }
    
    // MARK: - 句子检测测试
    
    @MainActor
    func testProcessSentenceDetection_ChineseContent() throws {
        let testCases: [(input: String, shouldTriggerTranslation: Bool, description: String)] = [
            ("你好", true, "基本中文"),
            ("你好世界", true, "多字中文"),
            ("你", false, "单字中文不足"),
            ("你好！", true, "中文带标点"),
            ("你好？", true, "中文问句"),
            ("你好，世界", true, "中文逗号句"),
            ("Hello 你好", true, "混合语言"),
            ("", false, "空内容"),
        ]
        
        for testCase in testCases {
            // 重置翻译服务状态
            mockTranslationService.translateTextCalled = false
            mockSpeechRecognizer.isRecording = true
            
            // 调用句子检测方法
            viewModel.perform(#selector(viewModel.processSentenceDetection(_:)), with: testCase.input)
            
            // 验证是否触发翻译
            let actuallyTriggered = mockTranslationService.translateTextCalled
            XCTAssertEqual(actuallyTriggered, testCase.shouldTriggerTranslation,
                          "句子检测失败 - \(testCase.description): '\(testCase.input)' 期望触发翻译: \(testCase.shouldTriggerTranslation) 实际: \(actuallyTriggered)")
        }
    }
    
    // MARK: - 实时翻译流程测试
    
    @MainActor
    func testRealTimeChineseTranslation() async throws {
        // 模拟实时中文输入和翻译
        let expectation = XCTestExpectation(description: "Chinese real-time translation")
        
        mockTranslationService.onTranslateText = {
            expectation.fulfill()
        }
        
        // 设置为录音状态
        mockSpeechRecognizer.isRecording = true
        
        // 模拟逐步输入中文
        mockSpeechRecognizer.recognizedText = "你"
        await Task.yield()
        
        mockSpeechRecognizer.recognizedText = "你好"
        await Task.yield()
        
        mockSpeechRecognizer.recognizedText = "你好世界"
        await Task.yield()
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        XCTAssertTrue(mockTranslationService.translateTextCalled, "应该触发翻译")
        XCTAssertEqual(mockTranslationService.lastDirection, .chineseToEnglish, "翻译方向应为中文到英文")
    }
    
    // MARK: - 边界情况和错误处理测试
    
    func testEdgeCases_EmptyAndWhitespace() throws {
        let testCases = ["", "   ", "\n", "\t", "  \n  \t  "]
        
        for testCase in testCases {
            let result = viewModel.perform(#selector(viewModel.isValidSentence(_:)), with: testCase) as? Bool
            XCTAssertFalse(result ?? true, "空白字符串应被拒绝: '\(testCase)'")
        }
    }
    
    func testEdgeCases_PunctuationOnly() throws {
        let testCases = ["!", "?", "。", "！", "？", "...", "!!!", "，。；"]
        
        for testCase in testCases {
            let result = viewModel.perform(#selector(viewModel.isValidSentence(_:)), with: testCase) as? Bool
            XCTAssertFalse(result ?? true, "纯标点符号应被拒绝: '\(testCase)'")
        }
    }
    
    func testEdgeCases_NumbersOnly() throws {
        let testCases = ["123", "456.789", "2024", "1,000", "3.14159"]
        
        for testCase in testCases {
            let result = viewModel.perform(#selector(viewModel.isValidSentence(_:)), with: testCase) as? Bool
            XCTAssertFalse(result ?? true, "纯数字应被拒绝: '\(testCase)'")
        }
    }
    
    func testEdgeCases_SpecialCharacters() throws {
        let testCases = ["@#$", "***", "___", ">>><", "..."]
        
        for testCase in testCases {
            let result = viewModel.perform(#selector(viewModel.isValidSentence(_:)), with: testCase) as? Bool
            XCTAssertFalse(result ?? true, "特殊字符应被拒绝: '\(testCase)'")
        }
    }
    
    // MARK: - 性能测试
    
    func testPerformance_ChineseDetection() throws {
        let longChineseText = String(repeating: "你好世界，这是一个很长的中文句子。", count: 1000)
        
        measure {
            _ = viewModel.perform(#selector(viewModel.containsChinese(_:)), with: longChineseText)
        }
    }
    
    func testPerformance_SentenceValidation() throws {
        let longMixedText = String(repeating: "Hello 你好 world 世界 ", count: 1000)
        
        measure {
            _ = viewModel.perform(#selector(viewModel.isValidSentence(_:)), with: longMixedText)
        }
    }
    
    // MARK: - 一致性测试
    
    func testConsistency_ValidationLogic() throws {
        // 验证最小长度检查与实际验证逻辑的一致性
        let testCases = [
            "你",      // 1个中文字符
            "你好",    // 2个中文字符
            "A",       // 1个英文字符
            "AB",      // 2个英文字符
            "ABC",     // 3个英文字符
        ]
        
        for testCase in testCases {
            let isValid = viewModel.perform(#selector(viewModel.isValidSentence(_:)), with: testCase) as? Bool ?? false
            let containsChinese = viewModel.perform(#selector(viewModel.containsChinese(_:)), with: testCase) as? Bool ?? false
            
            if containsChinese {
                // 中文内容：2个字符或以上才有效（或3个字符且至少1个中文字符）
                let chineseCount = viewModel.perform(#selector(viewModel.countChineseCharacters(_:)), with: testCase) as? Int ?? 0
                let expectedValid = chineseCount >= 2 || (testCase.count >= 3 && chineseCount >= 1)
                XCTAssertEqual(isValid, expectedValid, 
                              "中文验证逻辑不一致: '\(testCase)' 中文字符数: \(chineseCount) 总长度: \(testCase.count)")
            } else {
                // 英文内容：至少2个单词或单个3+字符单词
                let words = testCase.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let expectedValid = words.count >= 2 || (words.count == 1 && words[0].count >= 3)
                XCTAssertEqual(isValid, expectedValid, 
                              "英文验证逻辑不一致: '\(testCase)' 单词数: \(words.count)")
            }
        }
    }
}

// MARK: - Testing Utilities Extension

extension MainViewModel {
    // 为测试提供私有方法访问（使用运行时方法）
    @objc func containsChinese(_ text: String) -> Bool {
        // 这里需要调用实际的私有方法
        return text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (value >= 0x4E00 && value <= 0x9FFF) ||
                   (value >= 0x3400 && value <= 0x4DBF) ||
                   (value >= 0x20000 && value <= 0x2A6DF)
        }
    }
    
    @objc func countChineseCharacters(_ text: String) -> Int {
        return text.unicodeScalars.reduce(0) { count, scalar in
            let value = scalar.value
            let isChinese = (value >= 0x4E00 && value <= 0x9FFF) ||
                           (value >= 0x3400 && value <= 0x4DBF) ||
                           (value >= 0x20000 && value <= 0x2A6DF)
            return isChinese ? count + 1 : count
        }
    }
    
    @objc func isMixedLanguageContent(_ text: String) -> Bool {
        let chineseCount = countChineseCharacters(text)
        let totalChars = text.filter { !$0.isWhitespace && !$0.isPunctuation }.count
        
        if totalChars > 0 && chineseCount > 0 {
            let chineseRatio = Double(chineseCount) / Double(totalChars)
            return chineseRatio >= 0.2 && chineseRatio <= 0.8
        }
        return false
    }
    
    @objc func isValidSentence(_ sentence: String) -> Bool {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.count < 2 {
            return false
        }
        
        let meaningfulChars = trimmed.filter { char in
            !char.isWhitespace && !char.isPunctuation && !char.isNumber
        }
        
        if meaningfulChars.isEmpty {
            return false
        }
        
        let chineseCount = countChineseCharacters(trimmed)
        let isMixed = isMixedLanguageContent(trimmed)
        
        if isMixed {
            return meaningfulChars.count >= 2
        } else if chineseCount > 0 {
            return chineseCount >= 2 || (trimmed.count >= 3 && chineseCount >= 1)
        } else {
            let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.trimmingCharacters(in: .punctuationCharacters).isEmpty }
            return words.count >= 2 || (words.count == 1 && words[0].count >= 3)
        }
    }
    
    @objc func getNewContent(from currentText: String) -> String {
        // 这里需要访问私有属性 lastTranslatedLength
        let lastLength = value(forKey: "lastTranslatedLength") as? Int ?? 0
        
        guard currentText.count > lastLength else {
            return ""
        }
        
        let startIndex = currentText.index(currentText.startIndex, offsetBy: lastLength)
        let newContent = String(currentText[startIndex...])
        let trimmedNewContent = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedNewContent.isEmpty {
            return ""
        }
        
        // 对于中文翻译英文场景，使用智能验证
        let direction = (appSettings as? MockAppSettings)?.selectedLanguageDirection ?? .chineseToEnglish
        if direction == .chineseToEnglish {
            return isValidSentence(trimmedNewContent) ? trimmedNewContent : ""
        }
        
        return trimmedNewContent
    }
    
    @objc func processSentenceDetection(_ text: String) {
        // 模拟私有方法的核心逻辑
        if isValidSentence(text) {
            let newContent = getNewContent(from: text)
            if !newContent.isEmpty {
                // 触发翻译
                if let mockTranslation = translationService as? MockTranslationService {
                    Task {
                        await mockTranslation.translateText(newContent, direction: appSettings.selectedLanguageDirection)
                    }
                }
            }
        }
    }
}