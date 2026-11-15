//
//  AudioQualityMonitorTests.swift
//  VoiceTranslationTests
//
//  Created by Claude on 2025-08-12.
//

import XCTest
import AVFoundation
import Combine
@testable import VoiceTranslation

@MainActor
final class AudioQualityMonitorTests: XCTestCase {
    
    var audioQualityMonitor: AudioQualityMonitor!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        audioQualityMonitor = AudioQualityMonitor()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        audioQualityMonitor.stopMonitoring()
        cancellables.removeAll()
        audioQualityMonitor = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testAudioQualityMonitorInitialization() {
        XCTAssertFalse(audioQualityMonitor.isMonitoring, "初始状态应该不在监控中")
        XCTAssertEqual(audioQualityMonitor.currentStatus, .silent, "初始状态应该是静音")
        XCTAssertNil(audioQualityMonitor.currentMetrics, "初始时应该没有指标")
        XCTAssertTrue(audioQualityMonitor.recentMetrics.isEmpty, "初始时历史指标应该为空")
        XCTAssertTrue(audioQualityMonitor.detectedIssues.isEmpty, "初始时应该没有检测到问题")
    }
    
    // MARK: - Monitoring Control Tests
    
    func testStartStopMonitoring() {
        // 开始监控
        audioQualityMonitor.startMonitoring()
        XCTAssertTrue(audioQualityMonitor.isMonitoring, "开始监控后状态应该是监控中")
        
        // 停止监控
        audioQualityMonitor.stopMonitoring()
        XCTAssertFalse(audioQualityMonitor.isMonitoring, "停止监控后状态应该不在监控中")
        XCTAssertEqual(audioQualityMonitor.currentStatus, .silent, "停止监控后状态应该重置为静音")
    }
    
    func testMultipleStartMonitoring() {
        // 多次开始监控应该安全
        audioQualityMonitor.startMonitoring()
        audioQualityMonitor.startMonitoring()
        XCTAssertTrue(audioQualityMonitor.isMonitoring, "多次开始监控应该仍然有效")
    }
    
    func testMultipleStopMonitoring() {
        // 多次停止监控应该安全
        audioQualityMonitor.startMonitoring()
        audioQualityMonitor.stopMonitoring()
        audioQualityMonitor.stopMonitoring()
        XCTAssertFalse(audioQualityMonitor.isMonitoring, "多次停止监控应该安全")
    }
    
    // MARK: - Audio Buffer Processing Tests
    
    func testProcessValidAudioBuffer() {
        audioQualityMonitor.startMonitoring()
        
        // 创建测试音频缓冲区
        let buffer = createTestAudioBuffer(sampleRate: 44100, channelCount: 2, frameCount: 1024)
        
        // 处理音频缓冲区
        audioQualityMonitor.processAudioBuffer(buffer)
        
        // 验证指标更新
        XCTAssertNotNil(audioQualityMonitor.currentMetrics, "处理音频后应该有当前指标")
        XCTAssertFalse(audioQualityMonitor.recentMetrics.isEmpty, "处理音频后应该有历史指标")
    }
    
    func testProcessEmptyAudioBuffer() {
        audioQualityMonitor.startMonitoring()
        
        // 创建空的音频缓冲区
        let buffer = createTestAudioBuffer(sampleRate: 44100, channelCount: 2, frameCount: 0)
        
        // 处理空音频缓冲区应该安全
        XCTAssertNoThrow(audioQualityMonitor.processAudioBuffer(buffer), "处理空音频缓冲区不应该抛出异常")
    }
    
