//
//  TTSService.swift
//  VoiceTranslation
//
//  Text-to-Speech service using AVSpeechSynthesizer.
//  Speaks suggestion text aloud so the meeting microphone can pick it up.
//  Supports both English and Chinese TTS voices.
//
//  Created on 2026-03-05.
//

import AVFoundation
import Combine

// MARK: - TTS Service

class TTSService: NSObject, ObservableObject {
    static let shared = TTSService()

    private let synthesizer = AVSpeechSynthesizer()

    /// ID of the suggestion currently being spoken
    @Published var speakingId: UUID?

    /// Whether TTS is currently active
    @Published var isSpeaking: Bool = false

    /// Speaking rate (0.0 ~ 1.0, default 0.5)
    var rate: Float = 0.48

    /// Volume (0.0 ~ 1.0)
    var volume: Float = 1.0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// Speak the given text with auto-detected language
    /// - Parameters:
    ///   - text: The text to speak
    ///   - id: Optional suggestion ID for UI feedback
    ///   - language: BCP 47 language code, e.g. "en-US" or "zh-CN"
    func speak(_ text: String, id: UUID? = nil, language: String? = nil) {
        // Stop any current speech first
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.volume = volume
        utterance.pitchMultiplier = 1.0

        // Set voice based on language
        let langCode = language ?? detectLanguage(text)
        if let voice = AVSpeechSynthesisVoice(language: langCode) {
            utterance.voice = voice
        }

        // Pre/post utterance delay
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.0

        speakingId = id
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stop current speech
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speakingId = nil
        isSpeaking = false
    }

    /// Speak a chat suggestion's primary text
    /// - Parameters:
    ///   - suggestion: The suggestion to speak
    ///   - direction: Language direction to determine the correct voice
    func speakSuggestion(_ suggestion: ChatSuggestion, direction: LanguageDirection) {
        let language: String
        switch direction {
        case .englishToChinese:
            // Primary text is English (reply language)
            language = "en-US"
        case .chineseToEnglish:
            // Primary text is Chinese (reply language)
            language = "zh-CN"
        }
        speak(suggestion.primaryText, id: suggestion.id, language: language)
    }

    // MARK: - Language Detection

    private func detectLanguage(_ text: String) -> String {
        // Simple heuristic: check if text contains CJK characters
        let chineseRange = text.range(of: "\\p{Han}", options: .regularExpression)
        if chineseRange != nil {
            // Count Chinese vs Latin characters
            let chineseCount = text.unicodeScalars.filter { $0.properties.isIdeographic }.count
            let totalCount = text.unicodeScalars.filter { !$0.properties.isWhitespace }.count
            if totalCount > 0 && Double(chineseCount) / Double(totalCount) > 0.3 {
                return "zh-CN"
            }
        }
        return "en-US"
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.speakingId = nil
            self?.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.speakingId = nil
            self?.isSpeaking = false
        }
    }
}
