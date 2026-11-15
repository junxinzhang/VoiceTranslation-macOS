//
//  CoreAudioTapCapture.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-01-02.
//
//  Core Audio Tap implementation for volume-independent system audio capture.
//  Uses the Core Audio taps API introduced in macOS 14.2 to capture audio
//  pre-mixer, allowing capture even when system volume is muted.
//

import Foundation
import AVFoundation
import Speech
import CoreAudio
import AudioToolbox
import os.log

// MARK: - Error Types

/// Core Audio Tap专用错误类型
enum CoreAudioTapError: LocalizedError, Equatable {
    case systemVersionUnsupported
    case permissionDenied
    case tapCreationFailed(String)
    case aggregateDeviceFailed(String)
    case audioFormatUnsupported
    case resourceExhausted
    case deviceNotAvailable

    var errorDescription: String? {
        switch self {
        case .systemVersionUnsupported:
            return "系统版本不支持 (需要 macOS 14.2+)"
        case .permissionDenied:
            return "音频捕获权限被拒绝"
        case .tapCreationFailed(let details):
            return "音频Tap创建失败: \(details)"
        case .aggregateDeviceFailed(let details):
            return "聚合设备创建失败: \(details)"
        case .audioFormatUnsupported:
            return "不支持的音频格式"
        case .resourceExhausted:
            return "系统资源耗尽"
        case .deviceNotAvailable:
            return "音频设备不可用"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .systemVersionUnsupported, .permissionDenied, .audioFormatUnsupported:
            return false
        case .tapCreationFailed, .aggregateDeviceFailed, .resourceExhausted, .deviceNotAvailable:
            return true
        }
    }
}

// MARK: - Core Audio Tap Capture

/// 使用Core Audio Tap API实现音量无关的系统音频捕获
/// 该实现捕获pre-mixer音频，即使系统静音也能正常工作
@available(macOS 14.2, *)
class CoreAudioTapCapture: NSObject, ObservableObject {

    // MARK: - Configuration

    private struct CaptureConfig {
        static let sampleRate: Double = 48000.0
        static let channelCount: UInt32 = 2
        static let targetSampleRate: Double = 16000.0
        static let targetChannelCount: AVAudioChannelCount = 1
        static let bufferSize: UInt32 = 4096
        static let maxRetries = 3
    }

    // MARK: - Logging

    private let logger = Logger(subsystem: "com.voicetranslation.audio", category: "CoreAudioTapCapture")

    // MARK: - Properties

    private let startupLock = NSLock()
    private var deviceStartInProgress = false
    private var stopRequestedDuringStart = false
    private var cleanupRequestedDuringStart = false
    var audioHeartbeat: AudioHeartbeat?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var processTapID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var tapDescription: CATapDescription?
    private var audioFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?
    private var audioConverter: AVAudioConverter?

    private let queue = DispatchQueue(label: "CoreAudioTapCapture", qos: .userInteractive)

    // 状态管理
    @Published public private(set) var isCapturing = false
    @Published public private(set) var lastError: String?
    @Published public private(set) var permissionStatus: String = "未确定"

    // 性能监控
    private var buffersProcessed: Int = 0
    private var processingErrors: Int = 0
    private var didFallbackToRawAppend = false

    // MARK: - Initialization

    override init() {
        super.init()
        logger.info("CoreAudioTapCapture 初始化")
    }

    deinit {
        cleanup()
    }

    // MARK: - Public Methods

