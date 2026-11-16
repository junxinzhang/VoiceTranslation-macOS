//
//  MainView.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//  Redesigned with modern minimal style on 2026-01-23.
//

import SwiftUI

struct MainView: View {
    @ObservedObject var speechRecognizer: SpeechRecognizer
    @ObservedObject var translationService: TranslationService
    @ObservedObject var historyManager: HistoryManager
    @ObservedObject var appSettings: AppSettings
    @ObservedObject var errorHandler: ErrorHandler

    @StateObject private var viewModel: MainViewModel
    @StateObject private var floatingOverlayController = FloatingOverlayWindowController()
    @State private var showPermissionGuide = false
    @State private var showAudioQuality = false
    @State private var sessionExport: ExportRequest?
    @State private var editingEntry: TranslationEntryModel?
    @State private var originalDraft = ""
    @State private var editError = ""
    @State private var rememberWordCorrection = false
    @State private var keyMonitor: Any?


    init(
        speechRecognizer: SpeechRecognizer,
        translationService: TranslationService,
        historyManager: HistoryManager,
        appSettings: AppSettings,
        errorHandler: ErrorHandler
    ) {
        self.speechRecognizer = speechRecognizer
        self.translationService = translationService
        self.historyManager = historyManager
        self.appSettings = appSettings
        self.errorHandler = errorHandler
        _viewModel = StateObject(
            wrappedValue: MainViewModel(
                speechRecognizer: speechRecognizer,
                translationService: translationService,
                historyManager: historyManager,
                appSettings: appSettings,
                errorHandler: errorHandler
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            if !historyManager.saveError.isEmpty {
                Text(historyManager.saveError).foregroundColor(.red).padding(.horizontal)
            }
            if !viewModel.restoredConversationMessage.isEmpty {
                Text(viewModel.restoredConversationMessage).font(.caption).foregroundColor(.secondary)
            }
            // Main Content
            VStack(spacing: 20) {
                // Language Direction Selector
                languageDirectionSelector

                // Audio Input Toggle
                audioInputToggle

                // Translation Log Card
                translationLogCard

                // Record Button
                recordButton
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom Bar
            bottomBar
        }
        .background(Constants.Colors.bgPrimary)
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                appSettings: appSettings,
                translationService: translationService,
                conversation: viewModel
            )
        }
        .sheet(isPresented: $viewModel.showHistory) {
            HistoryView(historyManager: viewModel.historyManager, onRestore: { viewModel.restoreConversation($0) }, canRestore: !speechRecognizer.isRecording)
        }
        .sheet(item: $sessionExport) { request in
            ExportView(
                title: "导出本次识别记录",
                subtitle: "以下是本次识别和翻译内容：",
                exportText: request.text,
                defaultFilename: "本次识别记录_\(Date().formatted(date: .numeric, time: .omitted))"
            )
        }
        .sheet(item: $editingEntry) { entry in
            VStack(alignment: .leading, spacing: 16) {
                Text("修改原文").font(.title2)
                Text("保存后会自动更新译文。后续识别不会覆盖你修改的这一段。")
                    .font(.callout).foregroundColor(.secondary)
                TextEditor(text: $originalDraft)
                    .accessibilityLabel("原文内容")
                    .font(.body)
                    .frame(minHeight: 150)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                if let proposal = viewModel.correctionProposal(for: entry.id, text: originalDraft) {
                    Toggle("记住人名或术语纠正：\(proposal.heard) → \(proposal.preferred)", isOn: $rememberWordCorrection)
                    Text("下次优先参考正确写法；再次听到旧写法时提供建议，不会自行替换原文。")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("数字、币种和整句改写不会保存成纠错记忆。").font(.caption).foregroundColor(.secondary)
                }
                if !editError.isEmpty { Text(editError).foregroundColor(.red).font(.caption) }
                HStack {
                    Text("仅修改这一段，其他内容继续识别和翻译。")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("取消") { editingEntry = nil }.keyboardShortcut(.cancelAction)
                    Button("保存并更新译文") {
                        let eligible = viewModel.correctionProposal(for: entry.id, text: originalDraft) != nil
                        if viewModel.updateOriginalText(entryID: entry.id, text: originalDraft, rememberCorrection: rememberWordCorrection && eligible) {
                            editingEntry = nil
                        } else { editError = viewModel.vocabularyMessage.isEmpty ? "请填写有效原文（最多 4000 个字），或关闭后重新打开这一段。" : viewModel.vocabularyMessage }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 620, height: 460)
        }
        .onChange(of: viewModel.showFloatingWindow) { show in
            if show {
                floatingOverlayController.show(viewModel: viewModel)
                viewModel.showFloatingWindow = false
            }
        }
        .sheet(isPresented: $showPermissionGuide) {
            PermissionGuideView(isPresented: $showPermissionGuide)
        }
        .sheet(isPresented: $showAudioQuality) {
            AudioQualityView(
                audioQualityMonitor: viewModel.audioQualityMonitor,
                isPresented: $showAudioQuality
            )
        }
        .alert("错误", isPresented: $viewModel.errorHandler.showErrorAlert) {
            Button("确定") {
                viewModel.errorHandler.clearError()
            }
        } message: {
            Text(viewModel.errorHandler.currentError?.errorDescription ?? "")
        }
        .focusable()
        .onAppear {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard editingEntry == nil, !viewModel.showSettings, !viewModel.showHistory,
                      sessionExport == nil, !showPermissionGuide, !showAudioQuality else { return event }
                if event.keyCode == 49, viewModel.speechRecognizer.isRecording {
                    viewModel.triggerTranslation(); return nil
                }
                if event.keyCode == 53, viewModel.speechRecognizer.isRecording {
                    viewModel.stopTranslation(); return nil
                }
                return event
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("语音实时翻译")
                    .font(Constants.Typography.largeTitle)
                    .foregroundColor(Constants.Colors.textPrimary)

                Text("Voice Real-time Translation")
                    .font(Constants.Typography.caption)
                    .foregroundColor(Constants.Colors.textSecondary)
            }

            Spacer()

            // Status Indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.speechRecognizer.isRecording ? Constants.Colors.statusNegative : Constants.Colors.accentPrimary)
                    .frame(width: 8, height: 8)

                Text(viewModel.speechRecognizer.recordingStatus)
                    .font(Constants.Typography.caption)
                    .foregroundColor(viewModel.speechRecognizer.isRecording ? Constants.Colors.statusNegative : Constants.Colors.textSecondary)
            }
        }
        .padding(.horizontal, 32)
        .frame(height: 72)
    }

