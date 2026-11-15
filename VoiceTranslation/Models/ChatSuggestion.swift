//
//  ChatSuggestion.swift
//  VoiceTranslation
//
//  Chat suggestion model for conversation reply recommendations.
//  Primary text is in the source language (to reply to the other party),
//  with a translated version for the user's reference.
//
//  Created on 2026-03-05.
//

import Foundation
import SwiftUI

// MARK: - Suggestion Tag

enum SuggestionTag: String, CaseIterable, Codable {
    case reply    // 回复
    case question // 提问
    case action   // 行动
    case confirm  // 确认

    var label: String {
        switch self {
        case .reply:    return "回复"
        case .question: return "提问"
        case .action:   return "行动"
        case .confirm:  return "确认"
        }
    }

    var color: Color {
        switch self {
        case .reply:    return Color(hex: "4A9EF5")  // 蓝色
        case .question: return Color(hex: "3D8A5A")  // 绿色
        case .action:   return Color(hex: "D4A64A")  // 橙色
        case .confirm:  return Color(hex: "9B7FD4")  // 紫色
        }
    }
}

// MARK: - Chat Suggestion

/// A single conversation suggestion.
///
/// `primaryText` is in the **source language** (the language before translation),
/// because the user needs to reply in the other party's language.
/// `secondaryText` is the translated version for the user's own reference.
///
/// Example (EN → 中文 mode):
///   primaryText   = "Sure, I'll sort out the timeline."   (English — to reply)
///   secondaryText = "好的，我来梳理一下时间节点"               (Chinese — for reference)
struct ChatSuggestion: Identifiable, Codable, Equatable {
    let id: UUID
    let tag: SuggestionTag
    let primaryText: String      // 翻译前的语言（用来回复对方）
    let secondaryText: String    // 翻译后的语言（帮用户理解）
    let createdAt: Date

    init(
        id: UUID = UUID(),
        tag: SuggestionTag,
        primaryText: String,
        secondaryText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.tag = tag
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.createdAt = createdAt
    }

    static func == (lhs: ChatSuggestion, rhs: ChatSuggestion) -> Bool {
        lhs.id == rhs.id
    }
}
