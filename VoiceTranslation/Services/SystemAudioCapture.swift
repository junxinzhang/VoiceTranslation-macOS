//
//  SystemAudioCapture.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation
import AVFoundation
import Speech
import ScreenCaptureKit
import CoreGraphics
import Combine
import os.log

// MARK: - Error Types

/// 系统音频捕获专用错误类型
enum SystemAudioError: LocalizedError, Equatable {
    case permissionDenied
    case deviceNotAvailable
    case streamCreationFailed(String)
    case streamConfigurationFailed(String)
    case audioFormatUnsupported
    case streamStartFailed(String)
    case streamUnhealthy
    case systemVersionUnsupported
    case resourceExhausted
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "屏幕录制权限被拒绝"
        case .deviceNotAvailable:
            return "音频设备不可用"
        case .streamCreationFailed(let details):
            return "流创建失败: \(details)"
        case .streamConfigurationFailed(let details):
            return "流配置失败: \(details)"
        case .audioFormatUnsupported:
            return "不支持的音频格式"
        case .streamStartFailed(let details):
            return "流启动失败: \(details)"
        case .streamUnhealthy:
            return "音频流状态不健康"
        case .systemVersionUnsupported:
            return "系统版本不支持"
        case .resourceExhausted:
            return "系统资源耗尽"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .permissionDenied, .systemVersionUnsupported, .audioFormatUnsupported:
            return false
        case .deviceNotAvailable, .streamCreationFailed, .streamConfigurationFailed, .streamStartFailed, .streamUnhealthy, .resourceExhausted:
            return true
        }
    }
    
    var retryDelay: UInt64 {
        switch self {
        case .deviceNotAvailable, .streamUnhealthy:
            return 500_000_000 // 500ms for quick recovery
        case .streamCreationFailed, .streamConfigurationFailed:
            return 1_000_000_000 // 1s for configuration issues
        case .streamStartFailed, .resourceExhausted:
            return 2_000_000_000 // 2s for resource issues
        default:
            return 200_000_000 // 200ms default
        }
    }
}

// MARK: - Performance Metrics

/// 性能指标监控
struct PerformanceMetrics {
    var streamCreationTime: TimeInterval = 0
    var streamStartTime: TimeInterval = 0
    var totalRetryAttempts: Int = 0
    var audioBuffersProcessed: Int = 0
    var audioProcessingErrors: Int = 0
    var lastSuccessfulCapture: Date?
    var averageBufferProcessingTime: TimeInterval = 0
    
    private var bufferProcessingTimes: [TimeInterval] = []
    private let maxStoredTimes = 100
    
    mutating func recordStreamCreation(duration: TimeInterval) {
        streamCreationTime = duration
    }
    
    mutating func recordStreamStart(duration: TimeInterval) {
        streamStartTime = duration
    }
    
    mutating func recordRetryAttempt() {
        totalRetryAttempts += 1
    }
    
    mutating func recordBufferProcessing(duration: TimeInterval, successful: Bool) {
        if successful {
            audioBuffersProcessed += 1
            lastSuccessfulCapture = Date()
            
            bufferProcessingTimes.append(duration)
            if bufferProcessingTimes.count > maxStoredTimes {
                bufferProcessingTimes.removeFirst()
            }
            
            averageBufferProcessingTime = bufferProcessingTimes.reduce(0, +) / Double(bufferProcessingTimes.count)
        } else {
            audioProcessingErrors += 1
        }
    }
    
    func getHealthScore() -> Double {
        let totalOperations = audioBuffersProcessed + audioProcessingErrors
        guard totalOperations > 0 else { return 1.0 }
        
        let successRate = Double(audioBuffersProcessed) / Double(totalOperations)
        let recencyScore: Double
        
        if let lastCapture = lastSuccessfulCapture {
            let timeSinceLastCapture = Date().timeIntervalSince(lastCapture)
            recencyScore = max(0, 1.0 - (timeSinceLastCapture / 30.0)) // 30秒内为满分
        } else {
            recencyScore = 0.0
        }
        
        return (successRate * 0.7) + (recencyScore * 0.3)
    }
    
    func getMetricsReport() -> String {
        return """
        性能指标报告:
        - 流创建时间: \(String(format: "%.3f", streamCreationTime))s
        - 流启动时间: \(String(format: "%.3f", streamStartTime))s
        - 重试次数: \(totalRetryAttempts)
        - 已处理音频缓冲区: \(audioBuffersProcessed)
        - 处理错误: \(audioProcessingErrors)
        - 平均处理时间: \(String(format: "%.3f", averageBufferProcessingTime * 1000))ms
        - 健康评分: \(String(format: "%.2f", getHealthScore() * 100))%
        """
    }
    
    mutating func reset() {
        streamCreationTime = 0
        streamStartTime = 0
        totalRetryAttempts = 0
        audioBuffersProcessed = 0
        audioProcessingErrors = 0
        lastSuccessfulCapture = nil
        averageBufferProcessingTime = 0
        bufferProcessingTimes.removeAll()
    }
}

