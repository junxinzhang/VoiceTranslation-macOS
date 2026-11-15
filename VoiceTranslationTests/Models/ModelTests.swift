//
//  ModelTests.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-11.
//

import XCTest
@testable import VoiceTranslation

final class ModelTests: XCTestCase {
    
    override func setUpWithError() throws {
        clearTestDefaults()
    }
    
    override func tearDownWithError() throws {
        clearTestDefaults()
    }

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
            "simultaneousThreshold"
        ]
        let suites = [UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)]

        for defaults in suites.compactMap({ $0 }) {
            keys.forEach { defaults.removeObject(forKey: $0) }
            defaults.synchronize()
        }
    }
    
    // MARK: - LanguageDirection Tests
    
    func testLanguageDirectionProperties() throws {
        // 测试英译中
        let enToCn = LanguageDirection.englishToChinese
        XCTAssertEqual(enToCn.displayName, "English → 中文")
        XCTAssertEqual(enToCn.sourceLanguage, "英文")
        XCTAssertEqual(enToCn.targetLanguage, "中文")
        XCTAssertEqual(enToCn.speechLocale, "en-US")
        XCTAssertEqual(enToCn.icon, "🇺🇸 → 🇨🇳")
        XCTAssertEqual(enToCn.rawValue, "en-zh")
        
        // 测试中译英
        let cnToEn = LanguageDirection.chineseToEnglish
        XCTAssertEqual(cnToEn.displayName, "中文 → English")
        XCTAssertEqual(cnToEn.sourceLanguage, "中文")
        XCTAssertEqual(cnToEn.targetLanguage, "英文")
        XCTAssertEqual(cnToEn.speechLocale, "zh-CN")
        XCTAssertEqual(cnToEn.icon, "🇨🇳 → 🇺🇸")
        XCTAssertEqual(cnToEn.rawValue, "zh-en")
    }
    
    func testLanguageDirectionPrompts() throws {
        let enToCn = LanguageDirection.englishToChinese
        XCTAssertTrue(enToCn.prompt.contains("英中翻译助手"))
        XCTAssertTrue(enToCn.prompt.contains("英文"))
        XCTAssertTrue(enToCn.prompt.contains("中文"))
        
        let cnToEn = LanguageDirection.chineseToEnglish
        XCTAssertTrue(cnToEn.prompt.contains("Chinese-English translation"))
        XCTAssertTrue(cnToEn.prompt.contains("Chinese"))
        XCTAssertTrue(cnToEn.prompt.contains("English"))
    }
    
    func testLanguageDirectionCaseIterable() throws {
        let allCases = LanguageDirection.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.englishToChinese))
        XCTAssertTrue(allCases.contains(.chineseToEnglish))
    }
    
    func testLanguageDirectionCodable() throws {
        let original = LanguageDirection.englishToChinese
        
        // 编码
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // 解码
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LanguageDirection.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
    
    // MARK: - TranslationRecord Tests
    
    func testTranslationRecordInitialization() throws {
        let record = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        XCTAssertNotNil(record.id)
        XCTAssertEqual(record.originalText, "Hello")
        XCTAssertEqual(record.translatedText, "你好")
        XCTAssertEqual(record.direction, .englishToChinese)
        XCTAssertEqual(record.sourceLanguage, "英文")
        XCTAssertEqual(record.targetLanguage, "中文")
        XCTAssertNotNil(record.timestamp)
    }
    
    func testTranslationRecordWithCustomTimestamp() throws {
        let customDate = Date(timeIntervalSince1970: 1640995200) // 2022-01-01
        let record = TranslationRecord(
            originalText: "Test",
            translatedText: "测试",
            direction: .chineseToEnglish,
            timestamp: customDate
        )
        
        XCTAssertEqual(record.timestamp, customDate)
    }
    
    func testTranslationRecordFormattedTimestamp() throws {
        let record = TranslationRecord(
            originalText: "Test",
            translatedText: "测试",
            direction: .englishToChinese
        )
        
        let formattedTimestamp = record.formattedTimestamp
        XCTAssertFalse(formattedTimestamp.isEmpty)
        // 格式化的时间戳应该包含日期和时间信息
        XCTAssertTrue(formattedTimestamp.contains("/") || formattedTimestamp.contains("-"))
    }
    
    func testTranslationRecordIsRecent() throws {
        // 最近的记录
        let recentRecord = TranslationRecord(
            originalText: "Recent",
            translatedText: "最近的",
            direction: .englishToChinese,
            timestamp: Date()
        )
        XCTAssertTrue(recentRecord.isRecent)
        
        // 超过1小时的记录
        let oldRecord = TranslationRecord(
            originalText: "Old",
            translatedText: "旧的",
            direction: .englishToChinese,
            timestamp: Date().addingTimeInterval(-3700) // 超过1小时
        )
        XCTAssertFalse(oldRecord.isRecent)
    }
    
    func testTranslationRecordPreview() throws {
        // 短文本
        let shortRecord = TranslationRecord(
            originalText: "Short text",
            translatedText: "短文本",
            direction: .englishToChinese
        )
        XCTAssertEqual(shortRecord.preview, "Short text")
        
        // 长文本
        let longText = String(repeating: "This is a long text ", count: 10)
        let longRecord = TranslationRecord(
            originalText: longText,
            translatedText: "长文本",
            direction: .englishToChinese
        )
        XCTAssertTrue(longRecord.preview.hasSuffix("..."))
        XCTAssertTrue(longRecord.preview.count <= 53) // 50 + "..."
    }

    func testTranslationRecordSessionOriginalExport() throws {
        let timestamp = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let record = TranslationRecord(
            originalText: "Session original text",
            translatedText: "会话原文",
            direction: .englishToChinese,
            timestamp: timestamp
        )

        XCTAssertEqual(record.sessionOriginalExportText, "Session original text")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        XCTAssertEqual(record.sessionOriginalExportFilename, "Session原文_" + formatter.string(from: timestamp))
    }
    
    func testTranslationRecordEquality() throws {
        let record1 = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        let record2 = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        // 不同的记录应该有不同的ID，因此不相等
        XCTAssertNotEqual(record1, record2)
        XCTAssertEqual(record1, record1) // 与自己相等
    }
    
    func testTranslationRecordCodable() throws {
        let original = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        // 编码
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // 解码
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TranslationRecord.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.originalText, original.originalText)
        XCTAssertEqual(decoded.translatedText, original.translatedText)
        XCTAssertEqual(decoded.direction, original.direction)
    }
    
    func testTranslationRecordSampleData() throws {
        let sampleData = TranslationRecord.sampleData
        XCTAssertEqual(sampleData.count, 3)
        
        // 验证样本数据的完整性
        for record in sampleData {
            XCTAssertFalse(record.originalText.isEmpty)
            XCTAssertFalse(record.translatedText.isEmpty)
            XCTAssertNotNil(record.id)
        }
        
        // 验证包含两种翻译方向
        let directions = Set(sampleData.map { $0.direction })
        XCTAssertEqual(directions.count, 2)
        XCTAssertTrue(directions.contains(.englishToChinese))
        XCTAssertTrue(directions.contains(.chineseToEnglish))
    }
    
    // MARK: - AppSettings Tests
    
    func testAppSettingsInitialization() throws {
        let settings = AppSettings()
        
        XCTAssertEqual(settings.openAIApiKey, "")
        XCTAssertEqual(settings.customAPIKey, "")
        XCTAssertEqual(settings.apiProvider, .customAPI)
        XCTAssertEqual(settings.selectedLanguageDirection, .chineseToEnglish)
        XCTAssertTrue(settings.keepHistory)
        XCTAssertEqual(settings.maxHistoryItems, 100)
        XCTAssertFalse(settings.autoDetectLanguage)
        XCTAssertTrue(settings.showTranslationAnimation)
    }
    
    func testAppSettingsApiKeyValidation() throws {
        let settings = AppSettings()

        settings.apiProvider = .openAI

        // 无效格式的 OpenAI 密钥
        settings.openAIApiKey = "invalid-key"
        XCTAssertFalse(settings.isApiKeyValid)
        XCTAssertFalse(settings.canTranslate)
        
        // 太短的 sk- 前缀密钥
        settings.openAIApiKey = "sk-123"
        XCTAssertFalse(settings.isApiKeyValid)
        XCTAssertFalse(settings.canTranslate)
        
        // 有效的 OpenAI 密钥
        settings.openAIApiKey = "sk-1234567890abcdef"
        XCTAssertTrue(settings.isApiKeyValid)
        XCTAssertTrue(settings.canTranslate)

        // Custom API 只要求最小长度和 URL / Model 合法
        settings.apiProvider = .customAPI
        settings.customAPIKey = "short"
        XCTAssertFalse(settings.isApiKeyValid)
        XCTAssertFalse(settings.canTranslate)

        settings.customAPIKey = "custom-key-123456"
        XCTAssertTrue(settings.isApiKeyValid)
        XCTAssertTrue(settings.canTranslate)
    }

    func testAppSettingsCustomAPIConfigurationValidation() throws {
        let settings = AppSettings()

        settings.apiProvider = .customAPI
        settings.customAPIKey = "custom-key-123456"
        settings.customAPIBaseURL = "https://example.com/v1/chat/completions"
        settings.customAPIModel = "custom/model"

        XCTAssertTrue(settings.isApiKeyValid)
        XCTAssertTrue(settings.isCurrentProviderConfigurationValid)
        XCTAssertTrue(settings.canTranslate)
        XCTAssertEqual(settings.currentAPIBaseURL, "https://example.com/v1/chat/completions")
        XCTAssertEqual(settings.currentModel, "custom/model")

        settings.customAPIBaseURL = "invalid-url"
        XCTAssertFalse(settings.isCurrentProviderConfigurationValid)
        XCTAssertFalse(settings.canTranslate)

        settings.customAPIBaseURL = ""
        settings.customAPIModel = ""
        XCTAssertEqual(settings.currentAPIBaseURL, Constants.CustomAPI.defaultBaseURL)
        XCTAssertEqual(settings.currentModel, Constants.CustomAPI.defaultModel)
    }
    
    func testAppSettingsApiKeyDisplayText() throws {
        let settings = AppSettings()

        settings.apiProvider = .openAI

        // 未设置密钥时，可能回退到内置 Key
        settings.openAIApiKey = ""
        XCTAssertEqual(settings.apiKeyDisplayText, BuiltInKeys.hasOpenAIKey ? "使用内置 Key" : "未设置")
        
        // 无效密钥
        settings.openAIApiKey = "invalid"
        XCTAssertEqual(settings.apiKeyDisplayText, "无效密钥")
        
        // 有效密钥
        settings.openAIApiKey = "sk-test1234567890abcdef1234567890abcdef"
        XCTAssertEqual(settings.apiKeyDisplayText, "sk-****cdef")
    }
    
    func testAppSettingsStatusText() throws {
        let settings = AppSettings()

        settings.apiProvider = .openAI

        // 无法翻译时
        settings.openAIApiKey = "invalid"
        XCTAssertEqual(settings.statusText, "请检查 API 配置")
        
        // 可以翻译时
        settings.openAIApiKey = "sk-1234567890abcdef"
        XCTAssertEqual(settings.statusText, "准备就绪")
    }
    
    func testAppSettingsPersistence() throws {
        let settings = AppSettings()
        
        // 设置一些值
        settings.apiProvider = .openAI
        settings.openAIApiKey = "sk-test1234567890"
        settings.selectedLanguageDirection = .chineseToEnglish
        settings.keepHistory = false
        settings.maxHistoryItems = 50
        
        // 创建新实例应该加载保存的值
        let newSettings = AppSettings()
        XCTAssertEqual(newSettings.apiProvider, .openAI)
        XCTAssertEqual(newSettings.openAIApiKey, "sk-test1234567890")
        XCTAssertEqual(newSettings.selectedLanguageDirection, .chineseToEnglish)
        XCTAssertFalse(newSettings.keepHistory)
        XCTAssertEqual(newSettings.maxHistoryItems, 50)
    }

    func testAppSettingsCustomAPIPersistence() throws {
        let settings = AppSettings()

        settings.apiProvider = .customAPI
        settings.customAPIKey = "custom-key-1234567890"
        settings.customAPIBaseURL = "https://example.com/v1/chat/completions"
        settings.customAPIModel = "custom/model-v1"

        let newSettings = AppSettings()
        XCTAssertEqual(newSettings.apiProvider, .customAPI)
        XCTAssertEqual(newSettings.customAPIKey, "custom-key-1234567890")
        XCTAssertEqual(newSettings.customAPIBaseURL, "https://example.com/v1/chat/completions")
        XCTAssertEqual(newSettings.customAPIModel, "custom/model-v1")
    }
    
    func testAppSettingsResetToDefaults() throws {
        let settings = AppSettings()
        
        // 修改设置
        settings.apiProvider = .openAI
        settings.openAIApiKey = "sk-test1234567890"
        settings.selectedLanguageDirection = .chineseToEnglish
        settings.keepHistory = false
        settings.maxHistoryItems = 50
        settings.autoDetectLanguage = true
        settings.showTranslationAnimation = false
        
        // 重置为默认值
        settings.resetToDefaults()
        
        XCTAssertEqual(settings.openAIApiKey, "")
        XCTAssertEqual(settings.customAPIKey, "")
        XCTAssertEqual(settings.apiProvider, .customAPI)
        XCTAssertEqual(settings.selectedLanguageDirection, .chineseToEnglish)
        XCTAssertTrue(settings.keepHistory)
        XCTAssertEqual(settings.maxHistoryItems, 100)
        XCTAssertFalse(settings.autoDetectLanguage)
        XCTAssertTrue(settings.showTranslationAnimation)
    }
    
    func testAppSettingsClearApiKey() throws {
        let settings = AppSettings()
        
        settings.apiProvider = .openAI
        settings.openAIApiKey = "sk-test1234567890"
        XCTAssertFalse(settings.openAIApiKey.isEmpty)
        
        settings.clearApiKey()
        XCTAssertEqual(settings.openAIApiKey, "")
    }
    
    // MARK: - 边界条件测试
    
    func testTranslationRecordWithEmptyText() throws {
        let record = TranslationRecord(
            originalText: "",
            translatedText: "",
            direction: .englishToChinese
        )
        
        XCTAssertEqual(record.originalText, "")
        XCTAssertEqual(record.translatedText, "")
        XCTAssertEqual(record.preview, "")
    }
    
    func testTranslationRecordWithSpecialCharacters() throws {
        let record = TranslationRecord(
            originalText: "Hello! @#$%^&*()_+ 🌍",
            translatedText: "你好！@#$%^&*()_+ 🌍",
            direction: .englishToChinese
        )
        
        XCTAssertEqual(record.originalText, "Hello! @#$%^&*()_+ 🌍")
        XCTAssertEqual(record.translatedText, "你好！@#$%^&*()_+ 🌍")
    }
    
    func testAppSettingsWithExtremeValues() throws {
        let settings = AppSettings()
        
        // 极大的历史记录数量
        settings.maxHistoryItems = 10000
        XCTAssertEqual(settings.maxHistoryItems, 10000)
        
        // 极小的历史记录数量
        settings.maxHistoryItems = 0
        XCTAssertEqual(settings.maxHistoryItems, 0)
        
        // 负数历史记录数量
        settings.maxHistoryItems = -10
        XCTAssertEqual(settings.maxHistoryItems, -10)
    }
}