    /// 检查是否支持 Core Audio Tap
    var isSupported: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }

    /// 设置系统音频捕获（使用Core Audio Tap）
    func setupSystemAudioCapture(with recognitionRequest: SFSpeechAudioBufferRecognitionRequest) async throws {
        self.recognitionRequest = recognitionRequest

        logger.info("开始设置Core Audio Tap系统音频捕获")

        // 设置音频格式
        try setupAudioFormats()

        // 创建全局音频Tap（捕获所有应用音频，排除当前应用）
        try await createProcessTap()

        // 创建聚合设备
        try await createAggregateDevice()

        logger.info("Core Audio Tap设置完成")
    }

    /// 开始捕获
    func start() async throws {
        guard processTapID != 0 && aggregateDeviceID != 0 else {
            throw CoreAudioTapError.tapCreationFailed("Tap未初始化")
        }

        logger.info("启动Core Audio Tap捕获")
        print("🚀 启动Core Audio Tap: tapID=\(processTapID), deviceID=\(aggregateDeviceID)")

        // 验证聚合设备的输入流
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(aggregateDeviceID, &propertyAddress, 0, nil, &dataSize)
        if status == noErr {
            let streamCount = dataSize / UInt32(MemoryLayout<AudioStreamID>.size)
            print("📊 聚合设备输入流数量: \(streamCount)")
        } else {
            print("⚠️ 无法获取输入流数量: \(status)")
        }

        // 检查设备是否正在运行
        propertyAddress.mSelector = kAudioDevicePropertyDeviceIsRunning
        var isRunning: UInt32 = 0
        dataSize = UInt32(MemoryLayout<UInt32>.size)
        status = AudioObjectGetPropertyData(aggregateDeviceID, &propertyAddress, 0, nil, &dataSize, &isRunning)
        print("📊 设备运行状态(启动前): \(isRunning == 1 ? "运行中" : "已停止")")

        // 设置IO回调
        try setupIOCallback()

        // 启动设备
        startupLock.lock()
        deviceStartInProgress = true
        startupLock.unlock()
        let deviceID = aggregateDeviceID
        let callbackID = ioProcID
        status = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: AudioDeviceStart(deviceID, callbackID)) }
        }
        startupLock.lock()
        deviceStartInProgress = false
        let shouldStop = stopRequestedDuringStart
        let shouldCleanup = cleanupRequestedDuringStart
        startupLock.unlock()
        if shouldStop || shouldCleanup || Task.isCancelled {
            cleanup()
            throw CancellationError()
        }
        guard status == noErr else {
            print("❌ 设备启动失败: \(status)")
            throw CoreAudioTapError.tapCreationFailed("设备启动失败: \(status)")
        }

        // 再次检查设备是否正在运行
        status = AudioObjectGetPropertyData(aggregateDeviceID, &propertyAddress, 0, nil, &dataSize, &isRunning)
        print("📊 设备运行状态(启动后): \(isRunning == 1 ? "运行中" : "已停止")")

        await MainActor.run {
            self.isCapturing = true
            self.lastError = nil
        }

        logger.info("Core Audio Tap捕获已启动")
        print("✅ Core Audio Tap捕获已成功启动")
    }

    /// 停止捕获
    func stop() {
        startupLock.lock()
        if deviceStartInProgress {
            stopRequestedDuringStart = true
            startupLock.unlock()
            return
        }
        startupLock.unlock()
        logger.info("停止Core Audio Tap捕获")

        if let ioProcID = ioProcID, aggregateDeviceID != 0 {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }

        updateCapturingState(false)

        logger.info("Core Audio Tap捕获已停止")
    }

    /// 清理所有资源
    func cleanup() {
        startupLock.lock()
        if deviceStartInProgress {
            cleanupRequestedDuringStart = true
            startupLock.unlock()
            return
        }
        startupLock.unlock()
        stop()

        // 销毁聚合设备
        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
            logger.info("聚合设备已销毁")
        }

        // 销毁进程Tap
        if processTapID != 0 {
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = 0
            logger.info("进程Tap已销毁")
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioConverter = nil

        logger.info("Core Audio Tap资源清理完成")
    }

    /// 更新识别请求（用于重启识别任务）
    func updateRecognitionRequest(_ request: SFSpeechAudioBufferRecognitionRequest) {
        recognitionRequest = request
    }

    /// 获取性能报告
    func getPerformanceReport() -> String {
        return """
        Core Audio Tap 性能报告:
        - 已处理缓冲区: \(buffersProcessed)
        - 处理错误: \(processingErrors)
        - 捕获状态: \(isCapturing ? "运行中" : "已停止")
        """
    }

    // MARK: - Private Methods

    private func updateCapturingState(_ capturing: Bool) {
        if Thread.isMainThread {
            isCapturing = capturing
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.isCapturing = capturing
        }
    }

    private func setupAudioFormats() throws {
        // 创建源格式（Core Audio Tap 输出为交错格式）
        // 重要：Core Audio Tap 输出是 interleaved (交错) 格式！
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: CaptureConfig.sampleRate,
            channels: AVAudioChannelCount(CaptureConfig.channelCount),
            interleaved: true  // Core Audio Tap 输出是交错格式
        ) else {
            throw CoreAudioTapError.audioFormatUnsupported
        }
        self.audioFormat = format
        print("📝 源格式: \(format.sampleRate)Hz, \(format.channelCount)通道, 交错=\(format.isInterleaved)")

        // 创建目标格式（Speech框架需要16kHz单声道，非交错）
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: CaptureConfig.targetSampleRate,
            channels: CaptureConfig.targetChannelCount,
            interleaved: false  // Speech Framework 需要非交错格式
        ) else {
            throw CoreAudioTapError.audioFormatUnsupported
        }
        self.targetFormat = target
        print("📝 目标格式: \(target.sampleRate)Hz, \(target.channelCount)通道, 交错=\(target.isInterleaved)")

        // 创建音频转换器
        guard let converter = AVAudioConverter(from: format, to: target) else {
            throw CoreAudioTapError.audioFormatUnsupported
        }
        self.audioConverter = converter

        logger.info("音频格式设置: \(CaptureConfig.sampleRate)Hz (交错) → \(CaptureConfig.targetSampleRate)Hz (非交错)")
    }

    private func createProcessTap() async throws {
        logger.info("创建全局进程Tap")

        // 创建全局Tap描述
        // 使用空的排除列表来捕获所有应用音频（当前应用通过配置排除）
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])

        // 配置Tap属性
        tapDesc.name = "VoiceTranslation System Audio Tap"
        tapDesc.uuid = UUID()

        // 关键配置：
        // 1. isPrivate = true: 私有Tap，不影响其他应用
        // 2. muteBehavior = .unmuted: 不静音原始音频，用户仍能听到声音
        //    这是捕获 pre-mixer 音频的关键，即使系统静音也能捕获
        // 3. isMixdown = true: 混音到单个流
        // 4. isExclusive = true: 排除模式（空列表 = 捕获所有）
        tapDesc.isPrivate = true
        tapDesc.muteBehavior = .unmuted
        tapDesc.isMixdown = true
        tapDesc.isExclusive = true

        print("🔧 Tap配置: isPrivate=\(tapDesc.isPrivate), muteBehavior=unmuted, isMixdown=\(tapDesc.isMixdown), isExclusive=\(tapDesc.isExclusive)")

        self.tapDescription = tapDesc

        // 创建进程Tap
        var tapID: AudioObjectID = 0
        let status = AudioHardwareCreateProcessTap(tapDesc, &tapID)

        guard status == noErr else {
            let errorMsg = "创建进程Tap失败，状态码: \(status)"
            logger.error("\(errorMsg)")
            print("❌ \(errorMsg)")
            throw CoreAudioTapError.tapCreationFailed(errorMsg)
        }

        self.processTapID = tapID
        logger.info("进程Tap创建成功，ID: \(tapID)")
        print("✅ 进程Tap创建成功，ID: \(tapID)")
    }

    private func createAggregateDevice() async throws {
        guard let tapDesc = tapDescription, processTapID != 0 else {
            throw CoreAudioTapError.tapCreationFailed("Tap描述未初始化")
        }

        logger.info("创建聚合设备")

        // 获取Tap的UUID
        let tapUUID = tapDesc.uuid.uuidString

        // 创建聚合设备配置
        let aggregateDeviceUID = "com.voicetranslation.aggregate.\(UUID().uuidString)"
        let aggregateDeviceName = "VoiceTranslation Audio Capture"

        // Tap子设备配置
        let tapSubDevice: [String: Any] = [
            kAudioSubTapUIDKey as String: tapUUID,
            kAudioSubTapDriftCompensationKey as String: true
        ]

        // 聚合设备属性
        let aggregateDeviceProperties: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: aggregateDeviceName,
            kAudioAggregateDeviceUIDKey as String: aggregateDeviceUID,
            kAudioAggregateDeviceTapListKey as String: [tapSubDevice],
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceTapAutoStartKey as String: true
        ]

        // 创建聚合设备
        var deviceID: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(
            aggregateDeviceProperties as CFDictionary,
            &deviceID
        )

        guard status == noErr else {
            let errorMsg = "创建聚合设备失败，状态码: \(status)"
            logger.error("\(errorMsg)")
            throw CoreAudioTapError.aggregateDeviceFailed(errorMsg)
        }

        self.aggregateDeviceID = deviceID
        logger.info("聚合设备创建成功，ID: \(deviceID)")
    }

    private func setupIOCallback() throws {
        guard aggregateDeviceID != 0 else {
            throw CoreAudioTapError.tapCreationFailed("聚合设备未初始化")
        }

        // 获取Tap的音频格式
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var asbd = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let formatStatus = AudioObjectGetPropertyData(
            processTapID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &asbd
        )

        if formatStatus == noErr {
            let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
            logger.info("Tap音频格式: \(asbd.mSampleRate)Hz, \(asbd.mChannelsPerFrame)通道, 交错=\(isInterleaved)")
            print("🔍 Tap实际格式: \(asbd.mSampleRate)Hz, \(asbd.mChannelsPerFrame)通道, 交错=\(isInterleaved), flags=\(asbd.mFormatFlags)")

            // 更新音频格式以匹配实际Tap输出
            var streamDescription = asbd
            if let format = AVAudioFormat(streamDescription: &streamDescription) {
                self.audioFormat = format
                print("📝 更新源格式: \(format.sampleRate)Hz, \(format.channelCount)通道, 交错=\(format.isInterleaved)")
                if let target = targetFormat {
                    if let newConverter = AVAudioConverter(from: format, to: target) {
                        self.audioConverter = newConverter
                        print("✅ 音频转换器已更新")
                    } else {
                        print("⚠️ 无法创建新的音频转换器")
                    }
                }
            }
        } else {
            print("⚠️ 无法获取Tap格式，使用默认值: \(formatStatus)")
        }

        // 创建IO回调
        var ioProcID: AudioDeviceIOProcID?

        // 用于调试的计数器
        var callbackCount = 0
        let logInterval = 100 // 每100次回调输出一次日志

        let ioBlock: AudioDeviceIOBlock = { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self = self else { return }

            callbackCount += 1

            // 定期输出调试日志
            if callbackCount == 1 || callbackCount % logInterval == 0 {
                let bufferCount = Int(inInputData.pointee.mNumberBuffers)
                let firstBufferBytes = inInputData.pointee.mBuffers.mDataByteSize
                print("🎵 IO回调 #\(callbackCount): \(bufferCount) 缓冲区, 首缓冲区 \(firstBufferBytes) 字节")
            }

            // 注意：AudioBufferList 只在回调期间有效，必须在此处复制数据
            guard let audioFormat = self.audioFormat,
                  let pcmBuffer = self.copyPCMBuffer(from: inInputData, format: audioFormat) else {
                return
            }

            self.queue.async { [weak self] in
                self?.processPCMBuffer(pcmBuffer)
            }
        }

        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, nil, ioBlock)

        guard status == noErr, let procID = ioProcID else {
            throw CoreAudioTapError.tapCreationFailed("创建IO回调失败: \(status)")
        }

        self.ioProcID = procID
        logger.info("IO回调设置成功")
    }

    private func copyPCMBuffer(from bufferList: UnsafePointer<AudioBufferList>, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard let firstBuffer = buffers.first,
              firstBuffer.mDataByteSize > 0,
              firstBuffer.mData != nil else {
            return nil
        }

        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        guard bytesPerFrame > 0 else {
            return nil
        }
        let frameCount = AVAudioFrameCount(firstBuffer.mDataByteSize / bytesPerFrame)

        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        pcmBuffer.frameLength = frameCount

        let destinationBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        let bufferCount = min(buffers.count, destinationBuffers.count)
        for index in 0..<bufferCount {
            let sourceBuffer = buffers[index]
            let destinationBuffer = destinationBuffers[index]
            guard let sourceData = sourceBuffer.mData,
                  let destinationData = destinationBuffer.mData else {
                continue
            }

            let bytesToCopy = min(Int(sourceBuffer.mDataByteSize), Int(destinationBuffer.mDataByteSize))
            if bytesToCopy > 0 {
                memcpy(destinationData, sourceData, bytesToCopy)
            }
        }

        return pcmBuffer
    }

    private func processPCMBuffer(_ pcmBuffer: AVAudioPCMBuffer) {
        audioHeartbeat?.observe(pcmBuffer)
        guard let recognitionRequest = recognitionRequest else {
            if buffersProcessed == 0 {
                print("⚠️ processPCMBuffer: 缺少必要组件 - request:\(recognitionRequest != nil)")
            }
            return
        }

        // 调试：检查音频电平
        if buffersProcessed < 10 || buffersProcessed % 100 == 0 {
            if let floatPtr = pcmBuffer.floatChannelData?[0] {
                let channelCount = Int(pcmBuffer.format.channelCount)
                let totalSamples = pcmBuffer.format.isInterleaved
                    ? (Int(pcmBuffer.frameLength) * channelCount)
                    : Int(pcmBuffer.frameLength)
                var maxLevel: Float = 0
                var sumLevel: Float = 0
                let checkCount = min(totalSamples, 1000)
                for i in 0..<checkCount {
                    let sample = abs(floatPtr[i])
                    maxLevel = max(maxLevel, sample)
                    sumLevel += sample
                }
                let avgLevel = checkCount > 0 ? (sumLevel / Float(checkCount)) : 0
                print("🎤 音频电平: max=\(String(format: "%.6f", maxLevel)), avg=\(String(format: "%.6f", avgLevel)), frames=\(pcmBuffer.frameLength) (缓冲区 #\(buffersProcessed))")
            }
        }

        if !didFallbackToRawAppend, let targetFormat = targetFormat, let converter = audioConverter {
            // 转换格式（48kHz交错 → 16kHz非交错单声道）
            if let convertedBuffer = convertAudioFormat(pcmBuffer, converter: converter, targetFormat: targetFormat) {
                recognitionRequest.append(convertedBuffer)
                buffersProcessed += 1

                // 定期输出处理状态
                if buffersProcessed == 1 || buffersProcessed % 500 == 0 {
                    print("✅ 已处理 \(buffersProcessed) 个音频缓冲区, 错误: \(processingErrors)")
                }
                return
            }

            processingErrors += 1
            if processingErrors < 10 {
                print("❌ 音频格式转换失败 #\(processingErrors)")
            }
        } else if !didFallbackToRawAppend {
            print("⚠️ 音频转换器不可用，改为直接送入Speech缓冲区")
            didFallbackToRawAppend = true
        }

        // 兜底：直接把原始PCM送给Speech，让系统自行处理重采样/声道
        if !didFallbackToRawAppend {
            print("⚠️ 音频转换失败，改为直接送入Speech缓冲区")
            didFallbackToRawAppend = true
        }

        recognitionRequest.append(pcmBuffer)
        buffersProcessed += 1
    }

    private func convertAudioFormat(_ inputBuffer: AVAudioPCMBuffer, converter: AVAudioConverter, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // 计算输出缓冲区大小
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)

        guard outputCapacity > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            return nil
        }

        var error: NSError?
        var inputExhausted = false

        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if inputExhausted {
                outStatus.pointee = .endOfStream
                return nil
            } else {
                outStatus.pointee = .haveData
                inputExhausted = true
                return inputBuffer
            }
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard error == nil, status != .error, outputBuffer.frameLength > 0 else {
            return nil
        }

        return outputBuffer
    }
}
