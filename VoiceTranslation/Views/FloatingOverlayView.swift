//
//  FloatingOverlayView.swift
//  VoiceTranslation
//
//  Created on 2026-02-26.
//  Floating translation overlay for watching videos.
//

import SwiftUI

// MARK: - Overlay Status

enum OverlayStatus {
    case idle
    case recognizing
    case error(String)
    
    var dotColor: Color {
        switch self {
        case .idle: return Color(hex: "3D8A5A")
        case .recognizing: return Color(hex: "D08068")
        case .error: return Color(hex: "E54D42")
        }
    }
    
    var label: String {
        switch self {
        case .idle: return "空闲"
        case .recognizing: return "识别中..."
        case .error: return "连接错误"
        }
    }
}



// MARK: - FloatingOverlayView

struct FloatingOverlayView: View { 
    @ObservedObject var viewModel: MainViewModel
    @State private var overlayOpacity: Double = {
        let saved = UserDefaults.standard.double(forKey: "FloatingOverlay_Opacity")
        return saved > 0 ? saved : 0.85
    }()
    @State private var isCollapsed: Bool = false
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onCollapsedChange: (Bool) -> Void
    @Binding var isPinned: Bool

    // Smart auto-scroll state
    @State private var autoScrollEnabled: Bool = true
    @State private var previousEntryCount: Int = 0

    // Entries are now provided directly by the ViewModel as structured data
    private var displayEntries: [TranslationEntryModel] {
        viewModel.displayEntries
    }
    
    /// Lightweight trigger value for onChange — avoids requiring full array Equatable
    private var displayEntriesTrigger: String {
        let last = viewModel.displayEntries.last
        return "\(viewModel.displayEntries.count)_\(last?.translatedText.count ?? 0)_\(last?.id.uuidString.prefix(8) ?? "")"
    }

    private var overlayStatus: OverlayStatus {
        if viewModel.errorHandler.showErrorAlert {
            return .error(viewModel.errorHandler.currentError?.errorDescription ?? "未知错误")
        } else if viewModel.speechRecognizer.isRecording || viewModel.translationService.isTranslating {
            return .recognizing
        } else {
            return .idle
        }
    }

    private var languagePairText: String {
        viewModel.appSettings.selectedLanguageDirection == .englishToChinese ? "EN → 中文" : "中文 → EN"
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCollapsed {
                // ── Collapsed: Wrapped Subtitle + Suggestions ──
                collapsedSubtitleBar

                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)

                suggestionsPanel
            } else {
                // ── Expanded: Full Panel Mode ──

                // Title Bar
                titleBar

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                // Content
                switch overlayStatus {
                case .error(let message):
                    errorContent(message: message)
                default:
                    translationContent
                        .frame(maxHeight: .infinity, alignment: .top)
                        .layoutPriority(1)
                }

                // Suggestion Divider
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)

                // Chat Suggestions Panel
                suggestionsPanel