@available(macOS 12.3, *)
class SystemAudioCapture: NSObject, ObservableObject {
    var audioHeartbeat: AudioHeartbeat?
    
    // MARK: - Configuration
    
    /// 系统音频捕获配置
    private struct CaptureConfig {
        static let maxRetries = 3
        static let streamInitDelay: UInt64 = 50_000_000 // 50ms - 减少初始化延迟
        static let retryBaseDelay: UInt64 = 100_000_000 // 100ms - 减少重试延迟
        static let streamStabilizeDelay: UInt64 = 150_000_000 // 150ms - 减少稳定延迟
        static let startStabilizeDelay: UInt64 = 50_000_000 // 50ms - 减少启动后延迟
        static let permissionWaitDelay: UInt64 = 1_000_000_000 // 1s
        static let streamMaxAge: TimeInterval = 60.0 // 60秒 - 延长流生命周期
        static let sampleRate: Double = 48000.0
        static let channelCount: AVAudioChannelCount = 2
        static let targetSampleRate: Double = 16000.0
        static let targetChannelCount: AVAudioChannelCount = 1
        static let logFrequency = 10 // 每10秒输出一次状态日志
        static let audioQualityLogFrequency = 5 // 每5秒输出一次音频处理日志
    }
    
    // MARK: - Logging
    
    private let logger = Logger(subsystem: "com.voicetranslation.audio", category: "SystemAudioCapture")
    
    // MARK: - Performance Monitoring
    
    private var performanceMetrics = PerformanceMetrics()
    
    // MARK: - Properties
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var audioFormat: AVAudioFormat?
    private let queue = DispatchQueue(label: "SystemAudioCapture", qos: .userInteractive)
    private var didFallbackToRawAppend = false
    
    // 添加一个强引用来保持流对象
    private var currentStream: SCStream?
    
    // 统一状态管理 - 只使用 StreamState actor
    private actor StreamState {
        private var _stream: SCStream?
        private var _configuration: SCStreamConfiguration?
        private var _filter: SCContentFilter?
        var isInitialized = false
        var creationTime: Date?
        var isHealthy = true
        
        // 使用计算属性确保流不会意外被释放
        var stream: SCStream? {
            return _stream
        }
        
        func updateStream(_ newStream: SCStream?, configuration: SCStreamConfiguration?, filter: SCContentFilter?) {
            self._stream = newStream
            self._configuration = configuration
            self._filter = filter
            self.creationTime = newStream != nil ? Date() : nil
            // 立即标记为已初始化和健康
            self.isInitialized = newStream != nil
            self.isHealthy = newStream != nil
        }
        
        func markInitialized() {
            self.isInitialized = true
        }
        
        func markUnhealthy() {
            self.isHealthy = false
        }
        
        func getStream() -> SCStream? {
            return _stream
        }
        
        func getStreamInfo() -> (stream: SCStream?, isInitialized: Bool, age: TimeInterval?, isHealthy: Bool) {
            let age = creationTime?.timeIntervalSinceNow
            return (_stream, isInitialized, age != nil ? -age! : nil, isHealthy)
        }
        
        func getSavedConfiguration() -> (configuration: SCStreamConfiguration?, filter: SCContentFilter?) {
            return (_configuration, _filter)
        }
        
        func reset() {
            _stream = nil
            _configuration = nil
            _filter = nil
            isInitialized = false
            creationTime = nil
            isHealthy = false
        }
        
        func validateHealth() -> Bool {
            guard let _ = _stream, isInitialized, isHealthy else { return false }
            
            // 检查流年龄 - 延长到60秒，避免过早判定为不健康
            if let age = creationTime?.timeIntervalSinceNow, -age > 60.0 {
                return false
            }
            
            return true
        }
    }
    
    private let streamState = StreamState()
    
    // 状态管理
    @Published public private(set) var isCapturing = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var permissionStatus: String = "未确定"
    
    // MARK: - Audio Capture Methods
    
    /// 获取当前权限状态 - 改进版，使用实际功能测试
    var screenRecordingPermissionStatus: Bool {
        // 使用同步方式检查权限
        var hasPermission = CGPreflightScreenCaptureAccess()
        
        // 对于开发构建，额外验证
        if !hasPermission && isDebugBuild() {
            // 尝试通过窗口列表检查权限（同步方法）
            let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
            hasPermission = windowList?.contains { window in
                let windowName = window[kCGWindowName as String] as? String
                return windowName != nil && !windowName!.isEmpty
            } ?? false
        }
        
        return hasPermission
    }
    
    /// 检查屏幕录制权限是否可用
    var hasScreenRecordingPermission: Bool {
        return screenRecordingPermissionStatus
    }
    
