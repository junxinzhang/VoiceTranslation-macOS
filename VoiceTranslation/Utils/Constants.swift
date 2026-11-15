//
//  Constants.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation
import SwiftUI

struct Constants {

    // MARK: - Design System Colors
    struct Colors {
        // Backgrounds
        static let bgPrimary = Color(hex: "F5F4F1")        // 温暖奶油色背景
        static let bgSurface = Color.white                  // 白色卡片表面
        static let bgElevated = Color(hex: "FAFAF8")       // 轻微温暖白
        static let bgMuted = Color(hex: "EDECEA")          // 温暖灰控件背景

        // Text
        static let textPrimary = Color(hex: "1A1918")      // 标题、主要内容
        static let textSecondary = Color(hex: "6D6C6A")    // 正文、描述
        static let textTertiary = Color(hex: "9C9B99")     // 标签、占位符

        // Borders
        static let borderSubtle = Color(hex: "E5E4E1")     // 卡片边框、分隔线
        static let borderStrong = Color(hex: "D1D0CD")     // 强调边框

        // Accents
        static let accentPrimary = Color(hex: "3D8A5A")    // 主要绿色
        static let accentLight = Color(hex: "C8F0D8")      // 浅绿色背景
        static let accentDark = Color(hex: "4D9B6A")       // 深绿色
        static let accentWarm = Color(hex: "D89575")       // 珊瑚色

        // Semantic
        static let statusPositive = Color(hex: "4D9B6A")   // 成功状态
        static let statusNegative = Color(hex: "D08068")   // 错误/录音状态
        static let statusWarning = Color(hex: "D4A64A")    // 警告状态
    }

    // MARK: - Design System Shadows
    struct Shadows {
        static let card = Shadow(color: Color.black.opacity(0.03), radius: 12, x: 0, y: 2)
        static let elevated = Shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        static let button = Shadow(color: Colors.accentPrimary.opacity(0.25), radius: 16, x: 0, y: 4)
        static let buttonRecording = Shadow(color: Colors.statusNegative.opacity(0.25), radius: 16, x: 0, y: 4)
    }

    // MARK: - Design System Typography
    struct Typography {
        static let largeTitle: Font = .system(size: 28, weight: .semibold, design: .rounded)
        static let title: Font = .system(size: 22, weight: .semibold, design: .rounded)
        static let headline: Font = .system(size: 15, weight: .semibold, design: .rounded)
        static let body: Font = .system(size: 14, weight: .regular, design: .rounded)
        static let caption: Font = .system(size: 13, weight: .medium, design: .rounded)
        static let small: Font = .system(size: 11, weight: .regular, design: .rounded)
    }

    // MARK: - Shadow Helper
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    
    // MARK: - API Configuration
    struct OpenAI {
        static let baseURL = "https://api.openai.com/v1/chat/completions"
        static let model = "gpt-4.1-nano"
        static let maxTokens = 1000
        static let temperature = 0.3
    }

    // MARK: - Custom API Configuration
    struct CustomAPI {
        static let defaultBaseURL = "https://api.siliconflow.cn/v1/chat/completions"
        static let defaultModel = "tencent/Hunyuan-MT-7B"
        static let maxTokens = 1000
        static let temperature = 0.3
    }
    
    // MARK: - App Configuration
    struct App {
        static let bundleIdentifier = "com.voicetranslation.macos"
        static let appName = "VoiceTranslation"

        static var version: String {
            let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

            switch (short, build) {
            case let (s?, b?) where !s.isEmpty && !b.isEmpty:
                return "\(s) (\(b))"
            case let (s?, _):
                return s
            case let (_, b?):
                return b
            default:
                return "Unknown"
            }
        }

        static var shortVersion: String {
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
        }
    }
    
