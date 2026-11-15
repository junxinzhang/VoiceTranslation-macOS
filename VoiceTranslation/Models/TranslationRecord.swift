//
//  TranslationRecord.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation

struct TranslationRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let direction: LanguageDirection
    let timestamp: Date
    
    init(originalText: String, 
         translatedText: String, 
         direction: LanguageDirection,
         timestamp: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.direction = direction
        self.sourceLanguage = direction.sourceLanguage
        self.targetLanguage = direction.targetLanguage
        self.timestamp = timestamp
    }
    
    // MARK: - Computed Properties
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: timestamp)
    }
    
    var isRecent: Bool {
        let timeInterval = Date().timeIntervalSince(timestamp)
        return timeInterval < 3600 // 1 hour
    }
    
    var preview: String {
        let maxLength = 50
        if originalText.count <= maxLength {
            return originalText
        } else {
            return String(originalText.prefix(maxLength)) + "..."
        }
    }

    var sessionOriginalExportText: String {
        originalText
    }

    var sessionOriginalExportFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "Session原文_\(formatter.string(from: timestamp))"
    }
    
    // MARK: - Static Methods
    
    static func == (lhs: TranslationRecord, rhs: TranslationRecord) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Sample Data

extension TranslationRecord {
    static let sampleData: [TranslationRecord] = [
        TranslationRecord(
            originalText: "Hello, how are you today?",
            translatedText: "你好，你今天怎么样？",
            direction: .englishToChinese,
            timestamp: Date().addingTimeInterval(-3600)
        ),
        TranslationRecord(
            originalText: "今天天气很好。",
            translatedText: "The weather is very nice today.",
            direction: .chineseToEnglish,
            timestamp: Date().addingTimeInterval(-7200)
        ),
        TranslationRecord(
            originalText: "Can you help me with this project?",
            translatedText: "你能帮助我完成这个项目吗？",
            direction: .englishToChinese,
            timestamp: Date().addingTimeInterval(-10800)
        )
    ]
}