                // Bottom Divider
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                // Bottom Bar
                bottomBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: isCollapsed ? nil : .infinity, alignment: .top)
        .background(
            ZStack {
                VisualEffectBlur()
                LinearGradient(
                    colors: [
                        Color(hex: "111111").opacity(0.72),
                        Color(hex: "1A1918").opacity(0.58)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .opacity(overlayOpacity)
        )
        .clipShape(RoundedRectangle(cornerRadius: isCollapsed ? 10 : 16, style: .continuous))
        .shadow(color: .black.opacity(0.4 * overlayOpacity), radius: isCollapsed ? 16 : 32, x: 0, y: isCollapsed ? 4 : 8)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: isCollapsed ? "arrow.left.and.right" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(isCollapsed ? 0.1 : 0.15))
                .frame(width: 16, height: 16)
                .padding(6)
        }
        .animation(.easeInOut(duration: 0.3), value: isCollapsed)
    }

    private var suggestionsPanel: some View {
        ChatSuggestionsView(
            suggestionService: viewModel.suggestionService,
            direction: viewModel.appSettings.selectedLanguageDirection,
            entries: displayEntries,
            onCopy: { text in
                print("📋 已复制建议")
            }
        )
        .onAppear {
            guard !displayEntries.isEmpty else { return }
            viewModel.suggestionService.generateSuggestions(
                from: displayEntries,
                direction: viewModel.appSettings.selectedLanguageDirection
            )
        }
        .onChange(of: displayEntriesTrigger) { _ in
            viewModel.suggestionService.generateSuggestions(
                from: displayEntries,
                direction: viewModel.appSettings.selectedLanguageDirection
            )
        }
    }

    // MARK: - Collapsed Subtitle Bar

    /// Wrapped subtitle bar with bounded height to keep collapsed resizing usable.
    private var collapsedSubtitleBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(overlayStatus.dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: overlayStatus.dotColor.opacity(0.6), radius: 3)

                Text(languagePairText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())

                Spacer(minLength: 8)

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isCollapsed = false
                    }
                    onCollapsedChange(false)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                        Text("展开")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
            }

            Group {
                if let lastEntry = displayEntries.last, !lastEntry.translatedText.isEmpty {
                    Text(lastEntry.translatedText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if viewModel.speechRecognizer.isRecording {
                    Text("识别中...")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                        .italic()
                } else {
                    Text("实时翻译 — 等待翻译内容")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                isCollapsed = false
            }
            onCollapsedChange(false)
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 0) {
            // Left: Drag handle + Title + Language
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.25))
                    .frame(width: 14, height: 14)

                Text("实时翻译")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))

                // Language badge
                Text(languagePairText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }

            Spacer()

            // Right: Status + Collapse + Pin + Close
            HStack(spacing: 10) {
                // Status indicator
                Circle()
                    .fill(overlayStatus.dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: overlayStatus.dotColor.opacity(0.6), radius: 4)

                Text(overlayStatus.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(overlayStatus.dotColor)

                // Collapse to subtitle bar
                OverlayToolbarButton(
                    icon: "chevron.down",
                    activeColor: nil,
                    action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isCollapsed = true
                        }
                        onCollapsedChange(true)
                    }
                )

                // Pin button
                OverlayToolbarButton(
                    icon: isPinned ? "pin.fill" : "pin",
                    activeColor: isPinned ? Color(hex: "3D8A5A") : nil,
                    action: onTogglePin
                )

                // Close button
                OverlayToolbarButton(
                    icon: "xmark",
                    activeColor: nil,
                    hoverColor: Color(hex: "E54D42"),
                    action: onClose
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isCollapsed.toggle()
            }
            onCollapsedChange(isCollapsed)
        }
    }

    // MARK: - Translation Content (with smart auto-scroll)

    private var translationContent: some View {
        VStack(spacing: 0) {
            // Waveform (when recognizing)
            if case .recognizing = overlayStatus {
                waveformView
                    .padding(.top, 8)
            }

            // Translation entries with auto-scroll
            ZStack(alignment: .bottomTrailing) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            if displayEntries.isEmpty {
                                emptyState
                            } else {
                                ForEach(Array(displayEntries.enumerated()), id: \.element.id) { index, entry in
                                    translationEntryRow(entry: entry, isLatest: index == displayEntries.count - 1)
                                        .id(entry.id)
                                        .animation(.none, value: entry.translatedText)
                                }
                            }
                            // Invisible anchor at the bottom for auto-scroll
                            Color.clear
                                .frame(height: 1)
                                .id("overlay_scroll_bottom")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .frame(minHeight: 80)
                    // Detect user manual scroll via scroll wheel
                    .onScrollGesture {
                        // User manually scrolled → pause auto-scroll
                        if autoScrollEnabled {
                            autoScrollEnabled = false
                        }
                    }
                    .onChange(of: displayEntriesTrigger) { _ in
                        // Auto-scroll to bottom when new content arrives (if enabled)
                        if autoScrollEnabled {
                            let latestEntry = displayEntries.last
                            let appendedNewEntry = displayEntries.count > previousEntryCount
                            previousEntryCount = displayEntries.count

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    if let latestEntry {
                                        proxy.scrollTo(latestEntry.id, anchor: appendedNewEntry ? .bottom : .top)
                                    } else {
                                        proxy.scrollTo("overlay_scroll_bottom", anchor: .bottom)
                                    }
                                }
                            }
                        } else {
                            previousEntryCount = displayEntries.count
                        }
                    }
                    .onAppear {
                        previousEntryCount = displayEntries.count
                        // Initial scroll to bottom
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            if let latestEntry = displayEntries.last {
                                proxy.scrollTo(latestEntry.id, anchor: .top)
                            } else {
                                proxy.scrollTo("overlay_scroll_bottom", anchor: .bottom)
                            }
                        }
                    }
                }

                // "Scroll to bottom" button (shown when auto-scroll is paused)
                if !autoScrollEnabled && !displayEntries.isEmpty {
                    Button(action: {
                        autoScrollEnabled = true
                        // Trigger scroll by toggling — the onChange will handle it
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                            Text("最新")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "3D8A5A").opacity(0.85))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: autoScrollEnabled)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.2))

                Text("等待翻译内容...")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
            }

            Text("点击下方按钮或按 Space 开始翻译")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func translationEntryRow(entry: TranslationEntryModel, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Original text (source language)
            Text(entry.originalText)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(entry.isLive ? Color(hex: "D08068").opacity(0.8) : .white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
                .transaction { t in t.animation = nil } // Added this line as per instruction

            // Translated text (target language) — only show if translation exists
            if !entry.translatedText.isEmpty {
                Text(entry.translatedText)
                    .font(.system(size: isLatest ? 20 : 18, weight: isLatest ? .semibold : .medium, design: .rounded))
                    .foregroundColor(.white.opacity(isLatest ? 0.9 : 0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .transaction { t in t.animation = nil }
            } else if entry.isLive || !entry.statusMessage.isEmpty {
                // Show translating indicator while live
                Text(entry.statusMessage.isEmpty ? "翻译中..." : entry.statusMessage)
                    .font(.system(size: isLatest ? 18 : 16, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(entryBackground(isLatest: isLatest, isLive: entry.isLive))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func entryBackground(isLatest: Bool, isLive: Bool) -> some View {
        if isLive {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "D08068").opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: "D08068").opacity(0.18), lineWidth: 1)
                )
        } else if isLatest {
            Color(hex: "3D8A5A").opacity(0.12)
        } else {
            Color.white.opacity(0.03)
        }
    }

    // MARK: - Waveform View

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { i in
                WaveBar(index: i)
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    // MARK: - Error Content

    private func errorContent(message: String) -> some View {
        VStack(spacing: 12) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Color(hex: "E54D42").opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: "wifi.slash")
                    .font(.system(size: 22))
                    .foregroundColor(Color(hex: "E54D42"))
            }

            Text("翻译服务连接失败")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))

            Text("请检查网络连接或 API 配置后重试")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            // Retry button
            Button(action: {
                viewModel.errorHandler.clearError()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                    Text("重新连接")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(hex: "E54D42"))
                .clipShape(Capsule())
                .shadow(color: Color(hex: "E54D42").opacity(0.4), radius: 8, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Bar (with translation control button)

    private var bottomBar: some View {
        HStack(spacing: 8) {
            // Left: Translation control button
            Button(action: {
                viewModel.toggleRecording()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: viewModel.speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 11))

                    Text(viewModel.speechRecognizer.isRecording ? "停止" : "开始翻译")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    viewModel.speechRecognizer.isRecording
                        ? Color(hex: "D08068")
                        : Color(hex: "3D8A5A")
                )
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())

            // Space key hint
            Text("Space")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06))
                .cornerRadius(3)

            // Simultaneous translation mode toggle
            Button(action: {
                viewModel.appSettings.simultaneousTranslation.toggle()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                    Text("同传")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundColor(
                    viewModel.appSettings.simultaneousTranslation
                        ? Color(hex: "F5A623")
                        : .white.opacity(0.3)
                )
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    viewModel.appSettings.simultaneousTranslation
                        ? Color(hex: "F5A623").opacity(0.15)
                        : Color.white.opacity(0.05)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .help("同声传译模式：按文本长度主动触发翻译，无需等待完整句子")

            // Threshold slider (only visible when simultaneous mode is on)
            if viewModel.appSettings.simultaneousTranslation {
                HStack(spacing: 3) {
                    Slider(
                        value: Binding(
                            get: { viewModel.appSettings.simultaneousThreshold },
                            set: { viewModel.appSettings.simultaneousThreshold = $0 }
                        ),
                        in: 10...200,
                        step: 5
                    )
                    .frame(width: 50)
                    .controlSize(.mini)

                    Text("\(Int(viewModel.appSettings.simultaneousThreshold))字")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "F5A623").opacity(0.7))
                        .frame(width: 30, alignment: .trailing)
                }
            }

            Spacer()

            // Auto-scroll status
            if !autoScrollEnabled {
                Text("⏸ 已暂停滚动")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "D4A64A").opacity(0.7))
            }

            Spacer()

            // Opacity slider
            HStack(spacing: 5) {
                Image(systemName: "sun.min")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))

                Slider(value: $overlayOpacity, in: 0.1...1.0, step: 0.01)
                    .frame(width: 60)
                    .controlSize(.mini)
                    .onChange(of: overlayOpacity) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "FloatingOverlay_Opacity")
                    }

                Text("\(Int(overlayOpacity * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }
}

