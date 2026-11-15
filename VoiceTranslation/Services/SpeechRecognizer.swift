//
//  SpeechRecognizer.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation
import Speech
import AVFoundation
import Combine
import ScreenCaptureKit
import CoreAudio
import AppKit
import os

@MainActor
class SpeechRecognizer: ObservableObject {
    @Published var recognizedText = ""
    @Published var finalizedText = ""
    @Published private(set) var recognitionSessionID = UUID()
    private var recognitionTaskID = UUID()
    private var recognitionTranscript = RecognitionTranscript()
    private var recoveryTask: Task<Void, Never>?
    private var recoveryAttempts = 0
    @Published private(set) var recordingStatus = "就绪"
    @Published private(set) var recordingPhase: RecordingPhase = .idle
    let audioHeartbeat = AudioHeartbeat()
    private var startupTask: Task<Void, Never>?
    private var captureRecoveryTask: Task<Void, Never>?
    private var captureGeneration = UUID()
    private var captureStartedAt = Date.distantPast
    private var captureReady = false
    private var microphonePermissionSession: UUID?
    var selectedAudioInputSource: AudioInputSource { currentAudioInputSource }
    var coreAudioCaptureStart: ((SFSpeechAudioBufferRecognitionRequest) async throws -> Void)?
    var screenCaptureAuthorization: () -> Bool = { CGPreflightScreenCaptureAccess() }
    var screenCaptureStart: ((SFSpeechAudioBufferRecognitionRequest) async throws -> Void)?
    var microphoneAuthorization: () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) }
    var requestMicrophoneAuthorization: () async -> Bool = { await AVCaptureDevice.requestAccess(for: .audio) }
    var isWaitingForMicrophonePermission: Bool { microphonePermissionSession != nil }
    private var sleeping = false
    private var captureRecoveryAttempts = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    @Published var isRecording = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var isListening = false

    // 权限管理和状态监控（暂时禁用，直接使用CGRequestScreenCaptureAccess）
    // private let permissionManager = PermissionManager.shared
    @Published var audioSourceStatus: String = "未知"
    @Published var permissionStatusMessage: String = ""
    @Published var fallbackMessage: String = ""

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private let captureLogger = Logger(subsystem: "com.voicetranslation.audio", category: "RecordingRecovery")
    private var microphoneTapInstalled = false
    private var preparingMicrophoneEngines = Set<ObjectIdentifier>()
    private var systemAudioCapture: Any? // 使用Any来避免版本检查问题 (ScreenCaptureKit)
    private var coreAudioTapCapture: Any? // Core Audio Tap捕获器 (macOS 14.2+)
    private var currentLanguage: String = "en-US"
    private var currentAudioInputSource: AudioInputSource = .microphone
    private var lastOutputText = ""  // 记录上次输出的文本，避免重复输出
    private var lastDisplayedLength = 0  // 记录上次显示的文本长度
    private var forceServerRecognitionForSystemAudio = false

    /// 是否使用Core Audio Tap（用于静音模式下的音频捕获）
    private var useCoreAudioTap: Bool {
        if #available(macOS 14.2, *) {
            return true
        }
        return false
    }
    
    // 音频设备管理器
    let audioDeviceManager = AudioDeviceManager()
    
    // 音频质量监控（暂时禁用）
    // private var audioQualityMonitor = AudioQualityMonitor()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupPermissionMonitoring()
        // 只检查权限状态，不触发请求弹窗
        checkAuthorizationStatus()

        // 监听音频设备变化
        audioDeviceManager.$currentInputDevice
            .map { $0?.uid }.removeDuplicates().dropFirst()
            .debounce(for: .milliseconds(800), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.currentAudioInputSource == .microphone else { return }
                self.scheduleCaptureRecovery(reason: "麦克风发生变化，正在恢复收音")
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, self.captureReady, let changed = notification.object as? AVAudioEngine,
                      changed === self.audioEngine else { return }
                self.scheduleCaptureRecovery(reason: "声音设备发生变化，正在恢复收音")
            }.store(in: &cancellables)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepareForSleep() }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterWake() }
        })
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] now in self?.checkCaptureHealth(at: now) }.store(in: &cancellables)
    }
    
    deinit {
        startupTask?.cancel()
        captureRecoveryTask?.cancel()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        recoveryTask?.cancel()
        // deinit 是非 actor 隔离上下文，做最小同步清理，避免异步闭包持有 self
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if #available(macOS 14.2, *), let capture = coreAudioTapCapture as? CoreAudioTapCapture {
            capture.cleanup()
        }
        coreAudioTapCapture = nil

        if #available(macOS 12.3, *), let capture = systemAudioCapture as? SystemAudioCapture {
            capture.stop()
        }
        systemAudioCapture = nil

        if !preparingMicrophoneEngines.contains(ObjectIdentifier(audioEngine)), audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }
    
    // MARK: - Public Methods

    /// 仅检查权限状态，不触发系统权限请求弹窗
    func checkAuthorizationStatus() {
        let status = SFSpeechRecognizer.authorizationStatus()
        authorizationStatus = status
        if status == .authorized {
            setupSpeechRecognizer()
        }
        print("🔍 语音识别权限状态检查: \(status.rawValue)")
    }

    /// 主动请求权限（只在用户明确操作时调用）
    func requestAuthorization() {
        // 先检查当前状态
        let currentStatus = SFSpeechRecognizer.authorizationStatus()

        // 如果已经授权，直接更新状态并返回
        if currentStatus == .authorized {
            authorizationStatus = currentStatus
            setupSpeechRecognizer()
            print("✅ 语音识别权限已授权")
            return
        }

        // 如果已被拒绝，无法再次请求
        if currentStatus == .denied || currentStatus == .restricted {
            authorizationStatus = currentStatus
            print("⚠️ 语音识别权限已被拒绝，请用户手动在系统设置中开启")
            return
        }

        // 只有在状态为 notDetermined 时才触发请求
        print("🔐 正在请求语音识别权限...")
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                self?.authorizationStatus = authStatus
                if authStatus == .authorized {
                    self?.setupSpeechRecognizer()
                    print("✅ 语音识别权限请求成功")
                } else {
                    print("❌ 语音识别权限请求失败: \(authStatus.rawValue)")
                }
            }
        }
    }
    
    private(set) var recognitionHints: [String] = []

    /// Hints bias recognition; they never replace recognized words or human edits.
    func setRecognitionGlossary(_ terms: [GlossaryTerm], direction: LanguageDirection) {
        var seen = Set<String>()
        recognitionHints = terms.compactMap { term in
            let value = term.pair(for: direction).source
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard !value.isEmpty, value.count <= 80, value.split(separator: " ").count <= 8,
                  seen.insert(value.lowercased()).inserted else { return nil }
            return value
        }.prefix(100).map { $0 }
        recognitionRequest?.contextualStrings = recognitionHints
    }

    func setLanguage(_ languageCode: String) {
        currentLanguage = languageCode
        setupSpeechRecognizer()
    }
    
    func setAudioInputSource(_ source: AudioInputSource) {
        // 防止重复设置相同的音频源
        guard currentAudioInputSource != source else { 
            return 
        }
        
        currentAudioInputSource = source
        print("切换音频输入源到: \(source.displayName)")
        
        // 如果正在录音，重新启动以应用新的音频源
        if isRecording {
            print("正在重新启动音频引擎以应用新的输入源...")
            let wasRecording = true
            stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                if wasRecording {
                    self?.startRecording()
                }
            }
        }
    }
    
    /// 诊断系统音频权限问题
    public func diagnoseSystemAudioPermissions() async -> String {
        if #available(macOS 12.3, *) {
            let capture = SystemAudioCapture()
            return await capture.diagnosePermissions()
        } else {
            return "系统版本不支持系统音频捕获（需要 macOS 12.3+）"
        }
    }
    
    /// 强制刷新系统音频权限
    public func forceRefreshSystemAudioPermissions() async -> Bool {
        if #available(macOS 12.3, *) {
            let capture = SystemAudioCapture()
            return await capture.forceRefreshPermissions()
        } else {
            return false
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        guard authorizationStatus == .authorized else {
            setRecordingPhase(.failed, message: "尚未获得语音权限，请先授权")
            return
        }
        isRecording = true // User intent; recordingPhase reports actual capture readiness.
        isListening = false
        captureRecoveryAttempts = 0
        launchCapture(recovering: false)
    }

    private func launchCapture(recovering: Bool) {
        // A stopped or slow new capture must never expose the previous attempt's text.
        recognizedText = ""
        let generation = UUID()
        captureGeneration = generation
        captureReady = false
        captureStartedAt = Date()
        audioHeartbeat.reset()
        setRecordingPhase(recovering ? .recovering : .starting)
        startupTask = Task { [weak self] in
            guard let self, !Task.isCancelled,
                  self.captureGeneration == generation, self.isRecording else { return }
            do {
                try await self.startRecognitionSession()
                guard !Task.isCancelled, self.captureGeneration == generation, self.isRecording else { return }
                self.captureReady = true
                self.captureStartedAt = Date()
                self.setRecordingPhase(.waiting)
            } catch {
                guard !Task.isCancelled, self.captureGeneration == generation, self.isRecording else { return }
                self.startupTask = nil
                let failure = error as NSError
                self.captureLogger.error("Capture startup failed: \(failure.domain, privacy: .public)/\(failure.code)")
                if let audioError = error as? SystemAudioError, !audioError.isRetryable {
                    self.stopRecording()
                    self.setRecordingPhase(.failed, message: "系统音频未能开启，请检查权限后重试；麦克风未开启")
                } else {
                    self.scheduleCaptureRecovery(reason: "收音暂时中断，正在重新连接")
                }
            }
        }
    }

    func stopRecording() {
        microphonePermissionSession = nil
        isRecording = false
        sleeping = false
        startupTask?.cancel()
        startupTask = nil
        captureRecoveryTask?.cancel()
        captureRecoveryTask = nil
        captureGeneration = UUID()
        stopCaptureResources()
        setRecordingPhase(.idle)
    }

    private func stopCaptureResources() {
        captureReady = false
        isListening = false
        recoveryTask?.cancel()
        recoveryTask = nil
        recognitionTaskID = UUID()
        recognitionSessionID = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if #available(macOS 14.2, *), let capture = coreAudioTapCapture as? CoreAudioTapCapture {
            capture.stop()
        }
        coreAudioTapCapture = nil
        if #available(macOS 12.3, *), let capture = systemAudioCapture as? SystemAudioCapture {
            capture.stop()
        }
        systemAudioCapture = nil
        // Even isRunning takes the engine's internal lock. A Bluetooth bind may
        // hold that lock indefinitely, so never touch a still-preparing engine here.
        if preparingMicrophoneEngines.contains(ObjectIdentifier(audioEngine)) {
            audioEngine = AVAudioEngine()
            microphoneTapInstalled = false
        } else if audioEngine.isRunning {
            audioEngine.stop()
        }
        if microphoneTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            microphoneTapInstalled = false
        }
        lastOutputText = ""
        lastDisplayedLength = 0
    }

    private func setRecordingPhase(_ phase: RecordingPhase, message: String? = nil) {
        let status = message ?? phase.message
        if recordingPhase != phase || recordingStatus != status {
            captureLogger.info("Recording state: \(phase.rawValue, privacy: .public)")
        }
        recordingPhase = phase
        recordingStatus = status
        isListening = phase == .waiting || phase == .receiving
    }

    func checkCaptureHealth(at now: Date) {
        guard isRecording, !sleeping, !isWaitingForMicrophonePermission else { return }
        if !captureReady {
            if startupTask != nil && now.timeIntervalSince(captureStartedAt) > 45 {
                scheduleCaptureRecovery(reason: "收音准备时间过长，正在重新连接")
            }
            return
        }
        guard recoveryTask == nil else { return }
        let sample = audioHeartbeat.snapshot()
        // Silent buffers are healthy. Recover only when buffers stop arriving.
        if now.timeIntervalSince(sample.bufferAt ?? captureStartedAt) > 8 {
            scheduleCaptureRecovery(reason: "声音输入已中断，正在恢复")
        } else if let soundAt = sample.soundAt, now.timeIntervalSince(soundAt) < 2 {
            captureRecoveryAttempts = 0
            setRecordingPhase(.receiving)
        } else {
            if sample.bufferAt != nil { captureRecoveryAttempts = 0 }
            setRecordingPhase(.waiting)
        }
    }

    func scheduleCaptureRecovery(reason: String) {
        guard isRecording, !sleeping, captureRecoveryTask == nil else { return }
        captureRecoveryAttempts += 1
        startupTask?.cancel()
        startupTask = nil
        captureGeneration = UUID()
        stopCaptureResources()
        guard captureRecoveryAttempts <= 5 else {
            isRecording = false
            setRecordingPhase(.failed, message: "声音输入未能恢复，请检查设备后重新开始")
            return
        }
        setRecordingPhase(.recovering, message: reason)
        let delay = UInt64(min(captureRecoveryAttempts, 5)) * 1_000_000_000
        captureRecoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.isRecording, !self.sleeping else { return }
            self.captureRecoveryTask = nil
            self.launchCapture(recovering: true)
        }
    }

    func prepareForSleep() {
        guard isRecording else { return }
        sleeping = true
        startupTask?.cancel()
        startupTask = nil
        captureRecoveryTask?.cancel()
        captureRecoveryTask = nil
        captureGeneration = UUID()
        stopCaptureResources()
        setRecordingPhase(.sleeping)
    }

    func resumeAfterWake() {
        guard sleeping, isRecording else { return }
        sleeping = false
        captureRecoveryAttempts = 0
        scheduleCaptureRecovery(reason: "电脑已唤醒，正在恢复收音")
    }

    // MARK: - Private Methods
    
    private func setupSpeechRecognizer() {
        let locale = Locale(identifier: currentLanguage)
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        
        // 根据音频源设置默认任务提示
        if currentAudioInputSource == .systemAudio {
            speechRecognizer?.defaultTaskHint = .dictation
        } else {
            speechRecognizer?.defaultTaskHint = .search
        }
        
        // 确保语音识别器可用
        if speechRecognizer?.isAvailable != true {
            print("⚠️ 语音识别器不可用，语言: \(currentLanguage)")
        }
    }

    func configureRecognitionRequest(_ request: SFSpeechAudioBufferRecognitionRequest) {
        request.shouldReportPartialResults = true
        request.contextualStrings = recognitionHints

        if currentAudioInputSource == .systemAudio {
            if #available(macOS 13.0, *) {
                let supportsOnDevice = speechRecognizer?.supportsOnDeviceRecognition ?? false
                let useOnDevice = supportsOnDevice && !forceServerRecognitionForSystemAudio
                request.requiresOnDeviceRecognition = useOnDevice
                request.addsPunctuation = false
            }

            request.taskHint = .dictation
        } else {
            if #available(macOS 13.0, *) {
                request.requiresOnDeviceRecognition = false
                request.addsPunctuation = true
            }

            request.taskHint = .search
        }
    }

    private func isSystemAudioCaptureActive() -> Bool {
        if #available(macOS 14.2, *), let tap = coreAudioTapCapture as? CoreAudioTapCapture {
            return tap.isCapturing
        }
        if #available(macOS 12.3, *), let capture = systemAudioCapture as? SystemAudioCapture {
            return capture.isCapturing
        }
        return false
    }

    private func updateActiveSystemAudioRecognitionRequestIfNeeded(_ request: SFSpeechAudioBufferRecognitionRequest) {
        guard currentAudioInputSource == .systemAudio else { return }

        if #available(macOS 14.2, *), let tap = coreAudioTapCapture as? CoreAudioTapCapture {
            tap.updateRecognitionRequest(request)
        }
        if #available(macOS 12.3, *), let capture = systemAudioCapture as? SystemAudioCapture {
            capture.updateRecognitionRequest(request)
        }
    }
    
    private func startRecognitionSession() async throws {
        print("开始识别会话...")
        
        beginRecognitionTranscript()
        recognitionTaskID = UUID()
        let sessionID = recognitionTaskID
        // 重置之前的任务
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // 检查语音识别器状态
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("语音识别器不可用")
            throw TranslationError.audioEngineError
        }
        
        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("无法创建识别请求")
            throw TranslationError.audioEngineError
        }
        
        configureRecognitionRequest(recognitionRequest)
        
        // 根据音频源类型设置和启动音频捕获
        if currentAudioInputSource == .systemAudio {
            // 首先尝试使用Core Audio Tap (macOS 14.2+)
            // Core Audio Tap 捕获 pre-mixer 音频，即使系统静音也能正常工作
            if #available(macOS 14.2, *) {
                print("🔊 启动Core Audio Tap系统音频捕获（支持静音模式）...")

                do {
                    if let coreAudioCaptureStart {
                        try await coreAudioCaptureStart(recognitionRequest)
                    } else {
                        let tapCapture = CoreAudioTapCapture()
                        coreAudioTapCapture = tapCapture
                        tapCapture.audioHeartbeat = audioHeartbeat
                        try await tapCapture.setupSystemAudioCapture(with: recognitionRequest)
                        guard !Task.isCancelled, self.recognitionTaskID == sessionID else { tapCapture.cleanup(); throw CancellationError() }
                        try await tapCapture.start()
                        guard !Task.isCancelled, self.recognitionTaskID == sessionID else { tapCapture.cleanup(); throw CancellationError() }

                    }
                    print("✅ Core Audio Tap捕获启动成功（静音模式下仍可捕获音频）")

                    // 添加延迟确保稳定运行
                    try await Task.sleep(nanoseconds: 200_000_000) // 200ms

                } catch {
                    if Task.isCancelled || self.recognitionTaskID != sessionID { throw CancellationError() }
                    print("❌ Core Audio Tap设置失败: \(error.localizedDescription)")
                    print("📱 尝试回退到ScreenCaptureKit...")

                    // 清理Core Audio Tap
                    if let tap = coreAudioTapCapture as? CoreAudioTapCapture {
                        tap.cleanup()
                    }
                    coreAudioTapCapture = nil

                    // 回退到ScreenCaptureKit
                    try await fallbackToScreenCaptureKit(recognitionRequest)
                }
            } else {
                // macOS 12.3 - 14.1: 使用ScreenCaptureKit
                guard #available(macOS 12.3, *) else {
                    print("❌ 系统音频模式需要macOS 12.3或更高版本，已停止收音")
                    throw SystemAudioError.systemVersionUnsupported
                }

                try await fallbackToScreenCaptureKit(recognitionRequest)
            }
        } else {
            // 麦克风模式：设置并启动音频引擎
            try await prepareAndStartMicrophone()
        }
        
        print("音频引擎启动成功，创建识别任务...")
        
        guard isRecording, recognitionTaskID == sessionID else { return }
        recognizedText = ""
        // 开始识别任务
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionResult(result: result, error: error, sessionID: sessionID)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.recognizedText = ""
            self?.lastOutputText = ""  // 重置输出状态
            self?.lastDisplayedLength = 0  // 重置显示长度
            print("\n开始新的语音识别会话...")
        }
    }
    
    @available(macOS 12.3, *)
    private func setupSystemAudioCapture(_ recognitionRequest: SFSpeechAudioBufferRecognitionRequest) async throws {
        guard let capture = systemAudioCapture as? SystemAudioCapture else {
            throw TranslationError.audioEngineError
        }
        
        try await capture.setupSystemAudioCapture(with: recognitionRequest)
        print("系统音频捕获设置完成")
    }
    
    /// Ask before constructing an input node: its synchronous driver setup can otherwise
    /// wait on TCC while holding audio-system resources, even though the app is responsive.
    func ensureMicrophonePermission() async throws {
        let sessionID = recognitionTaskID
        let permission = microphoneAuthorization()
        if permission == .authorized { return }
        var granted = false
        if permission == .notDetermined {
            microphonePermissionSession = sessionID
            setRecordingPhase(.starting, message: "请在系统提示中允许麦克风，允许后会继续收音")
            defer { if microphonePermissionSession == sessionID { microphonePermissionSession = nil } }
            granted = await requestMicrophoneAuthorization()
        }
        try Task.checkCancellation()
        guard recognitionTaskID == sessionID, isRecording else { throw CancellationError() }
        guard granted else {
            stopRecording()
            setRecordingPhase(.failed, message: "麦克风尚未授权，请在系统设置中允许后重试")
            throw CancellationError()
        }
        captureStartedAt = Date()
        setRecordingPhase(.starting)
    }

    private func prepareAndStartMicrophone() async throws {
        guard currentAudioInputSource == .microphone else { throw SystemAudioError.permissionDenied }
        try await ensureMicrophonePermission()
        let sessionID = recognitionTaskID
        // A disconnected Bluetooth route must not survive in a reused audio engine.
        audioEngine = AVAudioEngine()
        let engine = audioEngine
        let engineID = ObjectIdentifier(engine)
        preparingMicrophoneEngines.insert(engineID)
        // Binding a Bluetooth microphone can block inside the audio driver. Keep the
        // window responsive while that happens, then validate intent before starting.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Give each attempt its own queue: a stuck old route must not block
            // preparation of the new default device after a disconnect.
            DispatchQueue(label: "VoiceTranslation.MicrophonePreparation.\(UUID())").async {
                _ = engine.inputNode
                continuation.resume()
            }
        }
        preparingMicrophoneEngines.remove(engineID)
        try Task.checkCancellation()
        guard isRecording, recognitionTaskID == sessionID, audioEngine === engine else { throw CancellationError() }
        try setupMicrophoneAudioEngine()
        try startMicrophoneEngine()
    }

    private func setupMicrophoneAudioEngine() throws {
        try setupAudioEngine()
        print("麦克风音频引擎设置完成")
    }

    /// 回退到ScreenCaptureKit进行系统音频捕获
    @available(macOS 12.3, *)
    func fallbackToScreenCaptureKit(_ recognitionRequest: SFSpeechAudioBufferRecognitionRequest) async throws {
        // Failure may retry this source, but must never expand capture to the room.
        guard screenCaptureAuthorization() else { throw SystemAudioError.permissionDenied }
        if let screenCaptureStart {
            try await screenCaptureStart(recognitionRequest)
            return
        }
        let capture = SystemAudioCapture()
        capture.audioHeartbeat = audioHeartbeat
        systemAudioCapture = capture
        try await setupSystemAudioCaptureWithRetry(recognitionRequest)
        try await startSystemAudioCaptureWithRetry()
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    private func startMicrophoneEngine() throws {
        // 准备并启动音频引擎
        print("准备音频引擎...")
        
        // 在准备之前，先重置音频引擎以清除可能的旧状态
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
            print("重置音频引擎")
        }
        
        audioEngine.prepare()
        
        print("启动音频引擎...")
        
        // 尝试启动音频引擎，如果失败则重试一次
        do {
            try audioEngine.start()
        } catch {
            print("⚠️ 首次启动失败，错误: \(error)")
            
            // 如果是格式错误，尝试重新配置
            if (error as NSError).code == -10868 {
                print("🔧 检测到格式错误，尝试重新配置...")
                
                // 移除旧的tap并重新配置
                let inputNode = audioEngine.inputNode
                inputNode.removeTap(onBus: 0)
                
                // 重置引擎
                audioEngine.reset()
                
                // 重新设置音频引擎
                try setupAudioEngine()
                
                // 准备并重试启动
                audioEngine.prepare()
                try audioEngine.start()
                print("✅ 音频引擎重新配置并启动成功")
            } else {
                // 其他错误直接抛出
                throw error
            }
        }
        
        print("麦克风音频引擎启动成功")
    }
    
    private func setupAudioEngine() throws {
        print("🎤 配置麦克风音频引擎")
        
        // 使用麦克风输入
        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        print("硬件格式: \(hardwareFormat)")
        
        // 检查录音格式是否有效
        guard hardwareFormat.sampleRate > 0 && hardwareFormat.channelCount > 0 else {
            print("无效的录音格式: \(hardwareFormat)")
            throw TranslationError.audioEngineError
        }
        
        // 在安装新tap之前，先移除可能存在的旧tap
        inputNode.removeTap(onBus: 0)
        print("已移除旧的音频tap")
        
        print("安装新的音频tap...")
        
        // 使用更大的缓冲区大小来减少音频处理负载
        let bufferSize: AVAudioFrameCount = 4096  // 增加缓冲区大小
        
        // 创建兼容的音频格式
        // 语音识别通常需要16kHz单声道，但我们应该使用硬件支持的格式
        let recordingFormat: AVAudioFormat
        
        // 检查硬件格式并创建兼容格式
        if let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: hardwareFormat.sampleRate,
                                       channels: 1,
                                       interleaved: false) {
            recordingFormat = format
            print("使用音频格式: 采样率=\(recordingFormat.sampleRate)Hz, 通道数=\(recordingFormat.channelCount)")
        } else {
            // 如果创建格式失败，使用硬件格式
            recordingFormat = hardwareFormat
            print("使用硬件默认格式: \(recordingFormat)")
        }
        
        // 使用明确的格式安装tap，避免格式不匹配
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] (buffer, when) in
            // 检查缓冲区是否有效
            guard buffer.frameLength > 0 else { return }
            self?.audioHeartbeat.observe(buffer)
            self?.recognitionRequest?.append(buffer)
        }
        microphoneTapInstalled = true
        print("音频tap安装完成，缓冲区大小: \(bufferSize), 格式: \(recordingFormat)")
    }
    
    private func restartRecognitionTask() {
        guard isRecording, audioEngine.isRunning || isSystemAudioCaptureActive() else { return }
        recoveryTask?.cancel()
        recoveryTask = nil
        beginRecognitionTranscript()
        recognitionTaskID = UUID()
        let sessionID = recognitionTaskID
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        // Replace the request immediately while capture keeps running: no half-second audio gap.
        let request = SFSpeechAudioBufferRecognitionRequest()
        configureRecognitionRequest(request)
        recognitionRequest = request
        updateActiveSystemAudioRecognitionRequestIfNeeded(request)
        recognizedText = ""
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognitionResult(result: result, error: error, sessionID: sessionID)
        }
        setRecordingPhase(.waiting)
    }

    private func recoverRecognitionTask() {
        guard recoveryTask == nil, isRecording else { return }
        let taskID = recognitionTaskID
        recoveryAttempts += 1
        if recoveryAttempts > 5 {
            scheduleCaptureRecovery(reason: "语音识别未能恢复，正在重新连接收音")
            recoveryAttempts = 0
            return
        }
        setRecordingPhase(.recovering, message: "语音识别暂时中断，正在恢复")
        let delay = UInt64(recoveryAttempts) * 500_000_000
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.recognitionTaskID == taskID else { return }
            self.recoveryTask = nil
            self.restartRecognitionTask()
        }
    }

    private func beginRecognitionTranscript() {
        recognitionSessionID = UUID()
        recognitionTranscript = RecognitionTranscript()
        lastOutputText = ""
        lastDisplayedLength = 0
    }

    func clearRecognizedText() {
        recognizedText = ""
        if isRecording { restartRecognitionTask() }
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?, sessionID: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording, self.recognitionTaskID == sessionID else { return }
            
            if let error = error {
                let nsError = error as NSError
                let errorMessage = error.localizedDescription
                NSLog("Speech recognition error: %@/%ld", nsError.domain, nsError.code)
                
                // Capture may still be healthy after the recognition request has failed.
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1101 {
                    // The failed recognition task is terminal even while capture keeps running.
                    self.recoverRecognitionTask()
                    return
                }
                
                // 本地/离线识别不可用时，系统音频尝试回退到在线识别
                if errorMessage.contains("com.apple.speech.localspeechrecognition") ||
                    errorMessage.contains("speechRecordingDidFail") ||
                    errorMessage.lowercased().contains("on-device") ||
                    errorMessage.lowercased().contains("on device") {
                    if self.currentAudioInputSource == .systemAudio && !self.forceServerRecognitionForSystemAudio {
                        print("⚠️ 本地识别不可用，切换到在线识别")
                        self.forceServerRecognitionForSystemAudio = true
                        self.restartRecognitionTask()
                        return
                    }
                    
                    // 这些是非致命错误，继续监听
                    self.recoverRecognitionTask()
                    return
                }
                
                // 只输出非 1101 错误
                print("语音识别错误: \(errorMessage)")
                
                // 对于实时翻译模式，某些错误不应该停止录音
                if errorMessage.contains("No speech detected") {
                    if self.currentAudioInputSource == .systemAudio {
                        print("提示：系统音频模式下未检测到语音，继续监听...")
                        print("请确保：")
                        print("1. 有音频正在播放（如音乐、视频等）")
                        print("2. 或切换到麦克风模式进行测试")
                        print("注意：Core Audio Tap模式支持静音状态下的音频捕获")
                    } else {
                        print("提示：暂时未检测到语音输入，继续监听...")
                    }
                    
                    // 不停止录音，继续监听
                    self.recoverRecognitionTask()
                    return
                } else if errorMessage.contains("Recognition request was canceled") {
                    // 识别请求被取消，这通常是由于音频源切换或系统操作引起的
                    print("识别请求被取消，准备重新开始识别...")
                    
                    // 重新启动识别任务而不是完全停止录音
                    self.restartRecognitionTask()
                    return
                }
                
                self.scheduleCaptureRecovery(reason: "语音识别暂时中断，正在恢复")
                return
            }
            
            if let result = result {
                self.recoveryAttempts = 0
                self.recoveryTask?.cancel()
                self.recoveryTask = nil
                let recognizedString = result.bestTranscription.formattedString
                let segments = result.bestTranscription.segments
                let first = segments.first?.timestamp
                let end = segments.last.map { $0.timestamp + $0.duration }
                let transcript = self.recognitionTranscript.observe(recognizedString, start: first, end: end)
                self.recognizedText = transcript
                
                // 实时输出语音识别内容（只输出新增的词汇）
                if !recognizedString.isEmpty {
                    // 只输出超过上次显示长度的新增内容
                    if recognizedString.count > self.lastDisplayedLength {
                        let newContent = String(recognizedString.dropFirst(self.lastDisplayedLength))
                        if !newContent.trimmingCharacters(in: .whitespaces).isEmpty {
                            // Transcript content stays in the conversation, never in console logs.
                            self.lastDisplayedLength = recognizedString.count
                        }
                    }
                    self.lastOutputText = recognizedString
                }
                
                // 在实时翻译模式下，不要因为结果是最终的就停止监听
                // 让用户通过空格键或手动停止来控制
                if result.isFinal || (end ?? 0) > (first ?? 0) {
                    self.finalizedText = transcript
                }
                if result.isFinal {
                    print(" | ")  // 简单分隔符表示识别完成
                    self.lastOutputText = ""  // 重置，准备下一段识别
                    self.lastDisplayedLength = 0  // 重置显示长度
                    self.restartRecognitionTask()
                }
                
                self.isListening = true
            }
        }
    }
    
    // MARK: - Enhanced Error Handling
    
    /// 带重试机制的系统音频设置
    @available(macOS 12.3, *)
    private func setupSystemAudioCaptureWithRetry(_ recognitionRequest: SFSpeechAudioBufferRecognitionRequest, maxRetries: Int = 3) async throws {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                if let capture = systemAudioCapture as? SystemAudioCapture {
                    try await capture.setupSystemAudioCapture(with: recognitionRequest)
                    print("✅ 系统音频设置成功 (尝试 \(attempt)/\(maxRetries))")
                    return
                }
            } catch {
                lastError = error
                print("❌ 系统音频设置失败 (尝试 \(attempt)/\(maxRetries)): \(error.localizedDescription)")
                
                // 如果不是最后一次尝试，等待一段时间后重试
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000) // 递增延迟：500ms, 1s, 1.5s
                    print("⏳ 等待 \(attempt * 500)ms 后重试...")
                }
            }
        }
        
        // 所有重试都失败，抛出最后的错误
        if let error = lastError {
            throw error
        }
        throw TranslationError.audioEngineError
    }
    
    /// 带重试机制的系统音频启动
    @available(macOS 12.3, *)
    private func startSystemAudioCaptureWithRetry(maxRetries: Int = 2) async throws {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                if let capture = systemAudioCapture as? SystemAudioCapture {
                    try await capture.start()
                    print("✅ 系统音频启动成功 (尝试 \(attempt)/\(maxRetries))")
                    return
                }
            } catch {
                lastError = error
                print("❌ 系统音频启动失败 (尝试 \(attempt)/\(maxRetries)): \(error.localizedDescription)")
                
                // 如果不是最后一次尝试，等待后重试
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: 300_000_000) // 300ms
                    print("⏳ 等待 300ms 后重试启动...")
                }
            }
        }
        
        // 所有重试都失败，抛出最后的错误
        if let error = lastError {
            throw error
        }
        throw TranslationError.audioEngineError
    }
    
    /// 安全的异步任务取消
    private func safeAsyncCancel<T>(_ task: Task<T, Error>) {
        if !task.isCancelled {
            task.cancel()
        }
    }
    
    // MARK: - Permission Management
    
    private func setupPermissionMonitoring() {
        // 权限监控功能暂时禁用
    }
    
    // 暂时禁用
    // private func handlePermissionChange(_ change: PermissionStatusChange) { ... }
    
    // 暂时禁用
    // private func convertPermissionStatusToSF(_ status: PermissionStatus) -> SFSpeechRecognizerAuthorizationStatus { ... }
    
    // 暂时禁用
    // private func updatePermissionStatusMessage(speech: PermissionStatus, microphone: PermissionStatus) { ... }
    
    // 暂时禁用
    // private func checkSystemAudioAvailability() async { ... }
    
    private func showFallbackMessage(_ message: String) {
        fallbackMessage = message
        
        // 10秒后自动清除消息（延长显示时间）
        Task {
            try await Task.sleep(nanoseconds: 10_000_000_000) // 10秒
            if self.fallbackMessage == message {
                self.fallbackMessage = ""
            }
        }
    }
    
    // MARK: - Audio Quality Report
    
    /// 获取音频质量报告（暂时禁用）
    func getAudioQualityReport() -> String {
        return "音频质量监控功能暂时禁用"
    }
    
    /// 重置音频质量数据（暂时禁用）
    func resetAudioQualityData() {
        // 功能暂时禁用
    }
}