    // MARK: - Language Direction Selector

    private var languageDirectionSelector: some View {
        HStack(spacing: 16) {
            // Source Language
            languageButton(
                language: appSettings.selectedLanguageDirection == .englishToChinese ? "English" : "中文",
                color: Constants.Colors.accentPrimary
            )

            // Switch Button
            Button(action: {
                viewModel.switchLanguageDirection()
                appSettings.selectedLanguageDirection = viewModel.appSettings.selectedLanguageDirection
            }) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Constants.Colors.accentPrimary)
                    .clipShape(Circle())
                    .shadow(color: Constants.Colors.accentPrimary.opacity(0.3), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())

            // Target Language
            languageButton(
                language: appSettings.selectedLanguageDirection == .englishToChinese ? "中文" : "English",
                color: Constants.Colors.accentWarm
            )
        }
    }

    private func languageButton(language: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 16))
                .foregroundColor(color)

            Text(language)
                .font(Constants.Typography.headline)
                .foregroundColor(Constants.Colors.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Constants.Colors.bgSurface)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.03), radius: 12, x: 0, y: 2)
    }

    // MARK: - Audio Input Toggle

    private var audioInputToggle: some View {
        HStack(spacing: 0) {
            ForEach(AudioInputSource.allCases, id: \.self) { source in
                Button(action: {
                    appSettings.audioInputSource = source
                    viewModel.appSettings.audioInputSource = source
                    viewModel.speechRecognizer.setAudioInputSource(source)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: source == .microphone ? "mic" : "speaker.wave.2")
                            .font(.system(size: 14))
                            .foregroundColor(appSettings.audioInputSource == source ? Constants.Colors.accentPrimary : Constants.Colors.textSecondary)

                        Text(source == .microphone ? "麦克风" : "系统音频")
                            .font(Constants.Typography.caption)
                            .foregroundColor(appSettings.audioInputSource == source ? Constants.Colors.textPrimary : Constants.Colors.textSecondary)
                            .fontWeight(appSettings.audioInputSource == source ? .semibold : .medium)
                    }
                    .segmentedButtonStyle(isSelected: appSettings.audioInputSource == source)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(Constants.Colors.bgMuted)
        .cornerRadius(12)
    }

    // MARK: - Translation Log Card

    private var translationLogCard: some View {
        VStack(spacing: 16) {
            // Card Header
            HStack {
                Text("实时翻译")
                    .font(Constants.Typography.headline)
                    .foregroundColor(Constants.Colors.textPrimary)

                Spacer()

                if viewModel.untranslatedCount > 0 {
                    Button("补译未完成内容（\(viewModel.untranslatedCount)）") {
                        viewModel.retryFailedTranslations()
                    }
                    .font(.caption)
                }
                if viewModel.factReviewCount > 0 {
                    Text("待核对 \(viewModel.factReviewCount) 段").font(.caption).foregroundColor(.orange)
                }
                // Status
                if viewModel.speechRecognizer.isListening || viewModel.isTranslating {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundColor(Constants.Colors.accentPrimary)

                        Text(viewModel.isTranslating ? "待译 \(viewModel.pendingTranslationCount) 段" : "识别中")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Constants.Colors.accentPrimary)
                    }
                }
            }

            // Log Content
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 12) {
                        if viewModel.displayEntries.isEmpty {
                            emptyLogPlaceholder
                        } else {
                            ForEach(viewModel.displayEntries) { entry in
                                structuredEntryView(entry)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("content")
                    .onChange(of: viewModel.displayEntries.count) { _ in
                        withAnimation {
                            proxy.scrollTo("content", anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Constants.Colors.bgElevated)
            .cornerRadius(12)
        }
        .cardStyle()
        .frame(maxHeight: .infinity)
    }

    private var emptyLogPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 32))
                .foregroundColor(Constants.Colors.textTertiary)

            Text("点击下方按钮开始实时翻译")
                .font(Constants.Typography.body)
                .foregroundColor(Constants.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private func structuredEntryView(_ entry: TranslationEntryModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("[\(entry.timestamp)]")
                    .font(Constants.Typography.small)
                    .foregroundColor(Constants.Colors.textTertiary)
                if entry.isManuallyEdited {
                    Text("已手动修改").font(.caption).foregroundColor(Constants.Colors.accentPrimary)
                }
                Spacer()
                if entry.canEditOriginal {
                    Button {
                        originalDraft = entry.originalText
                        rememberWordCorrection = false
                        editError = ""
                        editingEntry = entry
                    } label: { Label("修改原文", systemImage: "square.and.pencil") }
                    .buttonStyle(.borderless)
                    .foregroundColor(Constants.Colors.accentPrimary)
                    .accessibilityLabel("修改原文：\(entry.originalText)")
                }
            }

            // Original text
            if entry.containsCriticalFacts {
                Text("含数字、日期或单位，请核对听写原文。")
                    .font(.caption).foregroundColor(.orange)
            }
            if let suggested = viewModel.rememberedSuggestion(for: entry) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("纠错记忆建议：\(suggested)").font(.caption).foregroundColor(.secondary)
                    Button("采用这次纠正并更新译文") { _ = viewModel.updateOriginalText(entryID: entry.id, text: suggested) }
                        .buttonStyle(.borderless)
                }
            }
            if !entry.originalText.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text(entry.isError ? "" : "原:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(entry.isError ? Constants.Colors.statusNegative : Constants.Colors.accentPrimary)
                        .frame(width: 28, alignment: .leading)

                    Text(entry.originalText)
                        .font(Constants.Typography.body)
                        .foregroundColor(entry.isError ? Constants.Colors.statusNegative : Constants.Colors.textPrimary)
                }
            }

            // Translated text
            if !entry.translatedText.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text("译:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Constants.Colors.accentWarm)
                        .frame(width: 28, alignment: .leading)

                    Text(entry.translatedText)
                        .font(Constants.Typography.body)
                        .foregroundColor(Constants.Colors.textPrimary)
                }
            } else if (entry.isLive || !entry.statusMessage.isEmpty) && !entry.isError {
                HStack(alignment: .top, spacing: 12) {
                    Text("译:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Constants.Colors.accentWarm)
                        .frame(width: 28, alignment: .leading)

                    Text(entry.statusMessage.isEmpty ? "翻译中..." : entry.statusMessage)
                        .font(Constants.Typography.body)
                        .foregroundColor(Constants.Colors.textTertiary)
                        .italic()
                }
            }

            Rectangle()
                .fill(Constants.Colors.borderSubtle)
                .frame(height: 1)
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        VStack(spacing: 12) {
            Button(action: viewModel.toggleRecording) {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)

                    Text(viewModel.speechRecognizer.isRecording ? "停止翻译" : "开始翻译")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(width: 200, height: 52)
                .background(
                    LinearGradient(
                        colors: viewModel.speechRecognizer.isRecording ?
                            [Constants.Colors.statusNegative, Color(hex: "B5725E")] :
                            [Constants.Colors.accentPrimary, Constants.Colors.accentDark],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(26)
                .shadow(
                    color: viewModel.speechRecognizer.isRecording ?
                        Constants.Colors.statusNegative.opacity(0.25) :
                        Constants.Colors.accentPrimary.opacity(0.25),
                    radius: 16,
                    x: 0,
                    y: 4
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!appSettings.canTranslate)
            .scaleEffect(viewModel.speechRecognizer.isRecording ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: viewModel.speechRecognizer.isRecording)

            Text("⌨️ 空格键完成翻译 • ESC 停止录音")
                .font(Constants.Typography.small)
                .foregroundColor(Constants.Colors.textTertiary)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Left: Clear button
            HStack(spacing: 8) {
                bottomBarButton(icon: "trash", label: "清空") {
                    viewModel.clearText()
                }
                .disabled(viewModel.speechRecognizer.recognizedText.isEmpty &&
                         viewModel.translationService.translatedText.isEmpty &&
                         viewModel.displayEntries.isEmpty)

                bottomBarButton(icon: "square.and.arrow.up", label: "导出本次", hasBg: true) {
                    sessionExport = ExportRequest(text: viewModel.exportCurrentSession())
                }
                .disabled(viewModel.displayEntries.isEmpty)
            }

            Spacer()

            // Right: Action buttons
            HStack(spacing: 8) {
                // Floating overlay button (highlighted)
                Button(action: {
                    floatingOverlayController.toggle(viewModel: viewModel)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pip")
                            .font(.system(size: 14))
                            .foregroundColor(Constants.Colors.accentPrimary)

                        Text("悬浮窗")
                            .font(Constants.Typography.caption)
                            .foregroundColor(Constants.Colors.accentPrimary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Constants.Colors.accentPrimary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Constants.Colors.accentPrimary.opacity(0.25), lineWidth: 1)
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                bottomBarButton(icon: "clock.arrow.circlepath", label: "历史", hasBg: true) {
                    viewModel.showHistory = true
                }

                bottomBarButton(icon: "gearshape", label: "设置", hasBg: true) {
                    viewModel.showSettings = true
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(Constants.Colors.bgSurface)
        .overlay(
            Rectangle()
                .fill(Constants.Colors.borderSubtle)
                .frame(height: 1),
            alignment: .top
        )
    }

    private func bottomBarButton(icon: String, label: String, hasBg: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Constants.Colors.textSecondary)

                Text(label)
                    .font(Constants.Typography.caption)
                    .foregroundColor(Constants.Colors.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(hasBg ? Constants.Colors.bgElevated : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Translation Log View

struct TranslationLogView: View {
    let entries: [TranslationEntryModel]
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack(alignment: .leading, spacing: 8) {
                            if entries.isEmpty {
                                Text("暂无翻译记录...")
                                    .font(Constants.Typography.body)
                                    .foregroundColor(Constants.Colors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                                    .padding()
                            } else {
                                Text(entries.map { $0.plainText }.joined(separator: "\n\n"))
                                    .font(Constants.Typography.body)
                                    .foregroundColor(Constants.Colors.textPrimary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                                    .padding()
                                    .id("content")
                            }
                        }
                        .onChange(of: entries.count) { _ in
                            if !entries.isEmpty {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    withAnimation(.easeOut(duration: 0.4)) {
                                        proxy.scrollTo("content", anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if !entries.isEmpty {
                                    withAnimation(.easeOut(duration: 0.4)) {
                                        proxy.scrollTo("content", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                .background(Constants.Colors.bgPrimary)
            }
            .navigationTitle("实时翻译记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("清空") {
                        onClear()
                    }
                    .disabled(entries.isEmpty)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