    /// 检查是否为调试构建
    private func isDebugBuild() -> Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// 诊断权限问题（公开方法）
    /// 注意：此方法仅使用 CGPreflightScreenCaptureAccess，不会触发权限弹窗
    public func diagnosePermissions() async -> String {
        var report = "🔍 屏幕录制权限诊断报告\n"
        report += String(repeating: "=", count: 40) + "\n\n"

        // 1. Bundle ID 检查
        let bundleId = Bundle.main.bundleIdentifier ?? "未知"
        report += "📦 Bundle ID: \(bundleId)\n"

        // 2. CGPreflightScreenCaptureAccess 检查
        // 只使用这个 API，不会触发权限弹窗
        let preflightStatus = CGPreflightScreenCaptureAccess()
        report += "📊 屏幕录制权限状态: \(preflightStatus ? "✅ 已授权" : "❌ 未授权")\n"

        // 注意：不再使用 SCShareableContent.current 进行实际测试
        // 因为这会触发权限弹窗

        // 3. 解决方案
        report += "\n💡 解决方案:\n"
        if !preflightStatus {
            report += "1. 完全退出 VoiceTranslation 应用\n"
            report += "2. 打开【系统设置】→【隐私与安全性】→【屏幕录制】\n"
            report += "3. 找到 VoiceTranslation (Bundle ID: \(bundleId))\n"
            report += "4. 如果已勾选，先取消勾选，等待2秒，再重新勾选\n"
            report += "5. 如果未出现在列表中，尝试重新构建应用\n"
            report += "6. 重新启动 VoiceTranslation 应用\n"
            report += "\n🔄 如果问题仍然存在:\n"
            report += "• 重启 macOS 系统\n"
            report += "• 运行: tccutil reset ScreenCapture com.voicetranslation.macos\n"
        } else {
            report += "✅ 权限已正确配置，系统音频捕获应该可以正常工作\n"
        }

        logger.info("\(report)")
        return report
    }
    
    /// 强制刷新权限状态
    /// 注意：此方法仅使用 CGPreflightScreenCaptureAccess，不会触发权限弹窗
    public func forceRefreshPermissions() async -> Bool {
        logger.info("🔄 强制刷新权限状态...")

        // 清理当前流
        await cleanupResources()

        // 等待一段时间让系统刷新
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // 重新检查权限 - 只使用不触发弹窗的 API
        let hasPermission = CGPreflightScreenCaptureAccess()
        logger.info("📊 权限刷新后状态: \(hasPermission ? "已授权" : "未授权")")
        return hasPermission
    }
    
    func setupSystemAudioCapture(with recognitionRequest: SFSpeechAudioBufferRecognitionRequest) async throws {
        self.recognitionRequest = recognitionRequest
        
        logger.info("开始设置系统音频捕获 - 使用ScreenCaptureKit")
        
        // 检查系统版本支持
        guard #available(macOS 13.0, *) else {
            let error = SystemAudioError.systemVersionUnsupported
            await MainActor.run {
                self.lastError = error.errorDescription
                self.permissionStatus = "系统版本不支持"
            }
            logger.error("版本检查失败: \(error.errorDescription ?? "未知错误")")
            throw error
        }
        
        // 权限检查和请求
        try await requestPermissionIfNeeded()
        
        // 设置音频格式
        try setupAudioFormat()
        
        // 设置ScreenCaptureKit流配置
        try await setupScreenCaptureKit()
        
