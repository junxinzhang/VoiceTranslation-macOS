//
//  TestUtilities.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-11.
//

import XCTest
import Combine
@testable import VoiceTranslation

/// 测试工具类，提供常用的测试辅助功能
final class TestUtilities {
    
    // MARK: - 测试数据生成
    
    /// 生成测试用的TranslationRecord
    static func createTestRecord(
        originalText: String = "Test text",
        translatedText: String = "测试文本",
        direction: LanguageDirection = .englishToChinese,
        timestamp: Date = Date()
    ) -> TranslationRecord {
        return TranslationRecord(
            originalText: originalText,
            translatedText: translatedText,
            direction: direction,
            timestamp: timestamp
        )
    }
    
    /// 生成多个测试记录
    static func createTestRecords(count: Int) -> [TranslationRecord] {
        return (0..<count).map { index in
            createTestRecord(
                originalText: "Test text \(index)",
                translatedText: "测试文本 \(index)",
                direction: index % 2 == 0 ? .englishToChinese : .chineseToEnglish,
                timestamp: Date().addingTimeInterval(-Double(index) * 60)
            )
        }
    }
    
    /// 创建有效的测试API密钥
    static func createValidTestApiKey() -> String {
        return "sk-test1234567890abcdef1234567890abcdef"
    }
    
    /// 创建无效的测试API密钥
    static func createInvalidTestApiKey() -> String {
        return "invalid-api-key"
    }
    
    /// 创建测试用的AppSettings
    static func createTestSettings() -> AppSettings {
        let settings = AppSettings()
        settings.openAIApiKey = createValidTestApiKey()
        settings.selectedLanguageDirection = .englishToChinese
        settings.keepHistory = true
        settings.maxHistoryItems = 50
        settings.audioInputSource = .microphone
        return settings
    }
    
    // MARK: - UserDefaults 测试工具
    