    func testProcessMultipleAudioBuffers() {
        audioQualityMonitor.startMonitoring()
        
        let expectation = XCTestExpectation(description: "处理多个音频缓冲区")
        expectation.expectedFulfillmentCount = 5
        
        // 监听指标更新
        audioQualityMonitor.qualityMetrics
            .sink { metrics in
                XCTAssertGreaterThan(metrics.sampleRate, 0, "采样率应该大于0")
                XCTAssertGreaterThan(metrics.channelCount, 0, "声道数应该大于0")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // 处理多个音频缓冲区
        for i in 0..<5 {
            let buffer = createTestAudioBuffer(
                sampleRate: 44100,
                channelCount: 2,
                frameCount: 1024,
                volume: Float(i) * 0.2
            )
            audioQualityMonitor.processAudioBuffer(buffer)
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    // MARK: - Audio Quality Status Tests
    
    func testAudioQualityStatusClassification() {
        let testCases: [(volume: Float, rms: Float, expectedStatus: AudioQualityStatus)] = [
            (0.9, 0.7, .excellent),
            (0.7, 0.5, .good),
            (0.4, 0.3, .fair),
            (0.1, 0.05, .poor),
            (0.005, 0.001, .silent)
        ]
        
        for (volume, rms, expectedStatus) in testCases {
            let metrics = AudioQualityMetrics(
                volume: volume,
                peak: volume,
                rms: rms,
                silenceRatio: volume < 0.01 ? 1.0 : 0.0,
                clipCount: 0,
                sampleRate: 44100,
                channelCount: 2,
                timestamp: Date()
            )
            
            XCTAssertEqual(metrics.status, expectedStatus,
                          "音量 \(volume), RMS \(rms) 应该被分类为 \(expectedStatus)")
        }
    }
    
    // MARK: - Issue Detection Tests
    
    func testProlongedSilenceDetection() {
        audioQualityMonitor.startMonitoring()
        
        let expectation = XCTestExpectation(description: "检测到长时间静音问题")
        
        // 监听音频问题
        audioQualityMonitor.audioIssues
            .sink { issue in
                if case .prolongedSilence = issue {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // 模拟长时间静音
        for _ in 0..<15 {
            let silentBuffer = createTestAudioBuffer(
                sampleRate: 44100,
                channelCount: 2,
                frameCount: 1024,
                volume: 0.0
            )
            audioQualityMonitor.processAudioBuffer(silentBuffer)
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testAudioClippingDetection() {
        audioQualityMonitor.startMonitoring()
        
        let expectation = XCTestExpectation(description: "检测到音频削波问题")
        
        // 监听音频问题
        audioQualityMonitor.audioIssues
            .sink { issue in
                if case .audioClipping = issue {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // 创建有削波的音频缓冲区
        let buffer = createTestAudioBuffer(
            sampleRate: 44100,
            channelCount: 2,
            frameCount: 1024,
            volume: 1.0,
            clipCount: 15
        )
        audioQualityMonitor.processAudioBuffer(buffer)
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    func testLowVolumeDetection() {
        audioQualityMonitor.startMonitoring()
        
        let expectation = XCTestExpectation(description: "检测到低音量问题")
        
        // 监听音频问题
        audioQualityMonitor.audioIssues
            .sink { issue in
                if case .lowVolume = issue {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // 创建低音量音频缓冲区
        let buffer = createTestAudioBuffer(
            sampleRate: 44100,
            channelCount: 2,
            frameCount: 1024,
            volume: 0.03 // 低于0.05阈值
        )
        audioQualityMonitor.processAudioBuffer(buffer)
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    // MARK: - Quality Report Tests
    
    func testQualityReportGeneration() {
        audioQualityMonitor.startMonitoring()
        
        // 处理一些音频数据
        for i in 0..<10 {
            let buffer = createTestAudioBuffer(
                sampleRate: 44100,
                channelCount: 2,
                frameCount: 1024,
                volume: Float(i) * 0.1
            )
            audioQualityMonitor.processAudioBuffer(buffer)
        }
        
        let report = audioQualityMonitor.getQualityReport()
        
        XCTAssertFalse(report.isEmpty, "质量报告不应该为空")
        XCTAssertTrue(report.contains("音频质量报告"), "报告应该包含标题")
        XCTAssertTrue(report.contains("平均音量"), "报告应该包含平均音量")
        XCTAssertTrue(report.contains("样本"), "报告应该包含样本信息")
    }
    
    func testEmptyQualityReport() {
        let report = audioQualityMonitor.getQualityReport()
        
        XCTAssertTrue(report.contains("暂无音频质量数据"), "空报告应该显示相应消息")
    }
    
    // MARK: - Data Management Tests
    
    func testResetData() {
        audioQualityMonitor.startMonitoring()
        
        // 添加一些数据
        let buffer = createTestAudioBuffer(sampleRate: 44100, channelCount: 2, frameCount: 1024)
        audioQualityMonitor.processAudioBuffer(buffer)
        
        // 验证有数据
        XCTAssertFalse(audioQualityMonitor.recentMetrics.isEmpty, "重置前应该有数据")
        
        // 重置数据
        audioQualityMonitor.resetData()
        
        // 验证数据被清空
        XCTAssertTrue(audioQualityMonitor.recentMetrics.isEmpty, "重置后历史数据应该被清空")
        XCTAssertTrue(audioQualityMonitor.detectedIssues.isEmpty, "重置后问题记录应该被清空")
        XCTAssertEqual(audioQualityMonitor.averageVolume, 0.0, "重置后平均音量应该为0")
        XCTAssertEqual(audioQualityMonitor.silentPeriodDuration, 0.0, "重置后静音时长应该为0")
    }
    
    func testHistoryLimiting() {
        audioQualityMonitor.startMonitoring()
        
        // 处理超过限制数量的音频缓冲区
        for i in 0..<60 { // 超过默认的50个限制
            let buffer = createTestAudioBuffer(
                sampleRate: 44100,
                channelCount: 2,
                frameCount: 1024,
                volume: Float(i % 10) * 0.1
            )
            audioQualityMonitor.processAudioBuffer(buffer)
        }
        
        // 验证历史记录被限制在合理范围内
        XCTAssertLessThanOrEqual(audioQualityMonitor.recentMetrics.count, 50,
                                "历史记录应该被限制在最大数量以内")
    }
    
    // MARK: - Performance Tests
    
    func testAudioProcessingPerformance() {
        audioQualityMonitor.startMonitoring()
        
        measure {
            for _ in 0..<100 {
                let buffer = createTestAudioBuffer(
                    sampleRate: 44100,
                    channelCount: 2,
                    frameCount: 1024
                )
                audioQualityMonitor.processAudioBuffer(buffer)
            }
        }
    }
    
    func testQualityReportPerformance() {
        audioQualityMonitor.startMonitoring()
        
        // 添加大量数据
        for i in 0..<50 {
            let buffer = createTestAudioBuffer(
                sampleRate: 44100,
                channelCount: 2,
                frameCount: 1024,
                volume: Float(i) * 0.02
            )
            audioQualityMonitor.processAudioBuffer(buffer)
        }
        
        measure {
            _ = audioQualityMonitor.getQualityReport()
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestAudioBuffer(
        sampleRate: Double,
        channelCount: UInt32,
        frameCount: AVAudioFrameCount,
        volume: Float = 0.5,
        clipCount: Int = 0
    ) -> AVAudioPCMBuffer {
        
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channelCount
        ) else {
            fatalError("无法创建音频格式")
        }
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            fatalError("无法创建音频缓冲区")
        }
        
        buffer.frameLength = frameCount
        
        // 填充测试数据
        guard let channelData = buffer.floatChannelData else {
            fatalError("无法获取声道数据")
        }
        
        for channel in 0..<Int(channelCount) {
            for frame in 0..<Int(frameCount) {
                var value = volume * sin(Float(frame) * 0.1) // 基础正弦波
                
                // 添加削波（如果需要）
                if frame < clipCount {
                    value = value > 0 ? 1.0 : -1.0
                }
                
                channelData[channel][frame] = value
            }
        }
        
        return buffer
    }
}