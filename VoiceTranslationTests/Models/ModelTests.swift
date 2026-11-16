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

final class TranslationIntegrityTests: XCTestCase {
    func testEquivalentExplicitFactsInBothLanguages() {
        let pairs = [
            ("The budget is three thousand five hundred US dollars.", "预算是3500美元。"),
            ("We need forty-two boxes, not forty-two dollars.", "我们需要42个盒子，不是42美元。"),
            ("we need 42 boxes not $42", "我们需要42个盒子，而不是42美元。"),
            ("It costs $42 per box.", "每个盒子的价格是42美元。"),
            ("The meeting is on March fifteenth, twenty twenty-seven, at nine thirty.", "会议在2027年3月15日9点30分举行。"),
            ("The temperature is minus five degrees Celsius and the distance is two point five kilometers.", "温度是零下5摄氏度，距离是2.5公里。"),
            ("The quantity is fifteen. Sorry, I mean fifty.", "数量是50。"),
            ("The quantity is fifteen. Sorry, I mean fifty.", "数量是15，对不起，我是说50。"),
            ("The budget is five thousand. I have not specified the currency.", "预算是5000。我没有说明币种。"),
            ("The budget is $3,500.50.", "预算是3500.50美元。"),
            ("增长了百分之五。", "It increased by five percent."),
            ("会议在2027年3月15日九点半举行。", "The meeting is on March 15, 2027 at 9:30."),
            ("需要3.5万人民币。", "We need 35000 yuan."),
            ("你好，我们一起讨论这个问题。", "Hello, let us discuss this together."),
            ("This is a test.", "这是一个测试。"),
            ("No one has replied.", "没有人回复。")
        ]
        for (a, b) in pairs { XCTAssertTrue(TranslationIntegrity.warnings(source: a, translation: b).isEmpty, "Rejected equivalent facts: \(a) -> \(b): \(TranslationIntegrity.warnings(source: a, translation: b))") }
    }

    func testChangedOrInventedFactsAreHeldForReview() {
        let pairs = [
            ("The budget is five thousand.", "预算是5000美元。"),
            ("The meeting starts at", "会议九点开始。"),
            ("We need 42 boxes.", "我们需要42美元。"),
            ("The budget is 3500 US dollars.", "预算是5300美元。"),
            ("The temperature is minus five degrees Celsius.", "温度是5摄氏度。"),
            ("The distance is 2.5 kilometers.", "距离是2.5米。"),
            ("The rate is 0.5 percent.", "比例是5%。"),
            ("The code is 00123.", "编号是123。"),
            ("The meeting is on March 15, 2027.", "会议在2027年5月13日。"),
            ("The budget is $3500 and we need 15 boxes. Sorry, I mean 50 boxes.", "我们需要50个盒子。")
        ]
        for (a, b) in pairs { XCTAssertFalse(TranslationIntegrity.warnings(source: a, translation: b).isEmpty, "Accepted changed facts: \(a) -> \(b)") }
    }

    func testReferenceDoesNotLicenseInventingNames() {
        let terms = [GlossaryTerm(english: "Jensen Huang", chinese: "黄仁勋")]
        XCTAssertFalse(TranslationIntegrity.warnings(source: "He will join.", translation: "黄仁勋会加入。", terms: terms).isEmpty)
        XCTAssertTrue(TranslationIntegrity.warnings(source: "Jensen Huang will join.", translation: "黄仁勋会加入。", terms: terms).isEmpty)
    }
}

