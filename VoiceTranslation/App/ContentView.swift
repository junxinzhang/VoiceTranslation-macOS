//
//  ContentView.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import SwiftUI
import Speech

struct ContentView: View {
    @StateObject private var appSettings = AppSettings()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @StateObject private var historyManager = HistoryManager()
    @StateObject private var errorHandler = ErrorHandler()
    @StateObject private var translationService: TranslationService

    init() {
        let settings = AppSettings()
        _appSettings = StateObject(wrappedValue: settings)
        _speechRecognizer = StateObject(wrappedValue: SpeechRecognizer())
        _historyManager = StateObject(wrappedValue: HistoryManager())
        _errorHandler = StateObject(wrappedValue: ErrorHandler())
        _translationService = StateObject(wrappedValue: TranslationService(appSettings: settings))
    }
    
    @State private var showingPermissionAlert = false
    @State private var permissionDenied = false
    
    var body: some View {
        Group {
            if speechRecognizer.authorizationStatus == .authorized {
                // 主应用界面
                MainView(
                    speechRecognizer: speechRecognizer,
                    translationService: translationService,
                    historyManager: historyManager,
                    appSettings: appSettings,
                    errorHandler: errorHandler
                )
                    .environmentObject(appSettings)
                    .environmentObject(speechRecognizer)
                    .environmentObject(translationService)
                    .environmentObject(historyManager)
                    .environmentObject(errorHandler)
            } else {
                // 权限请求界面
                PermissionRequestView(
                    authorizationStatus: speechRecognizer.authorizationStatus,
                    onRequestPermission: {
                        speechRecognizer.requestAuthorization()
                    }
                )
            }
        }
        .frame(minWidth: Constants.UI.minWindowWidth, minHeight: Constants.UI.minWindowHeight)
        .onAppear {
            setupApp()
        }
        .alert("权限被拒绝", isPresented: $showingPermissionAlert) {
            Button("打开系统设置") {
                openSystemPreferences()
            }
            Button("稍后设置", role: .cancel) {
                permissionDenied = true
            }
        } message: {
            Text("语音翻译需要麦克风和语音识别权限才能正常工作。请在系统设置中手动开启这些权限。")
        }
        .onChange(of: speechRecognizer.authorizationStatus) { newStatus in
            if newStatus == .denied || newStatus == .restricted {
                showingPermissionAlert = true
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupApp() {
        // 应用启动时的初始化工作
        print("应用启动完成")
        
        // 检查并请求必要的权限
        checkPermissions()
        
        // 设置语音识别器的语言
        speechRecognizer.setLanguage(appSettings.selectedLanguageDirection.speechLocale)
        
        // 设置音频输入源
        speechRecognizer.setAudioInputSource(appSettings.audioInputSource)
    }
    
    private func checkPermissions() {
        // 只检查权限状态，不自动触发请求弹窗
        // 用户需要点击"授权权限"按钮才会触发权限请求
        speechRecognizer.checkAuthorizationStatus()

        switch speechRecognizer.authorizationStatus {
        case .notDetermined:
            // 不自动请求，等待用户点击按钮
            print("🔍 语音识别权限状态: 未确定，等待用户授权")
        case .denied, .restricted:
            permissionDenied = true
            print("⚠️ 语音识别权限状态: 已被拒绝")
        case .authorized:
            print("✅ 语音识别权限状态: 已授权")
        @unknown default:
            break
        }
    }
    
    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Permission Request View

struct PermissionRequestView: View {
    let authorizationStatus: SFSpeechRecognizerAuthorizationStatus
    let onRequestPermission: () -> Void
    
    var body: some View {
        VStack(spacing: Constants.UI.padding * 2) {
            Spacer()
            
            // 图标
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            // 标题
            Text("欢迎使用语音实时翻译")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // 描述
            VStack(spacing: Constants.UI.padding) {
                Text("为了提供最佳的语音翻译体验，我们需要以下权限：")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    PermissionItem(
                        icon: "mic.fill",
                        title: "麦克风权限",
                        description: "用于录制您的语音输入"
                    )
                    
                    PermissionItem(
                        icon: "waveform",
                        title: "语音识别权限",
                        description: "用于将语音转换为文字"
                    )
                }
                .padding(Constants.UI.padding)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(Constants.UI.cornerRadius)
            }
            
            // 状态信息
            statusText
            
            // 操作按钮
            actionButton
            
            Spacer()
            
            // 底部说明
            Text("语音识别可能使用系统在线服务，文字会发送至所选翻译服务。开启历史记录后，文字内容保存在本机。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Constants.UI.padding * 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Status Text
    
    private var statusText: some View {
        Group {
            switch authorizationStatus {
            case .notDetermined:
                Text("点击下方按钮开始设置权限")
                    .foregroundColor(.secondary)
            case .denied, .restricted:
                Text("权限被拒绝。请在系统设置中手动开启麦克风和语音识别权限。")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            case .authorized:
                Text("权限已获取，正在加载...")
                    .foregroundColor(.green)
            @unknown default:
                Text("检查权限状态...")
                    .foregroundColor(.secondary)
            }
        }
        .font(.body)
    }
    
    // MARK: - Action Button
    
    private var actionButton: some View {
        Group {
            switch authorizationStatus {
            case .notDetermined:
                Button(action: onRequestPermission) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                        Text("授权权限")
                    }
                    .frame(height: 44)
                    .frame(maxWidth: 200)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                
            case .denied, .restricted:
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(BorderedProminentButtonStyle())
                
            case .authorized:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在加载应用...")
                }
                
            @unknown default:
                EmptyView()
            }
        }
    }
}

// MARK: - Permission Item

struct PermissionItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: Constants.UI.padding) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