    /// 清理测试相关的UserDefaults数据
    static func cleanupTestUserDefaults() {
        let keys = [
            Constants.UserDefaults.openAIApiKey,
            Constants.UserDefaults.selectedLanguageDirection,
            Constants.UserDefaults.keepHistory,
            Constants.UserDefaults.maxHistoryItems,
            "Translation_History",
            "Auto_Detect_Language",
            "Show_Translation_Animation"
        ]
        
        for key in keys {
            UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: key)
        }
    }
    
    /// 设置测试用的UserDefaults数据
    static func setupTestUserDefaults() {
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set(createValidTestApiKey(), forKey: Constants.UserDefaults.openAIApiKey)
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set(LanguageDirection.englishToChinese.rawValue, forKey: Constants.UserDefaults.selectedLanguageDirection)
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set(true, forKey: Constants.UserDefaults.keepHistory)
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.set(100, forKey: Constants.UserDefaults.maxHistoryItems)
    }
    
    // MARK: - 异步测试工具
    
    /// 等待异步操作完成的工具方法
    static func waitForAsyncOperation(
        timeout: TimeInterval = 2.0,
        operation: @escaping () -> Void,
        condition: @escaping () -> Bool
    ) async throws {
        operation()
        
        let startTime = Date()
        while !condition() && Date().timeIntervalSince(startTime) < timeout {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        if !condition() {
            throw TestError.asyncOperationTimeout
        }
    }
    
    /// 等待Published属性变化
    static func waitForPublisherChange<T: Equatable>(
        publisher: Published<T>.Publisher,
        expectedValue: T,
        timeout: TimeInterval = 2.0
    ) async throws {
        let expectation = XCTestExpectation(description: "Publisher change")
        var cancellable: AnyCancellable?
        
        cancellable = publisher
            .sink { value in
                if value == expectedValue {
                    expectation.fulfill()
                }
            }
        
        defer { cancellable?.cancel() }
        
        let result = await XCTWaiter().fulfillment(of: [expectation], timeout: timeout)
        
        if result != .completed {
            throw TestError.publisherTimeout
        }
    }
    
    // MARK: - Mock 数据工具
    
    /// 生成模拟的OpenAI API响应数据
    static func createMockOpenAIResponse(content: String) -> Data? {
        let response = """
        data: {"choices":[{"delta":{"content":"\(content)"}}]}
        
        data: [DONE]
        """
        return response.data(using: .utf8)
    }
    
    /// 生成错误的OpenAI API响应
    static func createMockErrorResponse(statusCode: Int, message: String) -> (Data?, HTTPURLResponse?) {
        let errorData = """
        {"error": {"message": "\(message)", "type": "invalid_request_error"}}
        """.data(using: .utf8)
        
        let response = HTTPURLResponse(
            url: URL(string: Constants.OpenAI.baseURL)!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        return (errorData, response)
    }
    
    // MARK: - 性能测试工具
    
    /// 测量操作执行时间
    static func measureExecutionTime<T>(operation: () throws -> T) rethrows -> (result: T, timeInterval: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        return (result, timeElapsed)
    }
    
    /// 测量异步操作执行时间
    static func measureAsyncExecutionTime<T>(operation: () async throws -> T) async rethrows -> (result: T, timeInterval: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        return (result, timeElapsed)
    }
    
    // MARK: - 内存测试工具
    
    /// 检查对象是否被正确释放
    static func checkMemoryLeak<T: AnyObject>(
        objectCreation: () -> T,
        operations: (T) -> Void = { _ in }
    ) -> Bool {
        weak var weakObject: T?
        
        autoreleasepool {
            let object = objectCreation()
            weakObject = object
            operations(object)
        }
        
        return weakObject == nil
    }
    
    /// 检查异步操作中的内存泄漏
    static func checkAsyncMemoryLeak<T: AnyObject>(
        objectCreation: () -> T,
        asyncOperations: @escaping (T) async -> Void
    ) async -> Bool {
        weak var weakObject: T?
        
        await withCheckedContinuation { continuation in
            Task {
                autoreleasepool {
                    let object = objectCreation()
                    weakObject = object
                    
                    Task {
                        await asyncOperations(object)
                        continuation.resume()
                    }
                }
            }
        }
        
        return weakObject == nil
    }
    
    // MARK: - 文本处理工具
    
    /// 生成指定长度的测试文本
    static func generateTestText(length: Int, pattern: String = "测试文本") -> String {
        let repeatCount = max(1, length / pattern.count)
        let result = String(repeating: pattern, count: repeatCount)
        return String(result.prefix(length))
    }
    
    /// 生成包含特殊字符的测试文本
    static func generateSpecialCharacterText() -> String {
        return "Special: @#$%^&*()_+-={}[]|\\:;\"'<>?,./ 🎉🌟✨🚀💎🔥⭐️🌈"
    }
    
    /// 生成包含多种语言的混合文本
    static func generateMixedLanguageText() -> String {
        return "Hello 你好 こんにちは 안녕하세요 Bonjour Hola Guten Tag مرحبا Привет"
    }
    
    // MARK: - 网络测试工具
    
    /// 模拟网络延迟
    static func simulateNetworkDelay(_ duration: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
    
    /// 创建测试用的URL请求
    static func createTestURLRequest(
        url: String = Constants.OpenAI.baseURL,
        method: String = "POST",
        headers: [String: String] = ["Content-Type": "application/json"]
    ) -> URLRequest? {
        guard let requestURL = URL(string: url) else { return nil }
        
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        return request
    }
    
    // MARK: - 验证工具
    
    /// 验证翻译记录的完整性
    static func validateTranslationRecord(_ record: TranslationRecord) -> Bool {
        return !record.originalText.isEmpty &&
               !record.translatedText.isEmpty &&
               !record.id.uuidString.isEmpty &&
               !record.sourceLanguage.isEmpty &&
               !record.targetLanguage.isEmpty
    }
    
    /// 验证API密钥格式
    static func validateApiKeyFormat(_ apiKey: String) -> Bool {
        return apiKey.hasPrefix("sk-") && apiKey.count > 10
    }
    
    /// 验证翻译方向配置
    static func validateLanguageDirection(_ direction: LanguageDirection) -> Bool {
        return !direction.displayName.isEmpty &&
               !direction.sourceLanguage.isEmpty &&
               !direction.targetLanguage.isEmpty &&
               !direction.speechLocale.isEmpty &&
               !direction.prompt.isEmpty
    }
}

// MARK: - 测试错误定义

enum TestError: Error, LocalizedError {
    case asyncOperationTimeout
    case publisherTimeout
    case invalidTestData
    case mockSetupFailed
    
    var errorDescription: String? {
        switch self {
        case .asyncOperationTimeout:
            return "异步操作超时"
        case .publisherTimeout:
            return "Publisher变化等待超时"
        case .invalidTestData:
            return "无效的测试数据"
        case .mockSetupFailed:
            return "Mock设置失败"
        }
    }
}

// MARK: - 测试配置

struct TestConfiguration {
    static let defaultTimeout: TimeInterval = 5.0
    static let networkTimeout: TimeInterval = 10.0
    static let shortTimeout: TimeInterval = 1.0
    
    static let maxHistoryItems = 100
    static let testApiKey = "sk-test1234567890abcdef1234567890abcdef"
    static let invalidApiKey = "invalid-key"
    
    static let sampleTexts = [
        "Hello, how are you?",
        "你好，你好吗？",
        "Good morning, have a great day!",
        "早上好，祝你有美好的一天！",
        "Thank you for your help.",
        "谢谢你的帮助。"
    ]
}

// MARK: - 测试断言扩展

extension XCTestCase {
    
    /// 断言异步操作在指定时间内完成
    func XCTAssertAsyncCompletion<T>(
        _ expression: @autoclosure () async throws -> T,
        timeout: TimeInterval = TestConfiguration.defaultTimeout,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail("异步操作失败: \(error.localizedDescription), \(message())", file: file, line: line)
        }
    }
    
    /// 断言Published属性在指定时间内发生变化
    func XCTAssertPublisherChange<T: Equatable>(
        _ publisher: Published<T>.Publisher,
        expectedValue: T,
        timeout: TimeInterval = TestConfiguration.defaultTimeout,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await TestUtilities.waitForPublisherChange(
                publisher: publisher,
                expectedValue: expectedValue,
                timeout: timeout
            )
        } catch {
            XCTFail("Publisher未在指定时间内变化为期望值, \(message())", file: file, line: line)
        }
    }
    
    /// 断言对象没有内存泄漏
    func XCTAssertNoMemoryLeak<T: AnyObject>(
        _ objectCreation: () -> T,
        operations: (T) -> Void = { _ in },
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let hasLeak = !TestUtilities.checkMemoryLeak(
            objectCreation: objectCreation,
            operations: operations
        )
        
        if hasLeak {
            XCTFail("检测到内存泄漏, \(message())", file: file, line: line)
        }
    }
}