extension TranslationIntegrityTests {
    func testListsCannotAcquireActionsAndTermsCannotBeOmitted() {
        let terms = [GlossaryTerm(english: "Jensen Huang", chinese: "黄仁勋"), GlossaryTerm(english: "Fei-Fei Li", chinese: "李飞飞"), GlossaryTerm(english: "Project Aurora", chinese: "晨光计划")]
        let source = "Jensen Huang and Fei Fei Li Project Aurora"
        XCTAssertTrue(TranslationIntegrity.warnings(source: source, translation: "黄仁勋、李飞飞、晨光计划。", terms: terms).isEmpty)
        XCTAssertFalse(TranslationIntegrity.warnings(source: source, translation: "黄仁勋和李飞飞携手推进晨光计划。", terms: terms).isEmpty)
        XCTAssertFalse(TranslationIntegrity.warnings(source: "Jensen Huang will review Project Aurora.", translation: "黄仁勋会审查该项目。", terms: terms).isEmpty)
        XCTAssertTrue(TranslationIntegrity.warnings(source: "public policy", translation: "public policy", terms: [.init(english: "Li", chinese: "Li")]).isEmpty)
    }
    func testOrdinaryPhrasesAndAttachedUnitsDoNotCauseFalseAlarms() {
        for (a,b) in [("Oh, I am tired.", "哦，我累了。"), ("First, let us discuss the plan.", "首先，我们讨论计划。"), ("Please send a blue box.", "请发一个蓝色盒子。"), ("We need 15kg.", "我们需要15千克。"), ("It takes one hour.", "需要一小时。"), ("The temperature is minus 5 degrees Celsius.", "温度为零下5摄氏度。"), ("We use GPT-4o.", "我们使用GPT-4o。") ] {
            XCTAssertTrue(TranslationIntegrity.warnings(source: a, translation: b).isEmpty, "\(a) / \(b)")
        }
        XCTAssertFalse(TranslationIntegrity.warnings(source: "It takes one hour.", translation: "需要一分钟。").isEmpty)
        XCTAssertFalse(TranslationIntegrity.warnings(source: "We need 15kg.", translation: "我们需要15克。").isEmpty)
        XCTAssertFalse(TranslationIntegrity.warnings(source: "The budget is $42 and the quantity is 42.", translation: "预算是42美元，数量是42美元。").isEmpty)
        XCTAssertFalse(TranslationIntegrity.warnings(source: "The meeting starts at 9:30.", translation: "会议上午9点30分开始。").isEmpty)
    }
    func testCorrectionMemoryIsNarrowAndNeverCreatesNumericRules() {
        let memory = RecognitionCorrection.proposal(before: "Jensen Hwang will join.", after: "Jensen Huang will join.", language: "en-US")
        XCTAssertEqual(memory?.heard, "Jensen Hwang")
        XCTAssertEqual(memory?.preferred, "Jensen Huang")
        XCTAssertEqual(memory?.suggestion(for: "Jensen Hwang is here.", language: "en-US"), "Jensen Huang is here.")
        XCTAssertNil(memory?.suggestion(for: "Jensen Hwangson is here.", language: "en-US"))
        XCTAssertNil(memory?.suggestion(for: "Jensen Hwang is here.", language: "zh-CN"))
        XCTAssertNil(RecognitionCorrection.proposal(before: "The quantity is 15.", after: "The quantity is 50.", language: "en-US"))
        XCTAssertNil(RecognitionCorrection.proposal(before: "We need 15kg.", after: "We need 50kg.", language: "en-US"))
        XCTAssertNil(RecognitionCorrection.proposal(before: "We need boxes.", after: "We need dollars.", language: "en-US"))
        let chinese = RecognitionCorrection.proposal(before: "请黄仁村参加会议", after: "请黄仁勋参加会议", language: "zh-CN")
        XCTAssertEqual(chinese?.heard, "黄仁村")
        XCTAssertEqual(chinese?.preferred, "黄仁勋")
    }
}

extension TranslationIntegrityTests {
    func testPreferredLatinTermsCanTouchChineseProseButNotLatinWords() {
        let terms = [GlossaryTerm(english: "Kubernetes", chinese: "Kubernetes")]
        XCTAssertTrue(TranslationIntegrity.warnings(source: "we discussed Kubernetes today", translation: "今天我们讨论了Kubernetes。", terms: terms).isEmpty)
        XCTAssertFalse(TranslationIntegrity.warnings(source: "we discussed Kubernetes today", translation: "今天讨论了MicroKubernetesX。", terms: terms).isEmpty)
        XCTAssertFalse(TranslationIntegrity.warnings(source: "we discussed software today", translation: "今天我们讨论了Kubernetes。", terms: terms).isEmpty)
    }
    func testExplicitSymbolsAndUserDefinedAliasesDoNotLookLikeInventedNames() {
        let terms = [GlossaryTerm(english: "USD", chinese: "美元"), GlossaryTerm(english: "kilogram", chinese: "公斤"), GlossaryTerm(english: "AI", chinese: "人工智能"), GlossaryTerm(english: "artificial intelligence", chinese: "人工智能")]
        XCTAssertTrue(TranslationIntegrity.warnings(source: "The budget is $3500.", translation: "预算是3500美元。", terms: terms).isEmpty)
        XCTAssertTrue(TranslationIntegrity.warnings(source: "We need 15kg.", translation: "我们需要15公斤。", terms: terms).isEmpty)
        XCTAssertTrue(TranslationIntegrity.warnings(source: "We use artificial intelligence.", translation: "我们使用人工智能。", terms: terms).isEmpty)
        XCTAssertFalse(TranslationIntegrity.warnings(source: "The budget is 3500.", translation: "预算是3500美元。", terms: terms).isEmpty)
    }
}
