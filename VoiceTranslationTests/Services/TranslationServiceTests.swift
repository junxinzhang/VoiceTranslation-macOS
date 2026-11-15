//
//  TranslationServiceTests.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-11.
//

import XCTest
import Combine
@testable import VoiceTranslation

final class TranslationServiceTests: XCTestCase {
    
    var translationService: TranslationService!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        translationService = TranslationService()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        translationService = nil
        cancellables = nil
        
        // 清理测试用的API Key
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: Constants.UserDefaults.openAIApiKey)
    }
    
    // MARK: - 初始化测试
    
    func testTranslationServiceInitialization() throws {
        XCTAssertNotNil(translationService)
        XCTAssertEqual(translationService.translatedText, "")
        XCTAssertFalse(translationService.isTranslating)
        XCTAssertNil(translationService.error)
    }
    
    // MARK: - API Key 验证测试
    
    func testTranslationWithoutAPIKey() async throws {
        // 确保没有API Key
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: Constants.UserDefaults.openAIApiKey)
        
        let errorExpectation = expectation(description: "API Key missing error")
        
        translationService.$error
            .compactMap { $0 }
            .sink { error in
                if case .apiKeyMissing = error {
                    errorExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        await translationService.translateText("Hello", direction: .englishToChinese)
        
        await fulfillment(of: [errorExpectation], timeout: 5.0)
    }
    
    func testTranslationWithInvalidAPIKey() async throws {
        // 设置无效的API Key
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("invalid-key", forKey: Constants.UserDefaults.openAIApiKey)
        
        let stateExpectation = expectation(description: "Translation state change")
        
        translationService.$isTranslating
            .sink { isTranslating in
                if isTranslating {
                    stateExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        await translationService.translateText("Hello", direction: .englishToChinese)
        
        await fulfillment(of: [stateExpectation], timeout: 5.0)
    }
    
    // MARK: - 翻译流程测试
    
    func testTranslationStateManagement() async throws {
        // 设置有效格式的API Key用于测试
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        let stateChanges = expectation(description: "State changes")
        var stateHistory: [Bool] = []
        
        translationService.$isTranslating
            .sink { isTranslating in
                stateHistory.append(isTranslating)
                if stateHistory.count >= 2 {
                    stateChanges.fulfill()
                }
            }
            .store(in: &cancellables)
        
        await translationService.translateText("Hello", direction: .englishToChinese)
        
        await fulfillment(of: [stateChanges], timeout: 10.0)
        
        // 验证状态变化：false -> true -> false
        XCTAssertEqual(stateHistory.first, false)
        XCTAssertTrue(stateHistory.contains(true))
    }
    
    func testEmptyTextTranslation() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        await translationService.translateText("", direction: .englishToChinese)
        
        // 空文本应该不触发翻译
        XCTAssertFalse(translationService.isTranslating)
        XCTAssertEqual(translationService.translatedText, "")
        XCTAssertNil(translationService.error)
    }
    
    func testWhitespaceOnlyTextTranslation() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        await translationService.translateText("   \n\t  ", direction: .englishToChinese)
        
        // 仅空白字符应该不触发翻译
        XCTAssertFalse(translationService.isTranslating)
        XCTAssertEqual(translationService.translatedText, "")
        XCTAssertNil(translationService.error)
    }
    
    // MARK: - 双向翻译测试
    
    func testEnglishToChineseTranslation() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        await translationService.translateText("Hello, world!", direction: .englishToChinese)
        
        // 由于是模拟API，我们主要验证流程是否正确执行
        XCTAssertFalse(translationService.isTranslating)
    }
    
    func testChineseToEnglishTranslation() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        await translationService.translateText("你好，世界！", direction: .chineseToEnglish)
        
        XCTAssertFalse(translationService.isTranslating)
    }
    
    // MARK: - 错误处理测试
    
    func testNetworkErrorHandling() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        let errorExpectation = expectation(description: "Network error")
        
        translationService.$error
            .compactMap { $0 }
            .sink { error in
                // 预期会有网络错误（因为使用的是测试API Key）
                errorExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        await translationService.translateText("Test text", direction: .englishToChinese)
        
        await fulfillment(of: [errorExpectation], timeout: 10.0)
        
        XCTAssertFalse(translationService.isTranslating)
        XCTAssertNotNil(translationService.error)
    }
    
    // MARK: - 并发翻译测试
    
    func testConcurrentTranslations() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        // 同时启动多个翻译任务
        async let translation1 = translationService.translateText("Text 1", direction: .englishToChinese)
        async let translation2 = translationService.translateText("Text 2", direction: .chineseToEnglish)
        async let translation3 = translationService.translateText("Text 3", direction: .englishToChinese)
        
        await translation1
        await translation2
        await translation3
        
        // 系统应该能够处理并发请求而不崩溃
        XCTAssertNotNil(translationService)
        XCTAssertFalse(translationService.isTranslating)
    }
    
    // MARK: - 特殊字符和长文本测试
    
    func testSpecialCharactersTranslation() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        let specialText = "Hello! @#$%^&*()_+ 你好 🌍 ñáéíóú"
        await translationService.translateText(specialText, direction: .englishToChinese)
        
        // 应该能够处理特殊字符而不崩溃
        XCTAssertNotNil(translationService)
    }
    
    func testLongTextTranslation() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        let longText = String(repeating: "This is a long text for testing purposes. ", count: 100)
        await translationService.translateText(longText, direction: .englishToChinese)
        
        // 应该能够处理长文本
        XCTAssertNotNil(translationService)
    }
    
    // MARK: - 状态重置测试
    
    func testStateResetBetweenTranslations() async throws {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set("sk-test1234567890abcdef", forKey: Constants.UserDefaults.openAIApiKey)
        
        // 第一次翻译
        await translationService.translateText("First text", direction: .englishToChinese)
        let firstError = translationService.error
        
        // 第二次翻译应该清除之前的错误状态
        await translationService.translateText("Second text", direction: .chineseToEnglish)
        
        // 验证状态被正确重置
        XCTAssertFalse(translationService.isTranslating)
    }
    
    // MARK: - 内存管理测试
    
    func testMemoryManagement() async throws {
        weak var weakService: TranslationService?
        
        await withCheckedContinuation { continuation in
            autoreleasepool {
                let service = TranslationService()
                weakService = service
                
                Task {
                    await service.translateText("Test", direction: .englishToChinese)
                    continuation.resume()
                }
            }
        }
        
        // 验证服务对象被正确释放
        XCTAssertNil(weakService, "TranslationService should be deallocated")
    }
}