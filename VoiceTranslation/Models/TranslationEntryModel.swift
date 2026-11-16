//
//  TranslationEntryModel.swift
//  VoiceTranslation
//
//  Structured translation entry — replaces string-based accumulation.
//  Created on 2026-02-27.
//

import Foundation

/// A single translation entry displayed in both MainView and FloatingOverlayView.
struct TranslationEntryModel: Identifiable, Equatable {
    let id: UUID
    let originalText: String
    var translatedText: String
    let timestamp: String
    let createdAt: Date
    var isLive: Bool
    var statusMessage: String
    var isError: Bool
    var canEditOriginal: Bool
    var isManuallyEdited: Bool
    var containsCriticalFacts: Bool

    // Shared DateFormatter (expensive to create; reuse)
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(
        id: UUID = UUID(),
        originalText: String,
        translatedText: String = "",
        timestamp: String? = nil,
        createdAt: Date = Date(),
        isLive: Bool = false,
        isError: Bool = false,
        statusMessage: String = "",
        canEditOriginal: Bool = false,
        isManuallyEdited: Bool = false,
        containsCriticalFacts: Bool? = nil
    ) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.timestamp = timestamp ?? Self.timestampFormatter.string(from: createdAt)
        self.createdAt = createdAt
        self.isLive = isLive
        self.isError = isError
        self.statusMessage = statusMessage
        self.canEditOriginal = canEditOriginal
        self.isManuallyEdited = isManuallyEdited
        self.containsCriticalFacts = containsCriticalFacts ?? TranslationIntegrity.containsFacts(originalText)
    }

    /// Create an error entry
    static func errorEntry(_ message: String) -> TranslationEntryModel {
        TranslationEntryModel(
            originalText: "❌ 错误: \(message)",
            isError: true
        )
    }

    /// Formatted text for plain display / export
    var plainText: String {
        var result = "[\(timestamp)]\n\(originalText)"
        if !translatedText.isEmpty {
            result += "\n→ \(translatedText)"
        }
        return result
    }

    static func == (lhs: TranslationEntryModel, rhs: TranslationEntryModel) -> Bool {
        lhs.id == rhs.id
            && lhs.originalText == rhs.originalText
            && lhs.translatedText == rhs.translatedText
            && lhs.isLive == rhs.isLive
            && lhs.isError == rhs.isError
            && lhs.statusMessage == rhs.statusMessage
            && lhs.canEditOriginal == rhs.canEditOriginal
            && lhs.isManuallyEdited == rhs.isManuallyEdited
    }
}
