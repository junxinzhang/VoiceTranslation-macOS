//
//  PermissionGuideView.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-12.
//

import SwiftUI

struct PermissionGuideView: View {
    @ObservedObject var permissionManager = PermissionManager.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                Text("权限设置指导")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("关闭") {
                    isPresented = false
                }
                .buttonStyle(.borderless)
            }
            .padding(.bottom)
            
            // 权限状态卡片
            VStack(spacing: 16) {
                PermissionStatusCard(
                    title: "麦克风权限",
                    icon: "mic.fill",
                    status: permissionManager.microphoneStatus,
                    description: "用于录制语音进行识别",
                    permissionType: .microphone
                )
                
                PermissionStatusCard(
                    title: "语音识别权限",
                    icon: "waveform",
                    status: permissionManager.speechRecognitionStatus,
                    description: "将语音转换为文本",
                    permissionType: .speechRecognition
                )
                
                PermissionStatusCard(
                    title: "屏幕录制权限",
                    icon: "display",
                    status: permissionManager.screenRecordingStatus,
                    description: "用于捕获系统音频（可选，需要macOS 13.0+）",
                    permissionType: .screenRecording
                )
            }
            
            // 整体状态指示
            OverallStatusIndicator()
            
            // 操作按钮
            HStack(spacing: 12) {
                Button("重新检查") {
                    Task {
                        await permissionManager.checkAllPermissions()
                    }
                }
                .buttonStyle(.bordered)
                
                Button("重置缓存") {
                    permissionManager.resetCache()
                    Task {
                        await permissionManager.checkAllPermissions()
                    }
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if canStartBasicFunctionality {
                    Button(startButtonText) {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if canRequestSystemAudioPermission {
                    Button("开启系统音频") {
                        Task {
                            await permissionManager.requestScreenRecordingPermissionWithGuidance()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 500, height: 450)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .onAppear {
            Task {
                await permissionManager.checkAllPermissions()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var canStartBasicFunctionality: Bool {
        permissionManager.microphoneStatus.isAuthorized && 
        permissionManager.speechRecognitionStatus.isAuthorized
    }
    
    private var canRequestSystemAudioPermission: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return canStartBasicFunctionality && !permissionManager.screenRecordingStatus.isAuthorized
    }
    
    private var startButtonText: String {
        let hasAllPermissions = permissionManager.microphoneStatus.isAuthorized && 
                               permissionManager.speechRecognitionStatus.isAuthorized && 
                               permissionManager.screenRecordingStatus.isAuthorized
        
        if hasAllPermissions {
            return "开始使用（全功能）"
        } else {
            return "开始使用（麦克风模式）"
        }
    }
}

struct PermissionStatusCard: View {
    let title: String
    let icon: String
    let status: PermissionStatus
    let description: String
    let permissionType: PermissionType
    
    @ObservedObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标和状态指示器
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .foregroundColor(statusColor)
                    .font(.title2)
                
                // 状态角标
                if status != .notDetermined {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: statusIcon)
                                .foregroundColor(.white)
                                .font(.caption)
                                .background(
                                    Circle()
                                        .fill(statusColor)
                                        .frame(width: 16, height: 16)
                                )
                        }
                    }
                }
            }
            
            // 详细信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(statusColor.opacity(0.2))
                        )
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // 操作按钮
                if shouldShowActionButton {
                    HStack(spacing: 8) {
                        Button("打开设置") {
                            permissionManager.openSystemPreferencesForPermission(permissionType)
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                        .foregroundColor(.accentColor)
                        
                        if permissionType == .screenRecording && !status.isAuthorized {
                            Button("智能申请") {
                                Task {
                                    await permissionManager.requestScreenRecordingPermissionWithGuidance()
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                            .foregroundColor(.green)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var statusColor: Color {
        switch status {
        case .granted:
            return .green
        case .denied:
            return .red
        case .restricted:
            return .orange
        case .unavailable:
            return .gray
        case .notDetermined:
            return .blue
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .granted:
            return "checkmark"
        case .denied:
            return "xmark"
        case .restricted:
            return "exclamationmark"
        case .unavailable:
            return "minus"
        case .notDetermined:
            return "questionmark"
        }
    }
    
    private var statusText: String {
        switch status {
        case .granted:
            return "已授权"
        case .denied:
            return "被拒绝"
        case .restricted:
            return "受限制"
        case .unavailable:
            if permissionType == .screenRecording {
                return "系统不支持"
            }
            return "不可用"
        case .notDetermined:
            return "未确定"
        }
    }
    
    private var shouldShowActionButton: Bool {
        if status == .unavailable {
            return false  // 不可用的权限不显示操作按钮
        }
        
        if permissionType == .screenRecording {
            // 屏幕录制权限需要macOS 13.0+
            guard #available(macOS 13.0, *) else { return false }
        }
        
        return !status.isAuthorized
    }
}

struct OverallStatusIndicator: View {
    @ObservedObject private var permissionManager = PermissionManager.shared
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: overallStatusIcon)
                    .foregroundColor(overallStatusColor)
                    .font(.title2)
                
                Text("整体状态")
                    .font(.headline)
                
                Spacer()
                
                Text(overallStatusText)
                    .font(.subheadline)
                    .foregroundColor(overallStatusColor)
                    .fontWeight(.medium)
            }
            
            ProgressView(value: overallProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: overallStatusColor))
            
            if !overallStatusMessage.isEmpty {
                Text(overallStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .background(overallStatusColor.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var overallProgress: Double {
        let micStatus = permissionManager.microphoneStatus.isAuthorized ? 1.0 : 0.0
        let speechStatus = permissionManager.speechRecognitionStatus.isAuthorized ? 1.0 : 0.0
        let screenStatus = permissionManager.screenRecordingStatus.isAuthorized ? 0.5 : 0.0 // 可选权限
        
        return (micStatus + speechStatus + screenStatus) / 2.5
    }
    
    private var overallStatusColor: Color {
        let micGranted = permissionManager.microphoneStatus.isAuthorized
        let speechGranted = permissionManager.speechRecognitionStatus.isAuthorized
        
        if micGranted && speechGranted {
            return .green
        } else if micGranted || speechGranted {
            return .orange
        } else {
            return .red
        }
    }
    
    private var overallStatusIcon: String {
        let micGranted = permissionManager.microphoneStatus.isAuthorized
        let speechGranted = permissionManager.speechRecognitionStatus.isAuthorized
        
        if micGranted && speechGranted {
            return "checkmark.circle.fill"
        } else if micGranted || speechGranted {
            return "exclamationmark.circle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }
    
    private var overallStatusText: String {
        let micGranted = permissionManager.microphoneStatus.isAuthorized
        let speechGranted = permissionManager.speechRecognitionStatus.isAuthorized
        let screenGranted = permissionManager.screenRecordingStatus.isAuthorized
        
        if micGranted && speechGranted && screenGranted {
            return "完全就绪"
        } else if micGranted && speechGranted {
            return "基本就绪"
        } else if micGranted || speechGranted {
            return "部分就绪"
        } else {
            return "需要授权"
        }
    }
    
    private var overallStatusMessage: String {
        let micGranted = permissionManager.microphoneStatus.isAuthorized
        let speechGranted = permissionManager.speechRecognitionStatus.isAuthorized
        let screenGranted = permissionManager.screenRecordingStatus.isAuthorized
        
        if micGranted && speechGranted && screenGranted {
            return "所有权限已就绪，可以使用完整功能（麦克风 + 系统音频）。"
        } else if micGranted && speechGranted {
            let systemAudioNote = {
                if #available(macOS 13.0, *) {
                    return "屏幕录制权限可选，用于系统音频翻译。"
                } else {
                    return "系统音频功能需要macOS 13.0+。"
                }
            }()
            return "基础权限已就绪，可以使用麦克风翻译。\(systemAudioNote)"
        } else if micGranted {
            return "已有麦克风权限，还需要语音识别权限才能开始翻译。"
        } else if speechGranted {
            return "已有语音识别权限，还需要麦克风权限才能录音。"
        } else {
            return "请授予麦克风和语音识别权限以开始使用翻译功能。"
        }
    }
}

#Preview {
    PermissionGuideView(isPresented: .constant(true))
}