        logger.info("系统音频捕获设置完成")
    }
    
    /// 检查权限（仅检查，不触发弹窗）
    private func requestPermissionIfNeeded() async throws {
        logger.info("🔍 开始权限检查...")

        // 只使用 CGPreflightScreenCaptureAccess 检查权限
        // 这个 API 不会触发弹窗
        let hasPermission = CGPreflightScreenCaptureAccess()
        logger.info("📊 屏幕录制权限状态: \(hasPermission ? "已授权" : "未授权")")

        if hasPermission {
            logger.info("✅ 屏幕录制权限已授予")
            await MainActor.run {
                self.permissionStatus = "已授权"
            }
            return
        }

        // 未授权时，主动请求系统弹窗
        logger.info("🪟 未授权，正在请求屏幕录制权限弹窗...")
        let granted = await MainActor.run { CGRequestScreenCaptureAccess() }
        logger.info("🪟 屏幕录制权限请求结果: \(granted ? "已授权" : "被拒绝")")

        guard granted else {
            // 权限不足，抛出错误让调用方处理
            let error = SystemAudioError.permissionDenied
            await MainActor.run {
                self.lastError = error.errorDescription
                self.permissionStatus = "未授权"
            }
            logger.info("❌ 屏幕录制权限不足，请在系统设置中手动授权")
            
            logger.error("屏幕录制权限被拒绝")
            logPermissionGuidance()
            throw error
        }

        // 用户刚刚授权，更新状态
        await MainActor.run {
            self.lastError = nil
            self.permissionStatus = "已授权"
        }
        logger.info("✅ 用户已授权屏幕录制权限")
    }
    
    /// 权限检查方法（仅检查状态，不触发弹窗）
    private func checkScreenRecordingPermissionImproved() async -> Bool {
        // 只使用 CGPreflightScreenCaptureAccess 检查权限
        // 这个 API 不会触发权限弹窗
        let cgPreflightResult = CGPreflightScreenCaptureAccess()
        logger.info("📊 屏幕录制权限检查 (CGPreflightScreenCaptureAccess): \(cgPreflightResult)")
        return cgPreflightResult
    }
    
    /// 设置音频格式
    private func setupAudioFormat() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: CaptureConfig.sampleRate,
            channels: CaptureConfig.channelCount,
            interleaved: false
        ) else {
            let error = SystemAudioError.audioFormatUnsupported
            Task { @MainActor in
                self.lastError = error.errorDescription
            }
            logger.error("音频格式创建失败")
            throw error
        }
        
        self.audioFormat = format
        logger.info("音频格式设置: \(CaptureConfig.sampleRate)Hz, \(CaptureConfig.channelCount)声道")
    }
    
    @available(macOS 13.0, *)
    private func setupScreenCaptureKit() async throws {
        let startTime = Date()
        do {
            logger.info("开始设置ScreenCaptureKit流配置")
            
            // 获取可共享内容
            let content = try await SCShareableContent.current
            guard !content.displays.isEmpty else {
                logger.error("无法访问显示器内容，可能是权限问题")
                throw SystemAudioError.deviceNotAvailable
            }
            
            logger.info("发现 \(content.displays.count) 个显示器, \(content.windows.count) 个窗口")
            
            // 使用第一个显示器
            guard let display = content.displays.first else {
                logger.error("未找到可用的显示器")
                throw SystemAudioError.deviceNotAvailable
            }
            
            // 创建过滤器 - 排除当前应用窗口避免反馈
            let excludeWindows = content.windows.filter { window in
                guard let bundleId = window.owningApplication?.bundleIdentifier else { return false }
                return bundleId.contains("VoiceTranslation")
            }
            
            if !excludeWindows.isEmpty {
                logger.info("排除 \(excludeWindows.count) 个应用窗口避免反馈")
            }
            
            let filter = SCContentFilter(display: display, excludingWindows: excludeWindows)
            let configuration = createStreamConfiguration()
            
            // 创建并初始化流
            try await createAndConfigureStream(filter: filter, configuration: configuration)
            
            let duration = Date().timeIntervalSince(startTime)
            performanceMetrics.recordStreamCreation(duration: duration)
            logger.info("ScreenCaptureKit流配置完成，耗时: \(String(format: "%.3f", duration))s")
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            let wrappedError: SystemAudioError
            if let systemError = error as? SystemAudioError {
                wrappedError = systemError
            } else {
                wrappedError = SystemAudioError.streamConfigurationFailed(error.localizedDescription)
            }
            
            await MainActor.run {
                self.lastError = wrappedError.errorDescription
            }
            logger.error("ScreenCaptureKit设置失败 (耗时: \(String(format: "%.3f", duration))s): \(wrappedError.errorDescription ?? "未知错误")")
            throw wrappedError
        }
    }
    
    /// 创建流配置
    @available(macOS 12.3, *)
    private func createStreamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        
        // 重要：设置合理的视频捕获参数，不要设置为1x1
        // 某些macOS版本在1x1时会导致流不稳定
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 FPS足够
        configuration.showsCursor = false
        
        // 优化性能 - 使用最简单的像素格式
        if #available(macOS 14.0, *) {
            configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            configuration.scalesToFit = false
        }
        
        // 音频捕获配置（需要 macOS 13.0+）
        if #available(macOS 13.0, *) {
            // 关键配置：确保音频捕获正确设置
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = Int(CaptureConfig.sampleRate)
            configuration.channelCount = Int(CaptureConfig.channelCount)
            
            // macOS 14+ 特定优化
            if #available(macOS 14.0, *) {
                // 在 macOS 14 中，可能需要显式设置音频队列大小
                // 这些是内部属性，可能需要通过setValue访问
            }
            
            // macOS 15+ 麦克风支持
            if #available(macOS 15.0, *) {
                // configuration.captureMicrophone = false // 确保不捕获麦克风
            }
            
            logger.info("音频配置: capturesAudio=\(configuration.capturesAudio), sampleRate=\(configuration.sampleRate)Hz, channelCount=\(configuration.channelCount)声道, excludesCurrentProcessAudio=\(configuration.excludesCurrentProcessAudio)")
        }
        
        return configuration
    }
    
    /// 创建并配置流
    @available(macOS 13.0, *)
    private func createAndConfigureStream(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws {
        // 重要：不要在主线程创建流，避免UI阻塞
        // 直接在当前上下文创建流，delegate参数传nil，后续用addStreamOutput
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        
        // 立即保存强引用 - 防止ARC回收
        self.currentStream = newStream
        
        logger.info("SCStream创建成功")
        
        // 立即保存流状态到actor
        await streamState.updateStream(newStream, configuration: configuration, filter: filter)
        
        // 关键：先等待一段时间让流完全初始化
        // 这是避免"stream is nil"错误的关键
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms - 增加初始化时间
        
        // 添加音频输出处理器
        do {
            // 重要：使用专用的DispatchQueue处理音频，而不是self的queue
            let audioQueue = DispatchQueue(label: "com.voicetranslation.audio.output", qos: .userInteractive, attributes: .concurrent)
            
            // 添加输出处理器，使用专门的队列
            try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
            logger.info("音频输出处理器添加成功")
            
            // 再等待一段时间确保输出处理器完全附加
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // 标记流已完全初始化
            await streamState.markInitialized()
            logger.info("流初始化完成")
            
        } catch {
            self.currentStream = nil
            await streamState.reset()
            logger.error("添加音频输出处理器失败: \(error.localizedDescription)")
            throw SystemAudioError.streamConfigurationFailed(error.localizedDescription)
        }
    }
    
    func start() async throws {
        try await startWithRetry()
    }

    /// 更新识别请求（用于重启识别任务）
    func updateRecognitionRequest(_ request: SFSpeechAudioBufferRecognitionRequest) {
        recognitionRequest = request
    }
    
    /// 带重试机制的启动方法
    private func startWithRetry() async throws {
        var lastError: SystemAudioError?
        let startTime = Date()
        
        for attempt in 1...CaptureConfig.maxRetries {
            do {
                try await performStart(attempt: attempt)
                let duration = Date().timeIntervalSince(startTime)
                performanceMetrics.recordStreamStart(duration: duration)
                return // 成功启动
            } catch {
                performanceMetrics.recordRetryAttempt()
                
                let systemError: SystemAudioError
                if let audioError = error as? SystemAudioError {
                    systemError = audioError
                } else if isStreamNilError(error) {
                    systemError = SystemAudioError.streamUnhealthy
                } else {
                    systemError = SystemAudioError.streamStartFailed(error.localizedDescription)
                }
                
                lastError = systemError
                logger.warning("启动尝试 \(attempt)/\(CaptureConfig.maxRetries) 失败: \(systemError.errorDescription ?? "未知错误")")
                
                // 根据错误类型决定重试策略
                if systemError.isRetryable && attempt < CaptureConfig.maxRetries {
                    switch systemError {
                    case .streamUnhealthy:
                        logger.info("检测到流失效，尝试重建流")
                        if #available(macOS 13.0, *) {
                            try await recreateStream()
                        }
                        // 等待流稳定
                        try await Task.sleep(nanoseconds: CaptureConfig.streamStabilizeDelay)
                    default:
                        // 使用错误特定的延迟
                        let delay = systemError.retryDelay
                        try await Task.sleep(nanoseconds: delay)
                    }
                } else if !systemError.isRetryable {
                    // 不可重试的错误，立即抛出
                    break
                }
            }
        }
        
        // 所有重试都失败
        if let error = lastError {
            await MainActor.run {
                self.isCapturing = false
                self.lastError = "启动失败 (\(CaptureConfig.maxRetries)次重试): \(error.errorDescription ?? "未知错误")"
            }
            throw error
        }
        throw SystemAudioError.resourceExhausted
    }
    
    /// 执行实际的启动操作
    private func performStart(attempt: Int) async throws {
        // 验证流状态
        try await validateStreamState()
        
        // 使用强引用的流对象
        guard let stream = self.currentStream else {
            logger.error("流对象不存在（强引用为nil）")
            throw SystemAudioError.streamUnhealthy
        }
        
        logger.info("启动系统音频捕获流 (尝试 \(attempt))")
        
        // 检查是否已经在捕获
        if isCapturing {
            logger.info("流已在捕获中，跳过启动")
            return
        }
        
        // 重要：在启动前等待一小段时间，确保流完全就绪
        // 这有助于避免"stream is nil"错误
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // 使用async/await方式启动，更稳定
        do {
            // 尝试使用新的async API（如果可用）
            if #available(macOS 14.0, *) {
                try await stream.startCapture()
                logger.info("流启动成功（async方式）")
            } else {
                // 使用传统的completion handler方式
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    stream.startCapture { error in
                        if let error = error {
                            // 特殊处理"stream is nil"错误
                            let errorDesc = error.localizedDescription
                            if errorDesc.lowercased().contains("stream is nil") || 
                               errorDesc.lowercased().contains("the stream is nil") {
                                self.logger.error("检测到'stream is nil'错误，流对象可能已失效")
                                continuation.resume(throwing: SystemAudioError.streamUnhealthy)
                            } else {
                                self.logger.error("流启动失败: \(errorDesc)")
                                continuation.resume(throwing: error)
                            }
                        } else {
                            self.logger.info("流启动回调成功")
                            continuation.resume()
                        }
                    }
                }
            }
        } catch {
            // 如果是"stream is nil"错误，转换为streamUnhealthy以触发重建
            if isStreamNilError(error) {
                throw SystemAudioError.streamUnhealthy
            }
            throw error
        }
        
        // 成功启动，更新状态
        await MainActor.run {
            self.isCapturing = true
            self.lastError = nil
        }
        
        logger.info("系统音频捕获已启动")
        
        // 等待流稳定
        try await Task.sleep(nanoseconds: CaptureConfig.startStabilizeDelay)
    }
    
    /// 验证流状态和健康度
    private func validateStreamState() async throws {
        let streamInfo = await streamState.getStreamInfo()
        
        logger.debug("验证流状态: stream=\(streamInfo.stream != nil), initialized=\(streamInfo.isInitialized), healthy=\(streamInfo.isHealthy)")
        
        guard streamInfo.stream != nil else {
            logger.error("流验证失败: stream为nil")
            throw SystemAudioError.streamUnhealthy
        }
        
        guard streamInfo.isInitialized else {
            logger.error("流验证失败: 流未完全初始化")
            throw SystemAudioError.streamConfigurationFailed("流未完全初始化")
        }
        
        // 使用actor内置的健康检查
        let isHealthy = await streamState.validateHealth()
        guard isHealthy else {
            logger.warning("流健康检查失败，可能需要重建")
            throw SystemAudioError.streamUnhealthy
        }
        
        logger.debug("流状态验证通过")
    }
    
    /// 检查是否是流nil错误
    private func isStreamNilError(_ error: Error) -> Bool {
        let errorDescription = error.localizedDescription.lowercased()
        return errorDescription.contains("stream is nil") || 
               errorDescription.contains("the stream is nil")
    }
    
    /// 重建流
    @available(macOS 13.0, *)
    private func recreateStream() async throws {
        logger.info("开始重建流")
        
        // 获取保存的配置
        let savedConfig = await streamState.getSavedConfiguration()
        
        // 如果没有保存的配置，重新创建
        let configuration: SCStreamConfiguration
        let filter: SCContentFilter
        
        if let savedConfiguration = savedConfig.configuration,
           let savedFilter = savedConfig.filter {
            configuration = savedConfiguration
            filter = savedFilter
            logger.info("使用保存的配置重建流")
        } else {
            logger.info("没有保存的配置，重新创建配置")
            // 重新获取显示内容和创建配置
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else {
                    throw SystemAudioError.deviceNotAvailable
                }
                
                let excludeWindows = content.windows.filter { window in
                    guard let bundleId = window.owningApplication?.bundleIdentifier else { return false }
                    return bundleId.contains("VoiceTranslation")
                }
                
                filter = SCContentFilter(display: display, excludingWindows: excludeWindows)
                configuration = createStreamConfiguration()
            } catch {
                logger.error("重新创建配置失败: \(error.localizedDescription)")
                throw SystemAudioError.streamConfigurationFailed(error.localizedDescription)
            }
        }
        
        // 停止并清理旧流
        if let oldStream = currentStream {
            logger.info("停止旧流")
            await withCheckedContinuation { continuation in
                oldStream.stopCapture { _ in
                    // 忽略停止错误
                    continuation.resume()
                }
            }
        }
        
        // 清理旧流强引用
        currentStream = nil
        
        // 清理旧流状态
        await streamState.reset()
        
        // 等待一段时间让系统完全释放资源
        try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        
        // 重新创建流
        try await createAndConfigureStream(filter: filter, configuration: configuration)
        
        logger.info("流重建完成")
    }
    
    /// 同步版本（兼容性保留）- 已废弃
    func startSync() throws {
        logger.warning("调用了已废弃的同步版本start()，请使用异步版本")
        Task {
            do {
                try await start()
            } catch {
                Task { @MainActor in
                    self.lastError = "启动失败: \(error.localizedDescription)"
                    self.isCapturing = false
                }
            }
        }
    }
    
    func stop() {
        Task {
            await stopAsync()
        }
    }
    
    private func stopAsync() async {
        // 检查是否在捕获中
        guard isCapturing else {
            logger.info("流未在捕获中，跳过停止操作")
            await cleanupResources()
            return
        }
        
        // 立即更新状态，避免重复调用
        await MainActor.run {
            self.isCapturing = false
        }
        
        // 获取当前流并停止
        let streamInfo = await streamState.getStreamInfo()
        if let stream = streamInfo.stream {
            await withCheckedContinuation { continuation in
                stream.stopCapture { error in
                    if let error = error {
                        // 忽略"已经停止"的错误
                        let nsError = error as NSError
                        if nsError.code == -3808 || 
                           error.localizedDescription.contains("已经停止") || 
                           error.localizedDescription.contains("already stopped") {
                            // 正常的已停止状态
                        } else {
                            self.logger.warning("停止捕获时出现错误: \(error.localizedDescription)")
                        }
                    }
                    continuation.resume()
                }
            }
            
            logger.info("系统音频捕获已停止")
        }
        
        // 清理资源
        await cleanupResources()
    }
    
    /// 清理所有资源
    private func cleanupResources() async {
        // 清理识别请求
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // 清理流强引用
        currentStream = nil
        
        // 清理流状态
        await streamState.reset()
        
        logger.info("资源清理完成")
    }
}