enum RecordingPhase: String {
    case idle, starting, waiting, receiving, recovering, sleeping, failed
    var message: String {
        switch self {
        case .idle: return "就绪"
        case .starting: return "正在准备收音..."
        case .waiting: return "收音已准备好，等待声音"
        case .receiving: return "已收到声音"
        case .recovering: return "正在恢复收音..."
        case .sleeping: return "电脑休眠中，唤醒后继续"
        case .failed: return "收音已停止，请检查设备后重试"
        }
    }
}

/// Audio callbacks write only a tiny locked snapshot, without touching the main thread.
final class AudioHeartbeat {
    private let lock = NSLock()
    private var bufferAt: Date?
    private var soundAt: Date?
    func reset() { lock.lock(); defer { lock.unlock() }; bufferAt = nil; soundAt = nil }
    func mark(hasSound: Bool, at now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        bufferAt = now
        if hasSound { soundAt = now }
    }
    func snapshot() -> (bufferAt: Date?, soundAt: Date?) {
        lock.lock(); defer { lock.unlock() }; return (bufferAt, soundAt)
    }
    func observe(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        var hasSound = false
        if let samples = buffer.floatChannelData?[0] {
            for i in stride(from: 0, to: Int(buffer.frameLength), by: 8) where abs(samples[i]) > 0.002 {
                hasSound = true; break
            }
        }
        mark(hasSound: hasSound)
    }
}
