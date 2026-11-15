//
//  HistoryManagerTests.swift
//  VoiceTranslationTests
//
//  Created by Testing Suite on 2025-08-11.
//

import XCTest
import Combine
@testable import VoiceTranslation

final class HistoryManagerTests: XCTestCase {
    
    var historyManager: HistoryManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUpWithError() throws {
        // 清理测试数据
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: "Translation_History")
        
        historyManager = HistoryManager()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDownWithError() throws {
        // 清理测试数据
        historyManager.clearAllHistory()
        historyManager = nil
        cancellables = nil
        
        UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName)!.removeObject(forKey: "Translation_History")
    }
    
    // MARK: - 初始化测试
    
    func testHistoryManagerInitialization() throws {
        XCTAssertNotNil(historyManager)
        XCTAssertEqual(historyManager.translationHistory.count, 0)
        XCTAssertEqual(historyManager.filteredHistory.count, 0)
        XCTAssertEqual(historyManager.searchText, "")
        XCTAssertNil(historyManager.selectedDirection)
    }
    
    // MARK: - 翻译记录保存测试
    
    func testSaveTranslationRecord() throws {
        let record = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        historyManager.saveTranslation(record)
        
        XCTAssertEqual(historyManager.translationHistory.count, 1)
        XCTAssertEqual(historyManager.filteredHistory.count, 1)
        XCTAssertEqual(historyManager.translationHistory.first?.originalText, "Hello")
        XCTAssertEqual(historyManager.translationHistory.first?.translatedText, "你好")
    }
    
    func testSaveMultipleRecords() throws {
        let record1 = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        let record2 = TranslationRecord(
            originalText: "Good morning",
            translatedText: "早上好",
            direction: .englishToChinese
        )
        
        historyManager.saveTranslation(record1)
        historyManager.saveTranslation(record2)
        
        XCTAssertEqual(historyManager.translationHistory.count, 2)
        // 新记录应该在前面
        XCTAssertEqual(historyManager.translationHistory.first?.originalText, "Good morning")
        XCTAssertEqual(historyManager.translationHistory.last?.originalText, "Hello")
    }
    
    func testAvoidDuplicateRecords() throws {
        let record1 = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        let record2 = TranslationRecord(
            originalText: "Hello", // 相同的原文
            translatedText: "你好", // 相同的译文
            direction: .englishToChinese
        )
        
        historyManager.saveTranslation(record1)
        historyManager.saveTranslation(record2)
        
        // 应该只有一个记录
        XCTAssertEqual(historyManager.translationHistory.count, 1)
    }
    
    func testHistoryLimit() throws {
        // 添加超过100个记录
        for i in 1...110 {
            let record = TranslationRecord(
                originalText: "Text \(i)",
                translatedText: "文本 \(i)",
                direction: .englishToChinese
            )
            historyManager.saveTranslation(record)
        }
        
        // 应该只保留100个记录
        XCTAssertEqual(historyManager.translationHistory.count, 100)
        
        // 最新的记录应该在前面
        XCTAssertEqual(historyManager.translationHistory.first?.originalText, "Text 110")
        XCTAssertEqual(historyManager.translationHistory.last?.originalText, "Text 11")
    }
    
    // MARK: - 记录删除测试
    
    func testDeleteSingleRecord() throws {
        let record = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        historyManager.saveTranslation(record)
        XCTAssertEqual(historyManager.translationHistory.count, 1)
        
        historyManager.deleteRecord(record)
        XCTAssertEqual(historyManager.translationHistory.count, 0)
        XCTAssertEqual(historyManager.filteredHistory.count, 0)
    }
    
    func testDeleteMultipleRecords() throws {
        let records = [
            TranslationRecord(originalText: "Hello", translatedText: "你好", direction: .englishToChinese),
            TranslationRecord(originalText: "Good", translatedText: "好", direction: .englishToChinese),
            TranslationRecord(originalText: "Bad", translatedText: "坏", direction: .englishToChinese)
        ]
        
        records.forEach { historyManager.saveTranslation($0) }
        XCTAssertEqual(historyManager.translationHistory.count, 3)
        
        // 删除第1个和第3个记录 (索引 0 和 2)
        let indexSet = IndexSet([0, 2])
        historyManager.deleteRecords(at: indexSet)
        
        XCTAssertEqual(historyManager.translationHistory.count, 1)
        XCTAssertEqual(historyManager.translationHistory.first?.originalText, "Good")
    }
    
    func testClearAllHistory() throws {
        let records = [
            TranslationRecord(originalText: "Hello", translatedText: "你好", direction: .englishToChinese),
            TranslationRecord(originalText: "Good", translatedText: "好", direction: .englishToChinese)
        ]
        
        records.forEach { historyManager.saveTranslation($0) }
        XCTAssertEqual(historyManager.translationHistory.count, 2)
        
        historyManager.clearAllHistory()
        
        XCTAssertEqual(historyManager.translationHistory.count, 0)
        XCTAssertEqual(historyManager.filteredHistory.count, 0)
    }
    
    // MARK: - 搜索和过滤测试
    
    func testSearchFiltering() throws {
        let records = [
            TranslationRecord(originalText: "Hello world", translatedText: "你好世界", direction: .englishToChinese),
            TranslationRecord(originalText: "Good morning", translatedText: "早上好", direction: .englishToChinese),
            TranslationRecord(originalText: "今天天气", translatedText: "Today's weather", direction: .chineseToEnglish)
        ]
        
        records.forEach { historyManager.saveTranslation($0) }
        
        // 搜索英文原文
        historyManager.searchText = "hello"
        XCTAssertEqual(historyManager.filteredHistory.count, 1)
        XCTAssertEqual(historyManager.filteredHistory.first?.originalText, "Hello world")
        
        // 搜索中文译文
        historyManager.searchText = "世界"
        XCTAssertEqual(historyManager.filteredHistory.count, 1)
        XCTAssertEqual(historyManager.filteredHistory.first?.translatedText, "你好世界")
        
        // 搜索不存在的内容
        historyManager.searchText = "xyz"
        XCTAssertEqual(historyManager.filteredHistory.count, 0)
        
        // 清空搜索
        historyManager.searchText = ""
        XCTAssertEqual(historyManager.filteredHistory.count, 3)
    }
    
    func testDirectionFiltering() throws {
        let records = [
            TranslationRecord(originalText: "Hello", translatedText: "你好", direction: .englishToChinese),
            TranslationRecord(originalText: "你好", translatedText: "Hello", direction: .chineseToEnglish),
            TranslationRecord(originalText: "Good", translatedText: "好", direction: .englishToChinese)
        ]
        
        records.forEach { historyManager.saveTranslation($0) }
        
        // 按英译中过滤
        historyManager.selectedDirection = .englishToChinese
        XCTAssertEqual(historyManager.filteredHistory.count, 2)
        
        // 按中译英过滤
        historyManager.selectedDirection = .chineseToEnglish
        XCTAssertEqual(historyManager.filteredHistory.count, 1)
        
        // 清除过滤
        historyManager.selectedDirection = nil
        XCTAssertEqual(historyManager.filteredHistory.count, 3)
    }
    
    func testCombinedFiltering() throws {
        let records = [
            TranslationRecord(originalText: "Hello world", translatedText: "你好世界", direction: .englishToChinese),
            TranslationRecord(originalText: "Hello", translatedText: "你好", direction: .chineseToEnglish),
            TranslationRecord(originalText: "Good world", translatedText: "好世界", direction: .englishToChinese)
        ]
        
        records.forEach { historyManager.saveTranslation($0) }
        
        // 组合搜索：搜索"hello"且方向为英译中
        historyManager.searchText = "hello"
        historyManager.selectedDirection = .englishToChinese
        
        XCTAssertEqual(historyManager.filteredHistory.count, 1)
        XCTAssertEqual(historyManager.filteredHistory.first?.originalText, "Hello world")
    }
    
    // MARK: - 持久化存储测试
    
    func testPersistenceToUserDefaults() throws {
        let record = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        historyManager.saveTranslation(record)
        
        // 创建新的HistoryManager实例来测试数据是否被持久化
        let newHistoryManager = HistoryManager()
        
        XCTAssertEqual(newHistoryManager.translationHistory.count, 1)
        XCTAssertEqual(newHistoryManager.translationHistory.first?.originalText, "Hello")
    }
    
    func testPersistenceAfterDeletion() throws {
        let record = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        historyManager.saveTranslation(record)
        historyManager.deleteRecord(record)
        
        // 创建新实例验证删除操作被持久化
        let newHistoryManager = HistoryManager()
        XCTAssertEqual(newHistoryManager.translationHistory.count, 0)
    }
    
    // MARK: - 导出功能测试
    
    func testExportHistory() throws {
        let record = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese
        )
        
        historyManager.saveTranslation(record)
        
        let exportedText = historyManager.exportHistory()
        
        XCTAssertTrue(exportedText.contains("语音翻译历史记录"))
        XCTAssertTrue(exportedText.contains("记录数量: 1"))
        XCTAssertTrue(exportedText.contains("Hello"))
        XCTAssertTrue(exportedText.contains("你好"))
        XCTAssertTrue(exportedText.contains("English → 中文"))
    }
    
    func testExportEmptyHistory() throws {
        let exportedText = historyManager.exportHistory()
        
        XCTAssertTrue(exportedText.contains("记录数量: 0"))
    }
    
    // MARK: - 统计数据测试
    
    func testStatistics() throws {
        let records = [
            TranslationRecord(originalText: "Hello", translatedText: "你好", direction: .englishToChinese),
            TranslationRecord(originalText: "你好", translatedText: "Hello", direction: .chineseToEnglish),
            TranslationRecord(originalText: "Good", translatedText: "好", direction: .englishToChinese),
            TranslationRecord(originalText: "谢谢", translatedText: "Thank you", direction: .chineseToEnglish)
        ]
        
        records.forEach { historyManager.saveTranslation($0) }
        
        XCTAssertEqual(historyManager.totalTranslations, 4)
        XCTAssertEqual(historyManager.englishToChineseCount, 2)
        XCTAssertEqual(historyManager.chineseToEnglishCount, 2)
        
        let recentTranslations = historyManager.recentTranslations
        XCTAssertEqual(recentTranslations.count, 4) // 少于5个，返回全部
        XCTAssertEqual(recentTranslations.first?.originalText, "谢谢") // 最新的在前面
    }
    
    func testTodaysTranslations() throws {
        // 今天的记录
        let todayRecord = TranslationRecord(
            originalText: "Hello",
            translatedText: "你好",
            direction: .englishToChinese,
            timestamp: Date()
        )
        
        // 昨天的记录
        let yesterdayRecord = TranslationRecord(
            originalText: "Good",
            translatedText: "好",
            direction: .englishToChinese,
            timestamp: Date().addingTimeInterval(-24 * 60 * 60)
        )
        
        historyManager.saveTranslation(todayRecord)
        historyManager.saveTranslation(yesterdayRecord)
        
        XCTAssertEqual(historyManager.todaysTranslations, 1)
    }
    
    // MARK: - 边界条件测试
    
    func testEmptyTextHandling() throws {
        let record = TranslationRecord(
            originalText: "",
            translatedText: "",
            direction: .englishToChinese
        )
        
        historyManager.saveTranslation(record)
        XCTAssertEqual(historyManager.translationHistory.count, 1)
    }
    
    func testVeryLongTextHandling() throws {
        let longText = String(repeating: "很长的文本", count: 1000)
        let record = TranslationRecord(
            originalText: longText,
            translatedText: longText,
            direction: .chineseToEnglish
        )
        
        historyManager.saveTranslation(record)
        XCTAssertEqual(historyManager.translationHistory.count, 1)
        
        let preview = historyManager.translationHistory.first?.preview
        XCTAssertNotNil(preview)
        XCTAssertTrue(preview!.count <= 53) // 50 + "..."
    }
    
    // MARK: - 内存管理测试
    
    func testMemoryManagement() throws {
        weak var weakHistoryManager: HistoryManager?
        
        autoreleasepool {
            let manager = HistoryManager()
            weakHistoryManager = manager
            
            let record = TranslationRecord(
                originalText: "Test",
                translatedText: "测试",
                direction: .englishToChinese
            )
            manager.saveTranslation(record)
        }
        
        XCTAssertNil(weakHistoryManager, "HistoryManager should be deallocated")
    }
}