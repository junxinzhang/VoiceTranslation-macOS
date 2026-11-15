//
//  AudioQualityMonitor.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-12.
//

import Foundation
import AVFoundation
import Combine
import Accelerate

/// 音频质量状态
public enum AudioQualityStatus {
    case excellent      // 优秀 (> 80%)
    case good          // 良好 (60-80%)
    case fair          // 一般 (40-60%)
    case poor          // 较差 (20-40%)
    case silent        // 静音 (< 20%)
    case error         // 错误状态
    
    var percentage: Double {
        switch self {
        case .excellent: return 0.9
        case .good: return 0.7
        case .fair: return 0.5
        case .poor: return 0.3
        case .silent: return 0.1
        case .error: return 0.0
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "优秀"
        case .good: return "良好"
        case .fair: return "一般"
        case .poor: return "较差"
        case .silent: return "静音"
        case .error: return "错误"
        }
    }
    
    var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟡"
        case .fair: return "🟠"
        case .poor: return "🔴"
        case .silent: return "🔇"
        case .error: return "❌"
        }
    }
}

/// 音频质量指标
public struct AudioQualityMetrics {
    let volume: Float           // 音量 (0.0 - 1.0)
    let peak: Float            // 峰值
    let rms: Float             // 有效值
    let silenceRatio: Float    // 静音比例
    let clipCount: Int         // 削波次数
    let sampleRate: Double     // 采样率
    let channelCount: Int      // 声道数
    let timestamp: Date        // 时间戳
    
    var status: AudioQualityStatus {
        // 基于多维度评估音频质量
        if volume < 0.01 && rms < 0.01 {
            return .silent
        } else if volume > 0.8 && rms > 0.6 && clipCount == 0 {
            return .excellent
        } else if volume > 0.5 && rms > 0.3 && clipCount <= 2 {
            return .good
        } else if volume > 0.2 && rms > 0.1 {
            return .fair
        } else if volume > 0.05 {
            return .poor
        } else {
            return .silent
        }
    }
}

