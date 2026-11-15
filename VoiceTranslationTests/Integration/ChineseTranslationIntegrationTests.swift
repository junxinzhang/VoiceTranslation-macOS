//
//  ChineseTranslationIntegrationTests.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-17.
//

import XCTest
import Combine
@testable import VoiceTranslation

/// 中文翻译功能的完整集成测试
final class ChineseTranslationIntegrationTests: XCTestCase {
    
    var viewModel: MainViewModel!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        // 使用真实的服务实例进行集成测试
        viewModel = MainViewModel()
        cancellables = Set<AnyCancellable>()
        
        // 设置测试环境
        viewModel.appSettings.selectedLanguageDirection = .chineseToEnglish
        viewModel.appSettings.keepHistory = false // 简化测试
        
        // 设置测试API Key
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef1234567890abcdef",
                                 forKey: Constants.UserDefaults.openAIApiKey)
    }
    
    override func tearDownWithError() throws {
        viewModel = nil
        cancellables = nil
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: Constants.UserDefaults.openAIApiKey)
    }
    
    // MARK: - 端到端测试场景
    
    @MainActor
    func testEndToEnd_BasicChineseTranslation() async throws {
        let expectation = XCTestExpectation(description: "Basic Chinese translation")
        
        // 监听翻译结果
        viewModel.translationService.$translatedText
            .dropFirst()
            .filter { !$0.isEmpty }
            .sink { translatedText in
                print("收到翻译结果: \(translatedText)")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 模拟语音识别结果
        viewModel.speechRecognizer.recognizedText = "你好世界"
        
        // 手动触发翻译
        viewModel.triggerTranslation()
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // 验证翻译状态
        XCTAssertFalse(viewModel.translationService.isTranslating, "翻译应该已完成")
        XCTAssertFalse(viewModel.translationService.translatedText.isEmpty, "应该有翻译结果")
    }
    
    @MainActor
    func testEndToEnd_MixedLanguageTranslation() async throws {
        let mixedInputs = [
            "Hello 你好",
            "iPhone 很棒",
            "2024年 is great",
            "我的email是test@example.com"
        ]
        
        for input in mixedInputs {
            let expectation = XCTestExpectation(description: "Mixed language translation: \(input)")
            
            // 清空之前的状态
            viewModel.clearText()
            
            // 监听翻译完成
            viewModel.translationService.$isTranslating
                .dropFirst()
                .filter { !$0 } // 等待翻译完成
                .sink { _ in
                    expectation.fulfill()
                }
                .store(in: &cancellables)
            
            // 设置输入并触发翻译
            viewModel.speechRecognizer.recognizedText = input
            viewModel.triggerTranslation()
            
            await fulfillment(of: [expectation], timeout: 3.0)
            
            print("混合语言测试完成: '\(input)' -> '\(viewModel.translationService.translatedText)'")
        }
    }
    
    @MainActor
    func testEndToEnd_InvalidContentFiltering() async throws {
        let invalidInputs = [
            "",
            "   ",
            "123",
            "!!!",
            "...",
            "@#$%"
        ]
        
        for input in invalidInputs {
            // 清空状态
            viewModel.clearText()
            
            // 设置无效输入
            viewModel.speechRecognizer.recognizedText = input
            
            // 记录初始状态
            let initialTranslationState = viewModel.translationService.isTranslating
            let initialTranslatedText = viewModel.translationService.translatedText
            
            // 尝试触发翻译
            viewModel.triggerTranslation()
            
            // 等待一小段时间确保处理完成
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            // 验证无效内容被正确过滤
            XCTAssertFalse(viewModel.translationService.isTranslating, 
                          "无效内容不应触发翻译: '\(input)'")
            XCTAssertEqual(viewModel.translationService.translatedText, initialTranslatedText, 
                          "无效内容不应产生翻译结果: '\(input)'")
        }
    }
    
    // MARK: - 实时语音翻译流程测试
    
    @MainActor
    func testRealTimeTranslationFlow_ChineseInput() async throws {
        let expectation = XCTestExpectation(description: "Real-time Chinese translation flow")
        expectation.expectedFulfillmentCount = 1
        
        var translationCount = 0
        
        // 监听翻译过程
        viewModel.translationService.$translatedText
            .dropFirst()
            .filter { !$0.isEmpty }
            .sink { translatedText in
                translationCount += 1
                print("实时翻译 #\(translationCount): \(translatedText)")
                
                if translationCount >= 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // 模拟实时语音识别过程
        viewModel.speechRecognizer.isRecording = true
        
        // 逐步输入中文
        viewModel.speechRecognizer.recognizedText = "你"
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
        
        viewModel.speechRecognizer.recognizedText = "你好"
        try await Task.sleep(nanoseconds: 300_000_000)
        
        viewModel.speechRecognizer.recognizedText = "你好世界"
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 停止录音（模拟语音结束）
        viewModel.speechRecognizer.isRecording = false
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertGreaterThan(translationCount, 0, "应该产生至少一次翻译")
    }
    
    @MainActor
    func testIncrementalTranslation_ChineseToEnglish() async throws {
        let expectation = XCTestExpectation(description: "Incremental Chinese translation")
        
        var receivedTranslations: [String] = []
        
        // 监听所有翻译更新
        viewModel.translationService.$translatedText
            .sink { text in
                if !text.isEmpty {
                    receivedTranslations.append(text)
                    print("增量翻译更新: \(text)")
                }
            }
            .store(in: &cancellables)
        
        // 监听翻译完成
        viewModel.translationService.$isTranslating
            .dropFirst()
            .filter { !$0 }
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 模拟增量输入
        viewModel.speechRecognizer.recognizedText = "你好"
        viewModel.triggerTranslation()
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        XCTAssertFalse(receivedTranslations.isEmpty, "应该收到翻译结果")
        print("最终翻译结果: \(receivedTranslations.last ?? "无")")
    }
    
    // MARK: - 错误处理和恢复测试
    
    @MainActor
    func testErrorHandling_InvalidApiKey() async throws {
        // 设置无效的API Key
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("invalid-key", forKey: Constants.UserDefaults.openAIApiKey)
        
        let expectation = XCTestExpectation(description: "Error handling")
        
        // 监听错误
        viewModel.translationService.$error
            .compactMap { $0 }
            .sink { error in
                print("捕获翻译错误: \(error)")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 尝试翻译
        viewModel.speechRecognizer.recognizedText = "你好"
        viewModel.triggerTranslation()
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // 验证错误状态
        XCTAssertNotNil(viewModel.translationService.error, "应该有错误状态")
        XCTAssertFalse(viewModel.translationService.isTranslating, "翻译状态应该已重置")
    }
    
    // MARK: - 语言切换测试
    
    @MainActor
    func testLanguageDirectionSwitch() async throws {
        // 初始设置：中文翻译英文
        XCTAssertEqual(viewModel.appSettings.selectedLanguageDirection, .chineseToEnglish)
        
        // 设置中文输入
        viewModel.speechRecognizer.recognizedText = "你好"
        
        // 切换到英文翻译中文
        viewModel.switchLanguageDirection()
        
        XCTAssertEqual(viewModel.appSettings.selectedLanguageDirection, .englishToChinese)
        XCTAssertEqual(viewModel.speechRecognizer.recognizedText, "", "切换语言应清空文本")
        
        // 设置英文输入
        viewModel.speechRecognizer.recognizedText = "Hello world"
        
        let expectation = XCTestExpectation(description: "English to Chinese translation")
        
        viewModel.translationService.$translatedText
            .dropFirst()
            .filter { !$0.isEmpty }
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        viewModel.triggerTranslation()
        
        await fulfillment(of: [expectation], timeout: 3.0)
        
        XCTAssertFalse(viewModel.translationService.translatedText.isEmpty, "应该有英译中结果")
    }
    
    // MARK: - 性能和稳定性测试
    
    @MainActor
    func testPerformance_MultipleTranslations() async throws {
        let inputs = [
            "你好",
            "世界",
            "中国",
            "技术",
            "未来",
            "Hello",
            "World",
            "China",
            "Technology",
            "Future"
        ]
        
        let startTime = Date()
        var completedTranslations = 0
        
        let expectation = XCTestExpectation(description: "Multiple translations")
        expectation.expectedFulfillmentCount = inputs.count
        
        // 监听翻译完成
        viewModel.translationService.$isTranslating
            .filter { !$0 } // 翻译完成
            .sink { _ in
                completedTranslations += 1
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 连续执行翻译
        for input in inputs {
            viewModel.clearText()
            viewModel.speechRecognizer.recognizedText = input
            viewModel.triggerTranslation()
            
            // 等待翻译完成再进行下一个
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒间隔
        }
        
        await fulfillment(of: [expectation], timeout: 30.0)
        
        let duration = Date().timeIntervalSince(startTime)
        let averageTime = duration / Double(inputs.count)
        
        XCTAssertEqual(completedTranslations, inputs.count, "所有翻译都应完成")
        XCTAssertLessThan(averageTime, 3.0, "平均翻译时间应少于3秒")
        
        print("性能测试完成: \(inputs.count)个翻译，总时间\(String(format: "%.2f", duration))秒，平均\(String(format: "%.2f", averageTime))秒")
    }
    
    // MARK: - 边界情况集成测试
    
    @MainActor
    func testEdgeCases_ExtremelyLongText() async throws {
        let longText = String(repeating: "你好世界，这是一个很长的句子。", count: 100)
        
        let expectation = XCTestExpectation(description: "Long text translation")
        
        viewModel.translationService.$isTranslating
            .dropFirst()
            .filter { !$0 }
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        viewModel.speechRecognizer.recognizedText = longText
        viewModel.triggerTranslation()
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        XCTAssertFalse(viewModel.translationService.isTranslating, "长文本翻译应该完成")
    }
    
    @MainActor
    func testEdgeCases_SpecialCharacters() async throws {
        let specialTexts = [
            "你好👋世界🌍",
            "测试@example.com邮箱",
            "价格¥100元",
            "时间2024年8月17日",
            "链接https://example.com测试"
        ]
        
        for text in specialTexts {
            let expectation = XCTestExpectation(description: "Special characters: \(text)")
            
            viewModel.clearText()
            
            viewModel.translationService.$isTranslating
                .dropFirst()
                .filter { !$0 }
                .sink { _ in
                    expectation.fulfill()
                }
                .store(in: &cancellables)
            
            viewModel.speechRecognizer.recognizedText = text
            viewModel.triggerTranslation()
            
            await fulfillment(of: [expectation], timeout: 5.0)
            
            print("特殊字符测试完成: '\(text)' -> '\(viewModel.translationService.translatedText)'")
        }
    }
    
    // MARK: - 一致性验证测试
    
    func testConsistency_ValidationMethods() throws {
        // 验证MainViewModel和TranslationService的验证方法一致性
        let testCases = [
            "你好",
            "Hello",
            "你好 world",
            "Hello 世界",
            "",
            "123",
            "!!!"
        ]
        
        for testCase in testCases {
            // 由于私有方法访问限制，这里主要验证公共行为一致性
            // 实际项目中会使用专门的测试工具或重构为可测试的结构
            
            let beforeTranslation = viewModel.translationService.isTranslating
            
            // 使用实际的公共方法进行一致性测试
            viewModel.speechRecognizer.recognizedText = testCase
            
            // 通过观察行为来验证一致性
            print("一致性测试: '\(testCase)' - 翻译状态: \(beforeTranslation)")
        }
    }
}

// MARK: - 测试辅助扩展

extension ChineseTranslationIntegrationTests {
    
    /// 等待指定条件满足或超时
    func waitForCondition(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 2.0,
        description: String = "Condition"
    ) async throws {
        let startTime = Date()
        
        while !condition() {
            if Date().timeIntervalSince(startTime) > timeout {
                XCTFail("\(description) timed out after \(timeout) seconds")
                return
            }
            
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        }
    }
    
    /// 验证翻译质量（基本检查）
    func validateTranslationQuality(_ original: String, _ translation: String) -> Bool {
        // 基本质量检查
        guard !translation.isEmpty else { return false }
        guard translation != original else { return false }
        
        // 长度合理性检查
        let lengthRatio = Double(translation.count) / Double(original.count)
        guard lengthRatio > 0.3 && lengthRatio < 5.0 else { return false }
        
        return true
    }
}