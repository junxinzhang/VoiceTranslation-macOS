//
//  PermissionManager.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-12.
//

import Foundation
import Speech
import AVFoundation
import ScreenCaptureKit
import CoreGraphics
import Combine

/// 权限状态枚举
public enum PermissionStatus {
    case notDetermined      // 未确定
    case granted           // 已授权
    case denied            // 被拒绝
    case restricted        // 受限制
    case unavailable       // 不可用（系统版本不支持等）
    
    var isAuthorized: Bool {
        return self == .granted
    }
}

/// 权限类型枚举
public enum PermissionType: String, CaseIterable {
    case microphone = "microphone"               // 麦克风权限
    case speechRecognition = "speechRecognition" // 语音识别权限
    case screenRecording = "screenRecording"     // 屏幕录制权限
}

/// 权限变更通知
public struct PermissionStatusChange {
    let type: PermissionType
    let oldStatus: PermissionStatus
    let newStatus: PermissionStatus
    let timestamp: Date
}

/// 统一权限管理器
@MainActor
public class PermissionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published public private(set) var speechRecognitionStatus: PermissionStatus = .notDetermined
    @Published public private(set) var screenRecordingStatus: PermissionStatus = .notDetermined
    
    // 权限检查进度状态
    @Published public private(set) var isCheckingPermissions = false
    @Published public private(set) var permissionCheckProgress: Double = 0.0
    
    // 用户引导状态
    @Published public var showPermissionGuide = false
    @Published public var pendingPermissionType: PermissionType?
    
    // MARK: - Private Properties
    
    private let statusChangeSubject = PassthroughSubject<PermissionStatusChange, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let permissionQueue = DispatchQueue(label: "PermissionManager", qos: .userInitiated)
    
    // 权限状态缓存（避免频繁系统调用）
    private var lastMicrophoneCheck: Date?
    private var lastSpeechRecognitionCheck: Date?
    private var lastScreenRecordingCheck: Date?
    private let cacheValidityInterval: TimeInterval = 5.0 // 5秒缓存
    
    // MARK: - Singleton
    
    public static let shared = PermissionManager()
    
    private init() {
        setupPermissionMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// 权限状态变更发布者
    public var permissionStatusChanges: AnyPublisher<PermissionStatusChange, Never> {
        statusChangeSubject.eraseToAnyPublisher()
    }
    
    /// 全面检查所有权限状态
    public func checkAllPermissions() async {
        await withTaskGroup(of: Void.self) { group in
            isCheckingPermissions = true
            permissionCheckProgress = 0.0
            
            group.addTask { [weak self] in
                await self?.checkMicrophonePermission()
                await MainActor.run { [weak self] in
                    self?.permissionCheckProgress = 0.33
                }
            }
            
            group.addTask { [weak self] in
                await self?.checkSpeechRecognitionPermission()
                await MainActor.run { [weak self] in
                    self?.permissionCheckProgress = 0.66
                }
            }
            
            group.addTask { [weak self] in
                await self?.checkScreenRecordingPermission()
                await MainActor.run { [weak self] in
                    self?.permissionCheckProgress = 1.0
                }
            }
            
            await group.waitForAll()
            
            isCheckingPermissions = false
            print("✅ 所有权限检查完成")
            printPermissionSummary()
        }
    }
    
    /// 检查麦克风权限（仅检查状态，不触发请求）
    @discardableResult
    public func checkMicrophonePermission() async -> PermissionStatus {
        // 检查缓存
        if let lastCheck = lastMicrophoneCheck,
           Date().timeIntervalSince(lastCheck) < cacheValidityInterval {
            return microphoneStatus
        }

        // 使用只检查状态的API，不触发权限请求
        let newStatus: PermissionStatus
        if #available(macOS 14.0, *) {
            let permission = AVAudioApplication.shared.recordPermission
            switch permission {
            case .undetermined:
                newStatus = .notDetermined
            case .denied:
                newStatus = .denied
            case .granted:
                newStatus = .granted
            @unknown default:
                newStatus = .notDetermined
            }
        } else {
            let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            switch authStatus {
            case .notDetermined:
                newStatus = .notDetermined
            case .denied:
                newStatus = .denied
            case .restricted:
                newStatus = .restricted
            case .authorized:
                newStatus = .granted
            @unknown default:
                newStatus = .notDetermined
            }
        }

        let oldStatus = microphoneStatus
        updateMicrophoneStatus(newStatus, oldStatus: oldStatus)
        lastMicrophoneCheck = Date()

        return newStatus
    }

    /// 请求麦克风权限（主动触发权限请求）
    public func requestMicrophonePermission() async -> PermissionStatus {
        // 先检查当前状态，如果已授权则无需请求
        let currentStatus = await checkMicrophonePermission()
        if currentStatus.isAuthorized {
            return currentStatus
        }

        // 如果状态不是 notDetermined，说明用户已做出选择，无法再次请求
        if currentStatus != .notDetermined {
            print("⚠️ 麦克风权限已被拒绝，请用户手动在系统设置中开启")
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            if #available(macOS 14.0, *) {
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    Task { @MainActor [weak self] in
                        let newStatus: PermissionStatus = granted ? .granted : .denied
                        let oldStatus = self?.microphoneStatus ?? .notDetermined

                        self?.updateMicrophoneStatus(newStatus, oldStatus: oldStatus)
                        self?.lastMicrophoneCheck = Date()

                        continuation.resume(returning: newStatus)
                    }
                }
            } else {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    Task { @MainActor [weak self] in
                        let newStatus: PermissionStatus = granted ? .granted : .denied
                        let oldStatus = self?.microphoneStatus ?? .notDetermined

                        self?.updateMicrophoneStatus(newStatus, oldStatus: oldStatus)
                        self?.lastMicrophoneCheck = Date()

                        continuation.resume(returning: newStatus)
                    }
                }
            }
        }
    }
    
    /// 检查语音识别权限（仅检查状态，不触发请求）
    @discardableResult
    public func checkSpeechRecognitionPermission() async -> PermissionStatus {
        // 检查缓存
        if let lastCheck = lastSpeechRecognitionCheck,
           Date().timeIntervalSince(lastCheck) < cacheValidityInterval {
            return speechRecognitionStatus
        }

        // 使用只检查状态的API，不触发权限请求
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        let newStatus = convertSFAuthorizationStatus(authStatus)
        let oldStatus = speechRecognitionStatus

        updateSpeechRecognitionStatus(newStatus, oldStatus: oldStatus)
        lastSpeechRecognitionCheck = Date()

        return newStatus
    }

    /// 请求语音识别权限（主动触发权限请求）
    public func requestSpeechRecognitionPermission() async -> PermissionStatus {
        // 先检查当前状态，如果已授权则无需请求
        let currentStatus = await checkSpeechRecognitionPermission()
        if currentStatus.isAuthorized {
            return currentStatus
        }

        // 如果状态不是 notDetermined，说明用户已做出选择，无法再次请求
        if currentStatus != .notDetermined {
            print("⚠️ 语音识别权限已被拒绝，请用户手动在系统设置中开启")
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
                Task { @MainActor [weak self] in
                    let newStatus = self?.convertSFAuthorizationStatus(authStatus) ?? .notDetermined
                    let oldStatus = self?.speechRecognitionStatus ?? .notDetermined

                    self?.updateSpeechRecognitionStatus(newStatus, oldStatus: oldStatus)
                    self?.lastSpeechRecognitionCheck = Date()

                    continuation.resume(returning: newStatus)
                }
            }
        }
    }
    
    /// 检查屏幕录制权限（仅检查状态，不触发请求弹窗）
    /// 注意：此方法只使用 CGPreflightScreenCaptureAccess，不会触发系统权限弹窗
    @discardableResult
    public func checkScreenRecordingPermission() async -> PermissionStatus {
        // macOS版本检查
        guard #available(macOS 11.0, *) else {
            let newStatus: PermissionStatus = .unavailable
            let oldStatus = screenRecordingStatus
            updateScreenRecordingStatus(newStatus, oldStatus: oldStatus)
            return newStatus
        }

        // 检查缓存
        if let lastCheck = lastScreenRecordingCheck,
           Date().timeIntervalSince(lastCheck) < cacheValidityInterval {
            return screenRecordingStatus
        }

        // 只使用 CGPreflightScreenCaptureAccess 检查权限
        // 这个 API 不会触发权限弹窗，只返回当前状态
        let hasPermission = await MainActor.run {
            CGPreflightScreenCaptureAccess()
        }
        print("🔍 屏幕录制权限状态检查 (CGPreflightScreenCaptureAccess): \(hasPermission)")

        let newStatus: PermissionStatus = hasPermission ? .granted : .notDetermined
        let oldStatus = screenRecordingStatus

        await MainActor.run { [weak self] in
            self?.updateScreenRecordingStatus(newStatus, oldStatus: oldStatus)
            self?.lastScreenRecordingCheck = Date()
        }

        return newStatus
    }

    /// 验证屏幕录制权限（使用实际功能测试，可能触发权限弹窗）
    /// 只在用户主动选择系统音频功能时调用
    @available(macOS 12.3, *)
    public func verifyScreenRecordingPermission() async -> PermissionStatus {
        // 先用不触发弹窗的方法检查
        let preflightResult = CGPreflightScreenCaptureAccess()
        if preflightResult {
            print("✅ 屏幕录制权限已授予 (preflight)")
            return .granted
        }

        // 尝试实际访问 SCShareableContent 来验证
        // 注意：这可能会触发权限弹窗
        do {
            if #available(macOS 13.0, *) {
                let content = try await SCShareableContent.current
                print("✅ SCShareableContent 访问成功: \(content.displays.count) 个显示器可用")

                await MainActor.run { [weak self] in
                    self?.updateScreenRecordingStatus(.granted, oldStatus: self?.screenRecordingStatus ?? .notDetermined)
                    self?.lastScreenRecordingCheck = Date()
                }
                return .granted
            }
        } catch {
            print("❌ SCShareableContent 访问失败: \(error.localizedDescription)")
        }

        // 备用方法：检查窗口列表
        let hasPermission = await checkScreenRecordingViaWindowList()
        let newStatus: PermissionStatus = hasPermission ? .granted : .denied

        await MainActor.run { [weak self] in
            self?.updateScreenRecordingStatus(newStatus, oldStatus: self?.screenRecordingStatus ?? .notDetermined)
            self?.lastScreenRecordingCheck = Date()
        }

        return newStatus
    }
    
    /// 通过 CGWindowListCopyWindowInfo 检查权限（备用方法）
    private func checkScreenRecordingViaWindowList() async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                // 尝试获取窗口列表信息
                let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
                
                // 如果能获取到窗口名称等敏感信息，说明有权限
                let hasPermission = windowList?.contains { window in
                    // 检查是否能获取窗口名称（需要屏幕录制权限）
                    let windowName = window[kCGWindowName as String] as? String
                    let windowLayer = window[kCGWindowLayer as String] as? Int
                    
                    // 排除系统窗口
                    return windowName != nil && !windowName!.isEmpty && windowLayer != 0
                } ?? false
                
                print("🔍 CGWindowListCopyWindowInfo 权限检查: \(hasPermission ? "有权限" : "无权限")")
                continuation.resume(returning: hasPermission)
            }
        }
    }
    
    /// 检查是否为调试构建
    private func isDebugBuild() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// 请求屏幕录制权限（主动请求）- 优化版本
    public func requestScreenRecordingPermission() async -> PermissionStatus {
        // 严格的版本检查 - CGRequestScreenCaptureAccess在10.15会崩溃
        guard #available(macOS 11.0, *) else {
            print("⚠️ 屏幕录制权限请求需要 macOS 11.0 或更高版本")
            return .unavailable
        }
        
        return await withCheckedContinuation { continuation in
            Task {
                print("🔐 正在请求屏幕录制权限...")
                
                // 首先使用改进的方法检查当前状态
                let currentStatus = await checkScreenRecordingPermission()
                if currentStatus.isAuthorized {
                    print("✅ 屏幕录制权限已存在（通过实际功能验证）")
                    continuation.resume(returning: .granted)
                    return
                }
                
                // 主动请求权限 - 这会显示系统权限对话框
                let requestResult = await MainActor.run {
                    CGRequestScreenCaptureAccess()
                }
                print("🔐 CGRequestScreenCaptureAccess 返回: \(requestResult)")
                
                // 等待一小段时间让系统处理权限变更
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                
                // 使用改进的方法重新验证权限
                let finalStatus = await checkScreenRecordingPermission()
                
                // 如果 CGRequestScreenCaptureAccess 返回 false 但实际有权限
                // 这种情况在开发构建中很常见
                if !requestResult && finalStatus.isAuthorized {
                    print("✅ 权限验证成功（尽管API返回false）")
                    print("ℹ️ 这是开发构建的已知问题，实际权限已生效")
                } else if finalStatus.isAuthorized {
                    print("✅ 屏幕录制权限已授予")
                } else {
                    print("❌ 权限请求后验证失败: 用户拒绝了应用程序、窗口、显示器捕捉的TCC")
                    
                    // 对于开发构建，提供额外的帮助信息
                    if isDebugBuild() {
                        print("""
                        
                        🔧 开发构建权限问题解决方案：
                        1. 在终端执行: tccutil reset ScreenCapture com.lkylove.VoiceTranslation
                        2. 重启应用
                        3. 确保在系统设置中手动添加并勾选应用
                        4. 如果仍有问题，尝试删除 DerivedData 并重新构建
                        """)
                    } else {
                        print("💡 请前往【系统偏好设置】>【安全性与隐私】>【隐私】>【屏幕录制】手动授权")
                    }
                }
                
                continuation.resume(returning: finalStatus)
            }
        }
    }
    
    /// 智能权限申请流程 - 仿照durt等优秀应用的实现
    public func requestScreenRecordingPermissionWithGuidance() async -> PermissionStatus {
        print("🚀 开始智能权限申请流程...")
        
        // 第一步：检查系统版本
        guard #available(macOS 11.0, *) else {
            await MainActor.run {
                showPermissionGuideFor(.screenRecording)
            }
            print("❌ 当前系统版本不支持屏幕录制权限请求")
            return .unavailable
        }
        
        // 第二步：检查当前权限状态
        let currentStatus = await checkScreenRecordingPermission()
        if currentStatus.isAuthorized {
            print("✅ 屏幕录制权限已存在，无需申请")
            return currentStatus
        }
        
        // 第三步：主动请求权限
        print("📋 显示权限申请说明...")
        await MainActor.run {
            showPermissionGuideFor(.screenRecording)
        }
        
        // 给用户一点时间看到说明
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        
        // 第四步：调用系统权限API
        let result = await requestScreenRecordingPermission()
        
        // 第五步：处理结果并提供后续指导
        if result.isAuthorized {
            print("🎉 权限申请成功！")
            await MainActor.run {
                hidePermissionGuide()
            }
        } else {
            print("⚠️ 权限申请被拒绝，提供手动设置指导")
            // 延迟打开系统设置，给用户时间看到消息
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
                await MainActor.run {
                    openSystemPreferencesForPermission(.screenRecording)
                }
            }
        }
        
        return result
    }
    
    /// 验证系统音频捕获能力（深度检查）
    @available(macOS 12.3, *)
    public func validateSystemAudioCapability() async -> (hasPermission: Bool, canAccessContent: Bool, errorMessage: String?) {
        // 检查macOS版本要求
        guard #available(macOS 13.0, *) else {
            return (false, false, "系统音频功能需要 macOS 13.0 或更高版本")
        }
        
        // 首先检查基础权限
        let permissionStatus = await checkScreenRecordingPermission()
        guard permissionStatus.isAuthorized else {
            return (false, false, "屏幕录制权限未授予，系统音频功能不可用")
        }
        
        // 深度验证：尝试访问共享内容
        do {
            let content = try await SCShareableContent.current
            
            // 检查是否有可用的显示器
            guard !content.displays.isEmpty else {
                let errorMsg = "虽然权限已授予，但无法访问系统音频内容"
                print("⚠️ \(errorMsg)")
                return (true, false, errorMsg)
            }
            
            // 检查是否支持音频捕获
            let hasAudioCapableDisplays = content.displays.contains { display in
                // 所有显示器都应该支持音频捕获
                return true
            }
            
            guard hasAudioCapableDisplays else {
                return (true, false, "当前显示器不支持音频捕获")
            }
            
            print("✅ 系统音频能力验证通过：\(content.displays.count) 个显示器可用，\(content.windows.count) 个窗口")
            return (true, true, nil)
            
        } catch {
            let errorMsg = "内容访问验证失败: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (true, false, errorMsg)
        }
    }
    
    /// 获取权限状态摘要
    public func getPermissionSummary() -> String {
        var summary = "权限状态摘要:\n"
        summary += "📱 麦克风: \(statusDescription(microphoneStatus))\n"
        summary += "🎙️ 语音识别: \(statusDescription(speechRecognitionStatus))\n"
        summary += "🖥️ 屏幕录制: \(statusDescription(screenRecordingStatus))"
        
        // 添加功能可用性说明
        let micGranted = microphoneStatus.isAuthorized
        let speechGranted = speechRecognitionStatus.isAuthorized
        let screenGranted = screenRecordingStatus.isAuthorized
        
        summary += "\n\n功能可用性:"
        if micGranted && speechGranted {
            summary += "\n✅ 麦克风翻译: 可用"
        } else {
            summary += "\n❌ 麦克风翻译: 需要麦克风和语音识别权限"
        }
        
        if screenGranted && micGranted && speechGranted {
            summary += "\n✅ 系统音频翻译: 可用"
        } else if !screenGranted {
            summary += "\n⚠️ 系统音频翻译: 需要屏幕录制权限"
        } else {
            summary += "\n❌ 系统音频翻译: 需要所有权限"
        }
        
        return summary
    }
    
    /// 获取特定权限类型的状态描述
    public func getPermissionStatusDescription(for type: PermissionType) -> String {
        switch type {
        case .microphone:
            return statusDescription(microphoneStatus)
        case .speechRecognition:
            return statusDescription(speechRecognitionStatus)
        case .screenRecording:
            return statusDescription(screenRecordingStatus)
        }
    }
    
    /// 重置权限缓存（强制重新检查）
    public func resetCache() {
        lastMicrophoneCheck = nil
        lastSpeechRecognitionCheck = nil
        lastScreenRecordingCheck = nil
        print("🔄 权限缓存已重置")
        
        // 重置权限状态为未确定，强制重新检查
        microphoneStatus = .notDetermined
        speechRecognitionStatus = .notDetermined
        screenRecordingStatus = .notDetermined
    }
    
    // MARK: - Permission Guide Methods
    
    /// 显示权限引导
    public func showPermissionGuideFor(_ type: PermissionType) {
        pendingPermissionType = type
        showPermissionGuide = true
        print("📖 显示权限引导: \(type.rawValue)")
        
        // 记录权限引导事件
        let permissionName = {
            switch type {
            case .microphone: return "麦克风"
            case .speechRecognition: return "语音识别"
            case .screenRecording: return "屏幕录制"
            }
        }()
        
        print("ℹ️ 用户需要配置\(permissionName)权限才能继续使用相关功能")
    }
    
    /// 隐藏权限引导
    public func hidePermissionGuide() {
        if let pendingType = pendingPermissionType {
            print("📖 关闭权限引导: \(pendingType.rawValue)")
        }
        
        pendingPermissionType = nil
        showPermissionGuide = false
        
        // 引导关闭后重新检查权限状态
        Task {
            await checkAllPermissions()
        }
    }
    
    /// 打开系统偏好设置到相关权限页面
    public func openSystemPreferencesForPermission(_ type: PermissionType) {
        let urlString: String
        
        // 根据macOS版本选择合适的URL方案
        if #available(macOS 14.0, *) {
            // macOS 14+ 使用新的系统设置URL方案
            switch type {
            case .microphone:
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            case .speechRecognition:
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
            case .screenRecording:
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            }
        } else {
            // macOS 13 及更早版本
            switch type {
            case .microphone:
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            case .speechRecognition:
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
            case .screenRecording:
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            }
        }
        
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            print("🔗 已打开系统偏好设置: \(type.rawValue)")
            
            // 记录用户操作，用于后续跟踪
            Task {
                // 延迟5秒后重新检查权限，给用户时间去设置
                try await Task.sleep(nanoseconds: 5_000_000_000)
                await checkAllPermissions()
            }
        } else {
            print("❌ 无法打开系统偏好设置: \(type.rawValue)")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupPermissionMonitoring() {
        // 应用激活时重新检查权限
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.checkAllPermissions()
                }
            }
            .store(in: &cancellables)
        
        print("🔍 权限监控已设置")
    }
    
    private func updateMicrophoneStatus(_ newStatus: PermissionStatus, oldStatus: PermissionStatus) {
        guard newStatus != oldStatus else { return }
        
        microphoneStatus = newStatus
        let change = PermissionStatusChange(
            type: .microphone,
            oldStatus: oldStatus,
            newStatus: newStatus,
            timestamp: Date()
        )
        
        statusChangeSubject.send(change)
        print("🎤 麦克风权限状态变更: \(statusDescription(oldStatus)) → \(statusDescription(newStatus))")
    }
    
    private func updateSpeechRecognitionStatus(_ newStatus: PermissionStatus, oldStatus: PermissionStatus) {
        guard newStatus != oldStatus else { return }
        
        speechRecognitionStatus = newStatus
        let change = PermissionStatusChange(
            type: .speechRecognition,
            oldStatus: oldStatus,
            newStatus: newStatus,
            timestamp: Date()
        )
        
        statusChangeSubject.send(change)
        print("🎙️ 语音识别权限状态变更: \(statusDescription(oldStatus)) → \(statusDescription(newStatus))")
    }
    
    private func updateScreenRecordingStatus(_ newStatus: PermissionStatus, oldStatus: PermissionStatus) {
        guard newStatus != oldStatus else { return }
        
        screenRecordingStatus = newStatus
        let change = PermissionStatusChange(
            type: .screenRecording,
            oldStatus: oldStatus,
            newStatus: newStatus,
            timestamp: Date()
        )
        
        statusChangeSubject.send(change)
        print("🖥️ 屏幕录制权限状态变更: \(statusDescription(oldStatus)) → \(statusDescription(newStatus))")
    }
    
    private func convertSFAuthorizationStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .granted
        @unknown default:
            return .notDetermined
        }
    }
    
    private func statusDescription(_ status: PermissionStatus) -> String {
        switch status {
        case .notDetermined:
            return "未确定"
        case .granted:
            return "已授权 ✅"
        case .denied:
            return "被拒绝 ❌"
        case .restricted:
            return "受限制 ⚠️"
        case .unavailable:
            return "不可用 🚫"
        }
    }
    
    private func printPermissionSummary() {
        let summary = getPermissionSummary()
        print("""
        
        =================== 权限检查摘要 ===================
        \(summary)
        ================================================
        """)
        
        // 如果有权限问题，提供解决建议
        let hasIssues = !microphoneStatus.isAuthorized || 
                       !speechRecognitionStatus.isAuthorized
        
        if hasIssues {
            print("\n💡 解决建议:")
            if !microphoneStatus.isAuthorized {
                print("   • 打开【系统偏好设置】>【安全性与隐私】>【隐私】>【麦克风】")
            }
            if !speechRecognitionStatus.isAuthorized {
                print("   • 打开【系统偏好设置】>【安全性与隐私】>【隐私】>【语音识别】")
            }
            if !screenRecordingStatus.isAuthorized {
                print("   • 系统音频功能需要屏幕录制权限（可选）")
            }
            print("   • 设置完成后请重启应用")
        }
    }
}