// MARK: - Scroll Gesture Detector (macOS scroll wheel detection)

extension View {
    /// Detect scroll wheel events to pause auto-scroll
    func onScrollGesture(perform action: @escaping () -> Void) -> some View {
        self.background(
            ScrollGestureDetector(onScroll: action)
        )
    }
}

struct ScrollGestureDetector: NSViewRepresentable {
    let onScroll: () -> Void

    func makeNSView(context: Context) -> ScrollDetectorView {
        let view = ScrollDetectorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollDetectorView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollDetectorView: NSView {
    var onScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        // Only trigger when user actually scrolls (not momentum)
        if abs(event.deltaY) > 0.5 {
            onScroll?()
        }
        super.scrollWheel(with: event)
    }
}

// MARK: - Overlay Toolbar Button (larger hit area + hover effect)

struct OverlayToolbarButton: View {
    let icon: String
    var activeColor: Color? = nil
    var hoverColor: Color? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(
                    isHovering
                        ? (hoverColor ?? activeColor ?? .white.opacity(0.8))
                        : (activeColor ?? .white.opacity(0.35))
                )
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isHovering
                                ? (hoverColor ?? activeColor ?? .white).opacity(0.15)
                                : (activeColor != nil ? activeColor!.opacity(0.12) : Color.clear)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Wave Bar Animation

struct WaveBar: View {
    let index: Int
    @State private var animating = false

    private let heights: [CGFloat] = [6, 12, 18, 24, 10, 20, 8, 22, 14, 6, 16, 10]

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(hex: "D08068"))
            .frame(width: 3, height: animating ? heights[index % heights.count] : 4)
            .animation(
                Animation.easeInOut(duration: Double.random(in: 0.3...0.7))
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.05),
                value: animating
            )
            .onAppear {
                animating = true
            }
    }
}

// MARK: - Visual Effect Blur (macOS)

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        // Force dark appearance for consistent rendering
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Ensure state stays active (can be reset by system)
        nsView.state = .active
        nsView.appearance = NSAppearance(named: .darkAqua)
    }
}
