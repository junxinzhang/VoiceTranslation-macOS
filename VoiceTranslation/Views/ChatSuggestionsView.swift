//
//  ChatSuggestionsView.swift
//  VoiceTranslation
//
//  Collapsible chat suggestions panel for the floating overlay.
//  Displays context-aware reply suggestions as text strip cards
//  with a toggle button in the header to expand/collapse.
//
//  Created on 2026-03-05.
//

import SwiftUI

// MARK: - Chat Suggestions Panel

struct ChatSuggestionsView: View {
    @ObservedObject var suggestionService: SuggestionService
    @ObservedObject var ttsService: TTSService = TTSService.shared
    let direction: LanguageDirection
    let entries: [TranslationEntryModel]
    let onCopy: (String) -> Void
    
    private let suggestionsMaxHeight: CGFloat = 156

    @State private var copiedId: UUID?
    @State private var hoveredId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header: title + badge + toggle
            suggestionsHeader

            // Collapsible content
            if suggestionService.isExpanded {
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                // Suggestion entries
                ScrollView(.vertical, showsIndicators: false) {
                    suggestionsList
                }
                .frame(maxHeight: suggestionsMaxHeight)
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                // Delay slider
                delaySlider
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: suggestionService.isExpanded)
    }

    // MARK: - Header

    private var suggestionsHeader: some View {
        HStack(spacing: 8) {
            // Icon
            Image(systemName: "text.bubble")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "4A9EF5").opacity(0.8))

            Text("对话建议")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

            // Badge count
            if !suggestionService.suggestions.isEmpty {
                Text("\(suggestionService.suggestions.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 16, height: 16)
                    .background(Color(hex: "4A9EF5").opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Spacer()

            // Refresh button (only when expanded)
            if suggestionService.isExpanded {
                Button(action: {
                    // Trigger refresh
                    suggestionService.refresh(from: entries, direction: direction)
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                        .rotationEffect(.degrees(suggestionService.isGenerating ? 360 : 0))
                        .animation(
                            suggestionService.isGenerating
                                ? Animation.linear(duration: 0.6).repeatForever(autoreverses: false)
                                : .default,
                            value: suggestionService.isGenerating
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 24, height: 24)
            }

            // Toggle expand/collapse button
            Button(action: {
                suggestionService.toggleExpanded()
            }) {
                HStack(spacing: 3) {
                    Text(suggestionService.isExpanded ? "收起" : "展开")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))

                    Image(systemName: suggestionService.isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .contentShape(Rectangle())
        .onTapGesture {
            suggestionService.toggleExpanded()
        }
    }

    // MARK: - Suggestions List

    private var suggestionsList: some View {
        VStack(spacing: 6) {
            if suggestionService.suggestions.isEmpty {
                emptySuggestionsState
            } else {
                ForEach(suggestionService.suggestions) { suggestion in
                    suggestionCard(suggestion)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Suggestion Card (Text Strip Shape)

    private func suggestionCard(_ suggestion: ChatSuggestion) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Tag label (colored pill)
            Text(suggestion.tag.label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(suggestion.tag.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(suggestion.tag.color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 1)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                // Primary text: source language (to reply with)
                Text(suggestion.primaryText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                // Secondary text: translated (for user's reference)
                Text(suggestion.secondaryText)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Action buttons (speak + copy)
            HStack(spacing: 2) {
                // TTS Speak button
                Button(action: {
                    if ttsService.speakingId == suggestion.id {
                        ttsService.stop()
                    } else {
                        ttsService.speakSuggestion(suggestion, direction: direction)
                    }
                }) {
                    Group {
                        if ttsService.speakingId == suggestion.id {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(Color(hex: "4A9EF5"))
                        } else {
                            Image(systemName: "speaker.wave.2")
                                .foregroundColor(.white.opacity(hoveredId == suggestion.id ? 0.5 : 0.15))
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
                .help("朗读此建议")

                // Copy button
                Button(action: {
                    copyToPasteboard(suggestion)
                }) {
                    Group {
                        if copiedId == suggestion.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(Color(hex: "3D8A5A"))
                        } else {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(.white.opacity(hoveredId == suggestion.id ? 0.5 : 0.15))
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(PlainButtonStyle())
                .help("复制到剪贴板")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredId == suggestion.id
                    ? suggestion.tag.color.opacity(0.08)
                    : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    hoveredId == suggestion.id
                        ? suggestion.tag.color.opacity(0.2)
                        : Color.white.opacity(0.05),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredId = isHovering ? suggestion.id : nil
            }
        }
        .onTapGesture {
            copyToPasteboard(suggestion)
        }
    }

    // MARK: - Empty State

    private var emptySuggestionsState: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.15))

            Text("开始对话后将自动生成建议")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Delay Slider

    private var delaySlider: some View {
        HStack(spacing: 6) {
            // Timer icon
            Image(systemName: "timer")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.25))

            // "Fast" label
            Text("快")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.25))

            // Slider
            Slider(
                value: $suggestionService.debounceDelay,
                in: 0.5...10.0,
                step: 0.5
            )
            .controlSize(.mini)
            .tint(Color(hex: "4A9EF5").opacity(0.6))

            // "Slow" label
            Text("慢")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.25))

            // Current value badge
            Text(String(format: "%.1fs", suggestionService.debounceDelay))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "4A9EF5").opacity(0.8))
                .frame(width: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.02))
    }

    // MARK: - Copy Action

    private func copyToPasteboard(_ suggestion: ChatSuggestion) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(suggestion.primaryText, forType: .string)
        #endif

        // Show feedback
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedId = suggestion.id
        }

        // Notify parent
        onCopy(suggestion.primaryText)

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                if copiedId == suggestion.id {
                    copiedId = nil
                }
            }
        }
    }
}