/// 音频质量监控器
@MainActor
public class AudioQualityMonitor: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var currentMetrics: AudioQualityMetrics?
    @Published public private(set) var currentStatus: AudioQualityStatus = .silent
    @Published public private(set) var isMonitoring = false
    
    // 历史数据（用于趋势分析）
    @Published public private(set) var recentMetrics: [AudioQualityMetrics] = []
    @Published public private(set) var averageVolume: Float = 0.0
    @Published public private(set) var silentPeriodDuration: TimeInterval = 0.0
    
    // 问题检测
    @Published public private(set) var detectedIssues: [AudioIssue] = []
    @Published public private(set) var lastIssueTimestamp: Date?
    
    // MARK: - Private Properties
    
    private let metricsSubject = PassthroughSubject<AudioQualityMetrics, Never>()
    private let issueSubject = PassthroughSubject<AudioIssue, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    private let monitoringQueue = DispatchQueue(label: "AudioQualityMonitor", qos: .userInteractive)
    
    // 监控参数
    private let maxHistoryCount = 50  // 保留最近50个指标
    private let silenceThreshold: Float = 0.01  // 静音阈值
    private let clipThreshold: Float = 0.95     // 削波阈值
    private let issueDetectionWindow: TimeInterval = 10.0  // 问题检测时间窗口
    
    // 状态跟踪
    private var lastSilentTime: Date?
    private var continuousSilentDuration: TimeInterval = 0.0
    
    // MARK: - Public Methods
    
    /// 音频质量指标发布者
    public var qualityMetrics: AnyPublisher<AudioQualityMetrics, Never> {
        metricsSubject.eraseToAnyPublisher()
    }
    
    /// 音频问题发布者
    public var audioIssues: AnyPublisher<AudioIssue, Never> {
        issueSubject.eraseToAnyPublisher()
    }
    
    /// 开始监控
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        lastSilentTime = nil
        continuousSilentDuration = 0.0
        detectedIssues.removeAll()
        
        print("🎵 音频质量监控已开始")
    }
    
    /// 停止监控
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        currentMetrics = nil
        currentStatus = .silent
        
        print("🎵 音频质量监控已停止")
    }
    
    /// 处理音频缓冲区（主要监控入口）
    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isMonitoring else { return }
        
        monitoringQueue.async { [weak self] in
            guard let self = self else { return }
            
            let metrics = self.analyzeAudioBuffer(buffer)
            
            Task { @MainActor [weak self] in
                self?.updateMetrics(metrics)
            }
        }
    }
    
    /// 获取质量评估报告
    public func getQualityReport() -> String {
        guard !recentMetrics.isEmpty else {
            return "暂无音频质量数据"
        }
        
        let avgVolume = recentMetrics.map { $0.volume }.reduce(0, +) / Float(recentMetrics.count)
        let avgRMS = recentMetrics.map { $0.rms }.reduce(0, +) / Float(recentMetrics.count)
        let totalClips = recentMetrics.map { $0.clipCount }.reduce(0, +)
        
        let statusDistribution = Dictionary(grouping: recentMetrics) { $0.status }
            .mapValues { $0.count }
        
        var report = "音频质量报告 (最近 \(recentMetrics.count) 个样本):\n"
        report += "📊 平均音量: \(String(format: "%.1f%%", avgVolume * 100))\n"
        report += "📊 平均有效值: \(String(format: "%.1f%%", avgRMS * 100))\n"
        report += "⚡ 总削波次数: \(totalClips)\n"
        report += "⏱️ 静音时长: \(String(format: "%.1f秒", silentPeriodDuration))\n"
        
        report += "\n状态分布:\n"
        for (status, count) in statusDistribution.sorted(by: { $0.value > $1.value }) {
            let percentage = Double(count) / Double(recentMetrics.count) * 100
            report += "\(status.emoji) \(status.description): \(String(format: "%.1f%%", percentage))\n"
        }
        
        if !detectedIssues.isEmpty {
            report += "\n⚠️ 检测到的问题:\n"
            for issue in detectedIssues.suffix(5) {
                report += "• \(issue.description)\n"
            }
        }
        
        return report
    }
    
    /// 重置监控数据
    public func resetData() {
        recentMetrics.removeAll()
        detectedIssues.removeAll()
        averageVolume = 0.0
        silentPeriodDuration = 0.0
        lastIssueTimestamp = nil
        lastSilentTime = nil
        continuousSilentDuration = 0.0
        
        print("🔄 音频质量监控数据已重置")
    }
    
    // MARK: - Private Methods
    
    private func analyzeAudioBuffer(_ buffer: AVAudioPCMBuffer) -> AudioQualityMetrics {
        let format = buffer.format
        let frameLength = buffer.frameLength
        let channelCount = Int(format.channelCount)
        
        guard frameLength > 0, let channelData = buffer.floatChannelData else {
            return AudioQualityMetrics(
                volume: 0.0,
                peak: 0.0,
                rms: 0.0,
                silenceRatio: 1.0,
                clipCount: 0,
                sampleRate: format.sampleRate,
                channelCount: channelCount,
                timestamp: Date()
            )
        }
        
        // 分析第一个声道的数据
        let samples = channelData[0]
        let sampleCount = Int(frameLength)
        
        // 计算峰值
        var peak: Float = 0.0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(sampleCount))
        
        // 计算RMS（有效值）
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(sampleCount))
        
        // 计算平均音量
        var sum: Float = 0.0
        vDSP_meamgv(samples, 1, &sum, vDSP_Length(sampleCount))
        let volume = sum
        
        // 计算静音比例
        var silentSamples = 0
        for i in 0..<sampleCount {
            if abs(samples[i]) < silenceThreshold {
                silentSamples += 1
            }
        }
        let silenceRatio = Float(silentSamples) / Float(sampleCount)
        
        // 检测削波
        var clipCount = 0
        for i in 0..<sampleCount {
            if abs(samples[i]) > clipThreshold {
                clipCount += 1
            }
        }
        
        return AudioQualityMetrics(
            volume: volume,
            peak: peak,
            rms: rms,
            silenceRatio: silenceRatio,
            clipCount: clipCount,
            sampleRate: format.sampleRate,
            channelCount: channelCount,
            timestamp: Date()
        )
    }
    
    private func updateMetrics(_ metrics: AudioQualityMetrics) {
        currentMetrics = metrics
        currentStatus = metrics.status
        
        // 更新历史记录
        recentMetrics.append(metrics)
        if recentMetrics.count > maxHistoryCount {
            recentMetrics.removeFirst()
        }
        
        // 更新平均音量
        averageVolume = recentMetrics.map { $0.volume }.reduce(0, +) / Float(recentMetrics.count)
        
        // 更新静音时长
        updateSilentDuration(metrics)
        
        // 检测问题
        detectAudioIssues(metrics)
        
        // 发布指标
        metricsSubject.send(metrics)
    }
    
    private func updateSilentDuration(_ metrics: AudioQualityMetrics) {
        let isSilent = metrics.status == .silent
        let currentTime = metrics.timestamp
        
        if isSilent {
            if lastSilentTime == nil {
                lastSilentTime = currentTime
            }
            continuousSilentDuration = currentTime.timeIntervalSince(lastSilentTime!)
        } else {
            if let silentStart = lastSilentTime {
                silentPeriodDuration += currentTime.timeIntervalSince(silentStart)
            }
            lastSilentTime = nil
            continuousSilentDuration = 0.0
        }
    }
    
    private func detectAudioIssues(_ metrics: AudioQualityMetrics) {
        var newIssues: [AudioIssue] = []
        
        // 检测长时间静音
        if continuousSilentDuration > 10.0 {
            newIssues.append(.prolongedSilence(duration: continuousSilentDuration))
        }
        
        // 检测削波问题
        if metrics.clipCount > 10 {
            newIssues.append(.audioClipping(count: metrics.clipCount))
        }
        
        // 检测音量过低
        if metrics.volume < 0.05 && metrics.status != .silent {
            newIssues.append(.lowVolume(volume: metrics.volume))
        }
        
        // 检测音量过高
        if metrics.volume > 0.95 {
            newIssues.append(.highVolume(volume: metrics.volume))
        }
        
        // 检测采样率问题
        if metrics.sampleRate < 16000 {
            newIssues.append(.lowSampleRate(rate: metrics.sampleRate))
        }
        
        // 添加新问题并发布
        for issue in newIssues {
            if !detectedIssues.contains(where: { $0.type == issue.type }) ||
               (lastIssueTimestamp == nil || Date().timeIntervalSince(lastIssueTimestamp!) > issueDetectionWindow) {
                
                detectedIssues.append(issue)
                lastIssueTimestamp = Date()
                issueSubject.send(issue)
                
                print("⚠️ 音频质量问题: \(issue.description)")
            }
        }
    }
}

