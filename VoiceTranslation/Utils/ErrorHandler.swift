//
//  ErrorHandler.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation
import SwiftUI

enum TranslationError: LocalizedError {
    case speechRecognitionDenied
    case screenRecordingDenied
    case networkError(String)
    case apiKeyMissing
    case openAIError(String)
    case audioEngineError
    case invalidResponse
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .speechRecognitionDenied:
            return Constants.ErrorMessages.speechRecognitionDenied
        case .screenRecordingDenied:
            return "系统音频捕获需要屏幕录制权限。应用将自动使用麦克风模式。"
        case .networkError(let message):
            return "\(Constants.ErrorMessages.networkError)\n详细信息: \(message)"
        case .apiKeyMissing:
            return Constants.ErrorMessages.apiKeyMissing
        case .openAIError(let message):
            return "\(Constants.ErrorMessages.translationError)\n详细信息: \(message)"
        case .audioEngineError:
            return Constants.ErrorMessages.audioEngineError
        case .invalidResponse:
            return "收到了无效的响应格式。"
        case .rateLimitExceeded:
            return "API 调用频率超限，请稍后再试。"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .speechRecognitionDenied:
            return "请在系统偏好设置 > 安全性与隐私 > 隐私 > 麦克风中允许此应用访问麦克风。"
        case .screenRecordingDenied:
            return "请在系统偏好设置 > 安全性与隐私 > 隐私 > 屏幕录制中勾选 VoiceTranslation，然后完全重启应用。"
        case .networkError:
            return "请检查您的网络连接，然后重试。"
        case .apiKeyMissing:
            return "请在设置页面中输入有效的 API 信息（Key / Base URL / Model）。"
        case .openAIError:
            return "请检查您的 API Key 是否有效，或稍后重试。"
        case .audioEngineError:
            return "请重启应用或检查音频设备连接。"
        case .invalidResponse:
            return "服务可能暂时不可用，请稍后重试。"
        case .rateLimitExceeded:
            return "您的 API 调用次数已达到限制，请等待一段时间后再试。"
        }
    }
}

class ErrorHandler: ObservableObject {
    @Published var currentError: TranslationError?
    @Published var showErrorAlert = false
    
    func handleError(_ error: TranslationError) {
        DispatchQueue.main.async {
            self.currentError = error
            self.showErrorAlert = true
        }
    }
    
    func handleError(_ error: Error) {
        if let translationError = error as? TranslationError {
            handleError(translationError)
        } else {
            handleError(.networkError(error.localizedDescription))
        }
    }
    
    func clearError() {
        DispatchQueue.main.async {
            self.currentError = nil
            self.showErrorAlert = false
        }
    }
}