    // MARK: - User Defaults Keys
    struct UserDefaults {
        static let openAIApiKey = "OpenAI_API_Key"
        static let customAPIKey = "Custom_API_Key"
        static let customAPIBaseURL = "Custom_API_Base_URL"
        static let customAPIModel = "Custom_API_Model"
        static let apiProvider = "API_Provider"
        static let selectedLanguageDirection = "Selected_Language_Direction"
        static let keepHistory = "Keep_History"
        static let maxHistoryItems = "Max_History_Items"
        static let autoDetectLanguage = "Auto_Detect_Language"
        static let showTranslationAnimation = "Show_Translation_Animation"
        static let audioInputSource = "Audio_Input_Source"
        static let hasCompletedOnboarding = "Has_Completed_Onboarding"
    }
    
    // MARK: - UI Constants
    struct UI {
        static let cornerRadius: CGFloat = 12
        static let padding: CGFloat = 16
        static let minWindowWidth: CGFloat = 787
        static let minWindowHeight: CGFloat = 787
    }
    
    // MARK: - Translation Prompts
    struct Prompts {
        static let englishToChinese = """
        你是一个专业的英中翻译助手。请将用户输入的英文准确翻译成中文。要求：
        1. 保持原意不变
        2. 表达自然流畅
        3. 只返回翻译结果，不要其他内容
        """
        
        static let chineseToEnglish = """
        You are a professional Chinese-English translation assistant. Please translate the user's Chinese input into accurate English. Requirements:
        1. Maintain the original meaning
        2. Express naturally and fluently
        3. Only return the translation result, no other content
        """
    }
    
    // MARK: - Error Messages
    struct ErrorMessages {
        static let speechRecognitionDenied = "语音识别权限被拒绝，请在系统设置中允许麦克风访问。"
        static let apiKeyMissing = "请在设置中配置有效的 API 信息（Key / Base URL / Model）。"
        static let networkError = "网络连接失败，请检查网络设置。"
        static let audioEngineError = "音频引擎启动失败。"
        static let translationError = "翻译服务出现错误。"
        static let microphonePermissionDenied = "麦克风权限被拒绝，请在系统偏好设置中允许访问。"
        static let screenRecordingPermissionDenied = "屏幕录制权限被拒绝，系统音频功能不可用。"
        static let systemAudioNotAvailable = "系统音频功能在当前设备或系统版本上不可用。"
        static let audioQualityPoor = "音频质量较差，可能影响识别准确性。"
        
        // 系统音频相关错误
        static let systemAudioSetupFailed = "系统音频设置失败，已自动切换到麦克风模式。"
        static let systemAudioVersionNotSupported = "系统音频功能需要 macOS 13.0 或更高版本。"
        static let systemAudioContentAccessFailed = "虽然权限已授予，但无法访问系统音频内容。"
        static let systemAudioStreamFailed = "系统音频流启动失败。"
        static let audioFormatConversionFailed = "音频格式转换失败。"
        static let audioBufferCreationFailed = "音频缓冲区创建失败。"
        
        // 权限相关错误
        static let permissionCheckFailed = "权限检查失败。"
        static let permissionValidationFailed = "权限验证失败。"
        static let multiplePermissionsDenied = "多个权限被拒绝，应用功能受限。"
    }
    
    // MARK: - Permission Messages
    struct PermissionMessages {
        static let microphoneDescription = "用于录制语音进行语音识别"
        static let speechRecognitionDescription = "将您的语音转换为文本"
        static let screenRecordingDescription = "捕获系统音频进行翻译（可选功能）"
        static let permissionDeniedTitle = "权限不足"
        static let permissionRequiredTitle = "需要权限"
        static let openSystemPreferences = "打开系统偏好设置"
        static let retryPermissionCheck = "重新检查权限"
        
        // 详细权限指导
        static let microphonePermissionGuide = """
        为了使用语音识别功能，需要麦克风权限：
        
        1. 打开【系统偏好设置】
        2. 选择【安全性与隐私】
        3. 点击【隐私】标签
        4. 选择【麦克风】
        5. 勾选【VoiceTranslation】
        
        完成后请重启应用。
        """
        