// MARK: - Audio Buffer Processing Extension

@available(macOS 12.3, *)
extension SystemAudioCapture {
    
    private func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        let startTime = Date()
        var processingSuccessful = false

        defer {
            let duration = Date().timeIntervalSince(startTime)
            performanceMetrics.recordBufferProcessing(duration: duration, successful: processingSuccessful)
        }

        guard let recognitionRequest = recognitionRequest,
              let audioFormat = audioFormat else {
            logger.warning("语音识别请求或音频格式未初始化")
            return
        }

        // 从CMSampleBuffer创建AVAudioPCMBuffer
        guard let audioBuffer = createAudioBuffer(from: sampleBuffer, format: audioFormat) else {
            return // 失败时静默处理，避免日志污染
        }

        // 调试：检查音频电平
        let buffersProcessed = performanceMetrics.audioBuffersProcessed
        if buffersProcessed < 10 || buffersProcessed % 100 == 0 {
            if let floatData = audioBuffer.floatChannelData {
                var maxLevel: Float = 0
                var sumLevel: Float = 0
                let frameCount = Int(audioBuffer.frameLength)
                for i in 0..<min(frameCount, 1000) {
                    let sample = abs(floatData[0][i])
                    maxLevel = max(maxLevel, sample)
                    sumLevel += sample
                }
                let avgLevel = frameCount > 0 ? sumLevel / Float(min(frameCount, 1000)) : 0
                print("🎤 [ScreenCaptureKit] 音频电平: max=\(String(format: "%.6f", maxLevel)), avg=\(String(format: "%.6f", avgLevel)), frames=\(frameCount) (缓冲区 #\(buffersProcessed))")
            }
        }

