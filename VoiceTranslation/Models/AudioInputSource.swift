//
//  AudioInputSource.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation

enum AudioInputSource: String, CaseIterable, Identifiable {
    case microphone = "microphone"
    case systemAudio = "systemAudio"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .microphone:
            return "麦克风"
        case .systemAudio:
            return "系统音频"
        }
    }
    
    var description: String {
        switch self {
        case .microphone:
            return "从麦克风捕获语音"
        case .systemAudio:
            return "从系统音频输出捕获声音，即使在静音模式下也能识别视频音频"
        }
    }
    
    var statusInfo: String {
        switch self {
        case .microphone:
            return "✅ 直接从麦克风录制音频"
        case .systemAudio:
            return "🔊 系统音频模式：使用ScreenCaptureKit捕获所有系统音频"
        }
    }
    
    var iconName: String {
        switch self {
        case .microphone:
            return "mic.fill"
        case .systemAudio:
            return "speaker.wave.3.fill"
        }
    }
}