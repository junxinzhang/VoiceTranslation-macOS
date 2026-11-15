//
//  LanguageDirection.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation

enum LanguageDirection: String, CaseIterable, Codable {
    case englishToChinese = "en-zh"
    case chineseToEnglish = "zh-en"
    
    var displayName: String {
        switch self {
        case .englishToChinese:
            return "English → 中文"
        case .chineseToEnglish:
            return "中文 → English"
        }
    }
    
    var sourceLanguage: String {
        switch self {
        case .englishToChinese:
            return "英文"
        case .chineseToEnglish:
            return "中文"
        }
    }
    
    var targetLanguage: String {
        switch self {
        case .englishToChinese:
            return "中文"
        case .chineseToEnglish:
            return "英文"
        }
    }
    
    var speechLocale: String {
        switch self {
        case .englishToChinese:
            return "en-US"
        case .chineseToEnglish:
            return "zh-CN"
        }
    }
    
    var prompt: String {
        switch self {
        case .englishToChinese:
            return Constants.Prompts.englishToChinese
        case .chineseToEnglish:
            return Constants.Prompts.chineseToEnglish
        }
    }
    
    var icon: String {
        switch self {
        case .englishToChinese:
            return "🇺🇸 → 🇨🇳"
        case .chineseToEnglish:
            return "🇨🇳 → 🇺🇸"
        }
    }
}