        // 转换音频格式为语音识别适用格式（16kHz单声道）
        let outputFrameLength: AVAudioFrameCount
        if !didFallbackToRawAppend, let convertedBuffer = convertAudioFormat(audioBuffer) {
            audioHeartbeat?.observe(convertedBuffer)
            recognitionRequest.append(convertedBuffer)
            outputFrameLength = convertedBuffer.frameLength
            processingSuccessful = true
        } else {
            // 兜底：直接把原始PCM送给Speech，让系统自行处理重采样/声道
            if !didFallbackToRawAppend {
                logger.warning("音频转换失败，改为直接送入Speech缓冲区")
                didFallbackToRawAppend = true
            }
            audioHeartbeat?.observe(audioBuffer)
            recognitionRequest.append(audioBuffer)
            outputFrameLength = audioBuffer.frameLength
            processingSuccessful = true
        }

        // 定期输出处理状态（降低日志频率）
        let currentTime = Date().timeIntervalSince1970
        if Int(currentTime) % CaptureConfig.audioQualityLogFrequency == 0 {
            logger.debug("音频处理: \(audioBuffer.frameLength) → \(outputFrameLength) 帧")
        }
    }
    
    private func convertAudioFormat(_ inputBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        // 创建目标格式（Speech框架要求16kHz单声道）
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: CaptureConfig.targetSampleRate,
            channels: CaptureConfig.targetChannelCount,
            interleaved: false
        ) else {
            return nil
        }
        
        // 检查是否需要转换
        if inputBuffer.format.sampleRate == targetFormat.sampleRate && 
           inputBuffer.format.channelCount == targetFormat.channelCount &&
           inputBuffer.format.commonFormat == targetFormat.commonFormat {
            return inputBuffer
        }
        
        // 创建音频转换器
        guard let converter = AVAudioConverter(from: inputBuffer.format, to: targetFormat) else {
            return nil
        }
        
        // 计算输出缓冲区大小
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        
        guard outputCapacity > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return nil
        }
        
        // 执行音频转换
        var error: NSError?
        var inputExhausted = false
        
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if inputExhausted {
                outStatus.pointee = AVAudioConverterInputStatus.endOfStream
                return nil
            } else {
                outStatus.pointee = AVAudioConverterInputStatus.haveData
                inputExhausted = true
                return inputBuffer
            }
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        // 静默处理错误，避免日志污染
        guard error == nil, status != .error, outputBuffer.frameLength > 0 else {
            return nil
        }
        
        return outputBuffer
    }
    
    private func createAudioBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else {
            return nil
        }

        // 检查实际的音频格式
        var isSourceInterleaved = true
        if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
                isSourceInterleaved = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
            }
        }

        // 计算帧数
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        let frameCount = AVAudioFrameCount(length) / AVAudioFrameCount(bytesPerFrame)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        // 获取音频数据指针
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                               totalLengthOut: nil, dataPointerOut: &dataPointer)

        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else {
            return nil
        }

        // 复制音频数据到PCM缓冲区
        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else { return nil }
            let floatPointer = dataPointer.withMemoryRebound(to: Float.self, capacity: Int(frameCount * format.channelCount)) { $0 }

            if isSourceInterleaved && !format.isInterleaved {
                // 源数据是交错格式，目标是非交错格式
                // 源: [L0, R0, L1, R1, ...] -> 目标: [L0, L1, ...], [R0, R1, ...]
                for frame in 0..<Int(frameCount) {
                    for channel in 0..<Int(format.channelCount) {
                        let sourceIndex = frame * Int(format.channelCount) + channel
                        channelData[channel][frame] = floatPointer[sourceIndex]
                    }
                }
            } else if !isSourceInterleaved && !format.isInterleaved {
                // 源和目标都是非交错格式，直接复制
                for channel in 0..<Int(format.channelCount) {
                    let channelOffset = channel * Int(frameCount)
                    channelData[channel].update(from: floatPointer.advanced(by: channelOffset), count: Int(frameCount))
                }
            } else if isSourceInterleaved && format.isInterleaved {
                // 源和目标都是交错格式，直接复制
                let totalSamples = Int(frameCount * format.channelCount)
                channelData[0].update(from: floatPointer, count: totalSamples)
            } else {
                // 源是非交错，目标是交错（不太常见）
                for frame in 0..<Int(frameCount) {
                    for channel in 0..<Int(format.channelCount) {
                        let sourceIndex = channel * Int(frameCount) + frame
                        let destIndex = frame * Int(format.channelCount) + channel
                        channelData[0][destIndex] = floatPointer[sourceIndex]
                    }
                }
            }

        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else { return nil }
            let int16Pointer = dataPointer.withMemoryRebound(to: Int16.self, capacity: Int(frameCount * format.channelCount)) { $0 }

            if isSourceInterleaved && !format.isInterleaved {
                for frame in 0..<Int(frameCount) {
                    for channel in 0..<Int(format.channelCount) {
                        let sourceIndex = frame * Int(format.channelCount) + channel
                        channelData[channel][frame] = int16Pointer[sourceIndex]
                    }
                }
            } else {
                for channel in 0..<Int(format.channelCount) {
                    let channelOffset = channel * Int(frameCount)
                    channelData[channel].update(from: int16Pointer.advanced(by: channelOffset), count: Int(frameCount))
                }
            }

        default:
            return nil
        }

        return buffer
    }
    
    // MARK: - Utility Methods
    
    /// 获取音频质量报告
    public func getAudioQualityReport() -> String {
        return performanceMetrics.getMetricsReport()
    }
    
    /// 重置音频质量数据
    public func resetQualityData() {
        performanceMetrics.reset()
        logger.info("性能指标已重置")
    }
    
    /// 获取当前性能指标
    public func getPerformanceMetrics() -> PerformanceMetrics {
        return performanceMetrics
    }
    
    /// 检查系统健康状态
    public func getSystemHealth() -> (score: Double, description: String) {
        let score = performanceMetrics.getHealthScore()
        let description: String
        
        switch score {
        case 0.9...1.0:
            description = "优秀 - 系统运行良好"
        case 0.7..<0.9:
            description = "良好 - 系统运行正常"
        case 0.5..<0.7:
            description = "中等 - 系统性能有所下降"
        case 0.3..<0.5:
            description = "较差 - 建议检查系统状态"
        default:
            description = "严重 - 系统需要立即关注"
        }
        
        return (score, description)
    }
    
    /// 记录权限指导信息
    private func logPermissionGuidance() {
        logger.info("权限解决步骤:")
        logger.info("1. 打开【系统偏好设置】->【安全性与隐私】->【隐私】->【屏幕录制】")
        logger.info("2. 勾选【VoiceTranslation】应用")
        logger.info("3. 完全退出并重新启动 VoiceTranslation 应用")
        logger.info("提示：如果已勾选，请先取消勾选，等待1-2秒后再重新勾选")
    }
}