/// 音频问题类型
public enum AudioIssue: Equatable {
    case prolongedSilence(duration: TimeInterval)
    case audioClipping(count: Int)
    case lowVolume(volume: Float)
    case highVolume(volume: Float)
    case lowSampleRate(rate: Double)
    case bufferUnderrun
    case formatMismatch
    
    var type: String {
        switch self {
        case .prolongedSilence: return "prolongedSilence"
        case .audioClipping: return "audioClipping"
        case .lowVolume: return "lowVolume"
        case .highVolume: return "highVolume"
        case .lowSampleRate: return "lowSampleRate"
        case .bufferUnderrun: return "bufferUnderrun"
        case .formatMismatch: return "formatMismatch"
        }
    }
    
    var description: String {
        switch self {
        case .prolongedSilence(let duration):
            return "长时间静音 (\(String(format: "%.1f", duration))秒)"
        case .audioClipping(let count):
            return "音频削波 (\(count)次)"
        case .lowVolume(let volume):
            return "音量过低 (\(String(format: "%.1f%%", volume * 100)))"
        case .highVolume(let volume):
            return "音量过高 (\(String(format: "%.1f%%", volume * 100)))"
        case .lowSampleRate(let rate):
            return "采样率过低 (\(rate)Hz)"
        case .bufferUnderrun:
            return "缓冲区欠载"
        case .formatMismatch:
            return "音频格式不匹配"
        }
    }
}