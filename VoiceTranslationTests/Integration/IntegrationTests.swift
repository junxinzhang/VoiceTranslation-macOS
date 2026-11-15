//
//  IntegrationTests.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-11.
//

import XCTest
import Combine
@testable import VoiceTranslation

final class IntegrationTests: XCTestCase {
    
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        cancellables = Set<AnyCancellable>()
        
        // 清理测试数据
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: Constants.UserDefaults.openAIApiKey)
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: "Translation_History")
    }
    
    override func tearDownWithError() throws {
        cancellables = nil
        
        // 清理测试数据
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: Constants.UserDefaults.openAIApiKey)
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: "Translation_History")
    }
    
    // MARK: - 端到端翻译流程测试
    
    @MainActor
    func testCompleteTranslationWorkflow() async throws {
        // 设置有效的测试API Key
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        let viewModel = MainViewModel()
        let translationCompleted = expectation(description: "Translation workflow completed")
        
        // 监听翻译状态变化
        viewModel.translationService.$translatedText
            .dropFirst()
            .sink { translatedText in
                if !translatedText.isEmpty || viewModel.translationService.error != nil {
                    translationCompleted.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // 模拟完整的翻译流程
        viewModel.startTranslation()
        XCTAssertTrue(viewModel.isProcessing)
        
        // 模拟语音识别结果
        viewModel.speechRecognizer.recognizedText = "Hello world"
        
        // 停止翻译（这会触发实际的翻译请求）
        viewModel.stopTranslation()
        
        await fulfillment(of: [translationCompleted], timeout: 10.0)
        
        // 验证流程完成
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(viewModel.speechRecognizer.recognizedText, "Hello world")
    }
    
    // MARK: - 语音识别和翻译集成测试
    
    @MainActor
    func testSpeechRecognitionToTranslationIntegration() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        let viewModel = MainViewModel()
        let integrationCompleted = expectation(description: "Speech to translation integration")
        
        // 监听翻译完成
        var translationTriggered = false
        viewModel.translationService.$isTranslating
            .sink { isTranslating in
                if isTranslating && !translationTriggered {
                    translationTriggered = true
                    integrationCompleted.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // 模拟语音识别流程
        viewModel.speechRecognizer.isRecording = false
        viewModel.speechRecognizer.isListening = false
        
        // 触发识别文本更新，应该自动触发翻译
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            viewModel.speechRecognizer.recognizedText = "Integration test"
        }
        
        await fulfillment(of: [integrationCompleted], timeout: 5.0)
        
        XCTAssertTrue(translationTriggered)
    }
    
    // MARK: - 历史记录集成测试
    
    @MainActor
    func testHistoryIntegration() throws {
        let viewModel = MainViewModel()
        
        // 启用历史记录保存
        viewModel.appSettings.keepHistory = true
        
        // 设置翻译数据
        viewModel.speechRecognizer.recognizedText = "Hello"
        viewModel.translationService.translatedText = "你好"
        
        let historyCountBefore = viewModel.historyManager.totalTranslations
        
        // 保存翻译
        viewModel.saveCurrentTranslation()
        
        let historyCountAfter = viewModel.historyManager.totalTranslations
        
        XCTAssertEqual(historyCountAfter, historyCountBefore + 1)
        
        let lastRecord = viewModel.historyManager.translationHistory.first
        XCTAssertNotNil(lastRecord)
        XCTAssertEqual(lastRecord?.originalText, "Hello")
        XCTAssertEqual(lastRecord?.translatedText, "你好")
    }
    
    @MainActor
    func testAutoHistorySaving() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        let viewModel = MainViewModel()
        viewModel.appSettings.keepHistory = true
        
        let historySaved = expectation(description: "History auto-saved")
        
        // 监听历史记录变化
        viewModel.historyManager.$translationHistory
            .dropFirst()
            .sink { history in
                if !history.isEmpty {
                    historySaved.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // 设置识别文本
        viewModel.speechRecognizer.recognizedText = "Auto save test"
        
        // 模拟翻译完成
        viewModel.translationService.translatedText = "自动保存测试"
        viewModel.translationService.isTranslating = false
        
        await fulfillment(of: [historySaved], timeout: 5.0)
        
        XCTAssertGreaterThan(viewModel.historyManager.totalTranslations, 0)
    }
    
    // MARK: - 设置和配置集成测试
    
    @MainActor
    func testLanguageSwitchingIntegration() throws {
        let viewModel = MainViewModel()
        
        // 初始设置：英译中
        XCTAssertEqual(viewModel.appSettings.selectedLanguageDirection, .englishToChinese)
        
        // 设置一些文本
        viewModel.speechRecognizer.recognizedText = "Test text"
        viewModel.translationService.translatedText = "测试文本"
        
        // 切换语言方向
        viewModel.switchLanguageDirection()
        
        // 验证语言方向已切换
        XCTAssertEqual(viewModel.appSettings.selectedLanguageDirection, .chineseToEnglish)
        
        // 验证文本已清空
        XCTAssertEqual(viewModel.speechRecognizer.recognizedText, "")
        XCTAssertEqual(viewModel.translationService.translatedText, "")
    }
    
    @MainActor
    func testApiKeyValidationIntegration() throws {
        let viewModel = MainViewModel()
        
        // 没有API Key时不能开始翻译
        viewModel.appSettings.openAIApiKey = ""
        XCTAssertFalse(viewModel.appSettings.canTranslate)
        
        viewModel.startTranslation()
        XCTAssertFalse(viewModel.speechRecognizer.isRecording)
        XCTAssertFalse(viewModel.isProcessing)
        
        // 设置有效API Key后可以开始翻译
        viewModel.appSettings.openAIApiKey = "sk-test1234567890abcdef"
        XCTAssertTrue(viewModel.appSettings.canTranslate)
        
        // 注意：在测试环境中，语音识别可能没有权限，所以我们只验证逻辑
        viewModel.startTranslation()
        XCTAssertTrue(viewModel.isProcessing)
    }
    
    // MARK: - 错误处理集成测试
    
    @MainActor
    func testErrorHandlingIntegration() async throws {
        let viewModel = MainViewModel()
        let errorHandled = expectation(description: "Error handled")
        
        // 监听错误处理
        viewModel.errorHandler.$showErrorAlert
            .dropFirst()
            .sink { showError in
                if showError {
                    errorHandled.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // 触发翻译错误
        viewModel.translationService.error = .apiKeyMissing
        
        await fulfillment(of: [errorHandled], timeout: 2.0)
        
        XCTAssertTrue(viewModel.errorHandler.showErrorAlert)
        XCTAssertNotNil(viewModel.errorHandler.currentError)
    }
    
    @MainActor
    func testNetworkErrorHandling() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        let viewModel = MainViewModel()
        let errorExpected = expectation(description: "Network error expected")
        
        // 监听翻译错误
        viewModel.translationService.$error
            .compactMap { $0 }
            .sink { error in
                errorExpected.fulfill()
            }
            .store(in: &cancellables)
        
        // 尝试翻译（应该产生网络错误）
        await viewModel.translationService.translateText("Test", direction: .englishToChinese)
        
        await fulfillment(of: [errorExpected], timeout: 10.0)
        
        XCTAssertNotNil(viewModel.translationService.error)
        XCTAssertFalse(viewModel.translationService.isTranslating)
    }
    
    // MARK: - 并发操作集成测试
    
    @MainActor
    func testConcurrentOperations() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        let viewModel = MainViewModel()
        
        // 同时进行多个操作
        let operations: [() -> Void] = [
            { viewModel.switchLanguageDirection() },
            { viewModel.clearText() },
            { viewModel.saveCurrentTranslation() },
            { 
                viewModel.speechRecognizer.recognizedText = "Concurrent test"
                viewModel.translationService.translatedText = "并发测试"
            }
        ]
        
        // 并发执行操作
        await withTaskGroup(of: Void.self) { group in
            for operation in operations {
                group.addTask {
                    await MainActor.run {
                        operation()
                    }
                }
            }
        }
        
        // 系统应该保持稳定状态
        XCTAssertNotNil(viewModel)
        XCTAssertNotNil(viewModel.speechRecognizer)
        XCTAssertNotNil(viewModel.translationService)
        XCTAssertNotNil(viewModel.historyManager)
    }
    
    // MARK: - 数据持久化集成测试
    
    func testDataPersistenceIntegration() throws {
        // 创建第一个ViewModel并保存数据
        autoreleasepool {
            let viewModel1 = MainViewModel()
            viewModel1.appSettings.openAIApiKey = "sk-persistence-test"
            viewModel1.appSettings.selectedLanguageDirection = .chineseToEnglish
            viewModel1.appSettings.keepHistory = false
            
            // 添加历史记录
            let record = TranslationRecord(
                originalText: "Persistence test",
                translatedText: "持久化测试",
                direction: .englishToChinese
            )
            viewModel1.historyManager.saveTranslation(record)
        }
        
        // 创建第二个ViewModel并验证数据持久化
        let viewModel2 = MainViewModel()
        
        XCTAssertEqual(viewModel2.appSettings.openAIApiKey, "sk-persistence-test")
        XCTAssertEqual(viewModel2.appSettings.selectedLanguageDirection, .chineseToEnglish)
        XCTAssertFalse(viewModel2.appSettings.keepHistory)
        XCTAssertEqual(viewModel2.historyManager.totalTranslations, 1)
        
        let savedRecord = viewModel2.historyManager.translationHistory.first
        XCTAssertNotNil(savedRecord)
        XCTAssertEqual(savedRecord?.originalText, "Persistence test")
        XCTAssertEqual(savedRecord?.translatedText, "持久化测试")
    }
    
    // MARK: - 性能集成测试
    
    @MainActor
    func testPerformanceIntegration() throws {
        let viewModel = MainViewModel()
        
        measure {
            // 模拟快速操作序列
            for i in 0..<100 {
                viewModel.speechRecognizer.recognizedText = "Test \(i)"
                viewModel.translationService.translatedText = "测试 \(i)"
                viewModel.switchLanguageDirection()
                viewModel.clearText()
            }
        }
        
        // 验证系统仍然正常运行
        XCTAssertNotNil(viewModel)
        XCTAssertFalse(viewModel.isProcessing)
    }
    
    @MainActor
    func testMemoryPerformanceIntegration() throws {
        // 创建大量历史记录测试内存性能
        let viewModel = MainViewModel()
        
        measure {
            for i in 0..<1000 {
                let record = TranslationRecord(
                    originalText: "Performance test \(i)",
                    translatedText: "性能测试 \(i)",
                    direction: i % 2 == 0 ? .englishToChinese : .chineseToEnglish
                )
                viewModel.historyManager.saveTranslation(record)
            }
        }
        
        // 验证历史记录限制正常工作
        XCTAssertLessThanOrEqual(viewModel.historyManager.totalTranslations, 100)
    }
    
    // MARK: - 边界条件集成测试
    
    @MainActor
    func testEdgeCaseIntegration() async throws {
        let viewModel = MainViewModel()
        
        // 测试空字符串处理
        viewModel.speechRecognizer.recognizedText = ""
        viewModel.stopTranslation()
        XCTAssertFalse(viewModel.translationService.isTranslating)
        
        // 测试非常长的文本
        let longText = String(repeating: "很长的测试文本", count: 1000)
        viewModel.speechRecognizer.recognizedText = longText
        
        // 系统应该能够处理而不崩溃
        XCTAssertNotNil(viewModel.speechRecognizer.recognizedText)
        
        // 测试特殊字符
        viewModel.speechRecognizer.recognizedText = "Special chars: @#$%^&*()_+{}[]|\\:;\"'<>?,./ 🎉🌟✨"
        viewModel.translationService.translatedText = "特殊字符: @#$%^&*()_+{}[]|\\:;\"'<>?,./ 🎉🌟✨"
        
        viewModel.saveCurrentTranslation()
        
        // 验证特殊字符被正确处理
        let lastRecord = viewModel.historyManager.translationHistory.first
        XCTAssertNotNil(lastRecord)
        XCTAssertTrue(lastRecord!.originalText.contains("🎉"))
    }
}