        static let speechRecognitionPermissionGuide = """
        为了使用语音识别功能，需要语音识别权限：
        
        1. 打开【系统偏好设置】
        2. 选择【安全性与隐私】
        3. 点击【隐私】标签
        4. 选择【语音识别】
        5. 勾选【VoiceTranslation】
        
        完成后请重启应用。
        """
        
        static let screenRecordingPermissionGuide = """
        为了使用系统音频功能，需要屏幕录制权限：
        
        1. 打开【系统偏好设置】
        2. 选择【安全性与隐私】
        3. 点击【隐私】标签
        4. 选择【屏幕录制】
        5. 勾选【VoiceTranslation】
        
        注意：如果已经勾选，请先取消勾选，等待1-2秒后再重新勾选。
        完成后请完全退出并重新启动应用。
        """
        
        static let fallbackToMicrophoneMessage = "系统音频不可用，已自动切换到麦克风模式。"
        static let systemAudioRequiresNewerMacOS = "系统音频功能需要 macOS 13.0 或更高版本。"
    }
    
    // MARK: - Audio Configuration
    struct Audio {
        // ScreenCaptureKit 音频配置
        static let systemAudioSampleRate: Double = 48000.0  // ScreenCaptureKit 默认采样率
        static let systemAudioChannels: UInt32 = 2          // 立体声
        static let systemAudioFormat = "Float32"            // 32位浮点格式
        
        // Speech Recognition 音频配置
        static let speechRecognitionSampleRate: Double = 16000.0  // Speech框架要求
        static let speechRecognitionChannels: UInt32 = 1          // 单声道
        
        // 音频处理配置
        static let audioBufferSize: UInt32 = 4096          // 音频缓冲区大小
        static let audioProcessingDelay: UInt64 = 300_000_000  // 300ms 处理延迟
        static let audioConversionTimeout: TimeInterval = 5.0   // 音频转换超时
        
        // 音频质量阈值
        static let minimumAudioLevel: Float = -60.0        // 最低音频电平 (dB)
        static let maximumAudioLevel: Float = 0.0          // 最高音频电平 (dB)
        static let audioQualityThreshold: Float = -40.0    // 音频质量阈值
    }
    
    // MARK: - System Audio Configuration
    struct SystemAudio {
        static let minimumMacOSVersion = "13.0"
        static let requiredFramework = "ScreenCaptureKit"
        static let retryAttempts = 3
        static let retryDelay: UInt64 = 500_000_000  // 500ms
        static let initializationTimeout: UInt64 = 300_000_000  // 300ms
        
        // 音频流配置
        static let minimumFrameInterval = 1  // 最低帧率用于视频
        static let excludeCurrentProcessAudio = true  // 排除当前应用音频
        static let audioReliabilityIndicators = false  // 关闭音频可靠性指示器
    }
    
    // MARK: - Logging Configuration
    struct Logging {
        static let audioProcessingLogInterval = 10  // 每10秒输出一次音频处理状态
        static let permissionCheckLogLevel = "详细"  // 权限检查日志级别
        static let systemAudioLogLevel = "详细"     // 系统音频日志级别
        static let enableDebugLogs = true          // 是否启用调试日志
    }
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Extension for Card Style
extension View {
    func cardStyle(cornerRadius: CGFloat = 16, padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(Constants.Colors.bgSurface)
            .cornerRadius(cornerRadius)
            .shadow(
                color: Color.black.opacity(0.03),
                radius: 12,
                x: 0,
                y: 2
            )
    }

    func segmentedButtonStyle(isSelected: Bool) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Constants.Colors.bgSurface : Color.clear)
            .cornerRadius(8)
            .shadow(
                color: isSelected ? Color.black.opacity(0.03) : Color.clear,
                radius: 2,
                x: 0,
                y: 1
            )
    }
}