// MARK: - SCStreamDelegate

@available(macOS 12.3, *)
extension SystemAudioCapture: SCStreamDelegate {
    
    // SCStreamOutput 协议在 macOS 13.0+ 才可用
    @available(macOS 13.0, *)
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // 只处理音频数据
        guard type == .audio,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            return
        }
        
        // 定期记录状态（降低日志频率）
        let currentTime = Date().timeIntervalSince1970
        if Int(currentTime) % CaptureConfig.logFrequency == 0 {
            let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
            let duration = CMSampleBufferGetDuration(sampleBuffer)
            let durationSeconds = CMTimeGetSeconds(duration)
            logger.debug("系统音频捕获: \(numSamples) 采样点, 时长: \(String(format: "%.3f", durationSeconds))秒")
        }
        
        // 在后台队列处理音频数据
        queue.async { [weak self] in
            self?.processAudioBuffer(sampleBuffer)
        }
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("系统音频捕获流停止，错误: \(error.localizedDescription)")
        
        // 标记流为不健康状态
        Task {
            await streamState.markUnhealthy()
        }
        
        // 更新UI状态
        Task { @MainActor in
            self.isCapturing = false
            self.lastError = "音频流意外停止: \(error.localizedDescription)"
        }
    }
}

// MARK: - SCStreamOutput (macOS 13.0+)

@available(macOS 13.0, *)
extension SystemAudioCapture: SCStreamOutput {
    // SCStreamOutput 协议实现在 SCStreamDelegate 扩展中
}
