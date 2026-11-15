//
//  HistoryView.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var historyManager: HistoryManager
    var onRestore: ((SavedConversation) -> Void)? = nil
    var canRestore = true
    @State private var showingDeleteAlert = false
    @State private var exportRequest: ExportRequest?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索和过滤栏
                searchAndFilterBar
                
                // 统计信息
                statisticsSection
                
                if !historyManager.saveError.isEmpty { Text(historyManager.saveError).foregroundColor(.red) }
                if !historyManager.savedConversations.isEmpty {
                    List {
                        Section("整场记录（含尚未译出的内容）") {
                            ForEach(historyManager.savedConversations.filter {
                                (historyManager.searchText.isEmpty || $0.searchText.localizedCaseInsensitiveContains(historyManager.searchText)) &&
                                (historyManager.selectedDirection == nil || $0.lines.contains { $0.direction == historyManager.selectedDirection })
                            }) { conversation in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(conversation.title).lineLimit(1)
                                        Text("\(conversation.startedAt.formatted()) · \(conversation.lines.count) 段 · 待补译 \(conversation.unfinishedCount) 段")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let onRestore {
                                        Button("打开并继续") { onRestore(conversation); dismiss() }.disabled(!canRestore)
                                    }
                                }
                            }
                        }
                    }.frame(minHeight: 140, maxHeight: 220)
                }
                // 历史记录列表
                historyList
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .navigationTitle("翻译历史")
        .alert("清空所有历史记录", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("确认清空", role: .destructive) {
                historyManager.clearAllHistory()
            }
        } message: {
            Text("这将删除所有翻译历史记录。此操作无法撤销。")
        }
        .sheet(item: $exportRequest) { request in
            ExportView(
                title: "导出翻译历史",
                subtitle: "以下是您的翻译历史记录：",
                exportText: request.text,
                defaultFilename: "翻译历史记录_\(Date().formatted(date: .numeric, time: .omitted))"
            )
        }
    }
    
    // MARK: - Search and Filter Bar
    
    private var searchAndFilterBar: some View {
        VStack(spacing: Constants.UI.padding) {
            HStack(spacing: Constants.UI.padding) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("搜索翻译内容...", text: $historyManager.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !historyManager.searchText.isEmpty {
                        Button(action: { historyManager.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                
                // 语言方向过滤器
                Picker("过滤", selection: $historyManager.selectedDirection) {
                    Text("全部").tag(LanguageDirection?.none)
                    ForEach(LanguageDirection.allCases, id: \.self) { direction in
                        Text(direction.displayName).tag(direction as LanguageDirection?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 150)
            }
            
            // 操作按钮
            HStack {
                Button("导出历史记录") {
                    exportRequest = ExportRequest(text: historyManager.exportHistory())
                }
                .disabled(historyManager.translationHistory.isEmpty)
                
                Spacer()
                
                Button("清空所有记录") {
                    showingDeleteAlert = true
                }
                .disabled(historyManager.translationHistory.isEmpty && historyManager.savedConversations.isEmpty)
                .foregroundColor(.red)
                
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
        .padding(Constants.UI.padding * 2)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        HStack(spacing: Constants.UI.padding * 2) {
            StatisticCard(
                title: "总记录数",
                value: "\(historyManager.totalTranslations)",
                icon: "doc.text"
            )
            
            StatisticCard(
                title: "英译中",
                value: "\(historyManager.englishToChineseCount)",
                icon: "arrow.right"
            )
            
            StatisticCard(
                title: "中译英",
                value: "\(historyManager.chineseToEnglishCount)",
                icon: "arrow.left"
            )
            
            StatisticCard(
                title: "今日翻译",
                value: "\(historyManager.todaysTranslations)",
                icon: "calendar"
            )
        }
        .padding(.horizontal, Constants.UI.padding * 2)
        .padding(.bottom, Constants.UI.padding)
    }
    
    // MARK: - History List
    
    private var historyList: some View {
        Group {
            if historyManager.filteredHistory.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(historyManager.filteredHistory) { record in
                        HistoryRowView(record: record)
                    }
                    .onDelete(perform: historyManager.deleteRecords)
                }
                .listStyle(PlainListStyle())
            }
        }
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: Constants.UI.padding) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text(historyManager.searchText.isEmpty ? "暂无翻译记录" : "未找到匹配的记录")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text(historyManager.searchText.isEmpty ? 
                 "完成翻译后，记录将会显示在这里" : 
                 "尝试调整搜索条件或清空搜索框")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - History Row View

struct HistoryRowView: View {
    let record: TranslationRecord
    @State private var isExpanded = false
    @State private var showingOriginalExportSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 主要内容行
            HStack(alignment: .top, spacing: Constants.UI.padding) {
                // 语言方向指示器
                VStack {
                    Text(record.direction.icon)
                        .font(.title2)
                    
                    Text(record.direction.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 60)
                
                // 文本内容
                VStack(alignment: .leading, spacing: 8) {
                    // 原文预览
                    Text(isExpanded ? record.originalText : record.preview)
                        .font(.body)
                        .lineLimit(isExpanded ? nil : 2)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    
                    // 译文
                    if isExpanded {
                        Text(record.translatedText)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.top, 4)
                    }
                    
                    // 时间戳
                    HStack {
                        Text(record.formattedTimestamp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if record.isRecent {
                            Text("最近")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }
                
                // 展开/收起按钮
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.vertical, Constants.UI.padding)
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded.toggle()
            }
            
            // 展开后的操作按钮
            if isExpanded {
                HStack {
                    Button("复制原文") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.originalText, forType: .string)
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                    
                    Button("复制译文") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.translatedText, forType: .string)
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)

                    Button("导出原文 TXT") {
                        showingOriginalExportSheet = true
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                    
                    Spacer()
                }
                .padding(.bottom, Constants.UI.padding)
            }
        }
        .padding(.horizontal, Constants.UI.padding)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(Constants.UI.cornerRadius)
        .padding(.horizontal, Constants.UI.padding)
        .padding(.vertical, 4)
        .sheet(isPresented: $showingOriginalExportSheet) {
            ExportView(
                title: "导出 Session 原文",
                subtitle: "\(record.direction.displayName) | \(record.formattedTimestamp)",
                exportText: record.sessionOriginalExportText,
                defaultFilename: record.sessionOriginalExportFilename
            )
        }
    }
}

// MARK: - Statistic Card

struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(Constants.UI.cornerRadius)
    }
}

// MARK: - Export View

// Keep the presentation and its content in one state update, including the first export.
struct ExportRequest: Identifiable {
    let id = UUID()
    let text: String
}

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String
    let exportText: String
    let defaultFilename: String
    @State private var exportError: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.padding) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(subtitle)
                .font(.body)
                .foregroundColor(.secondary)
            
            ScrollView {
                Text(exportText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 300)
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(Constants.UI.cornerRadius)
            
            HStack {
                Button("复制到剪贴板") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(exportText, forType: .string)
                }
                
                Button("保存为文件") {
                    saveToFile()
                }
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(BorderedProminentButtonStyle())
            }
        }
        .padding(Constants.UI.padding * 2)
        .frame(width: 600, height: 500)
        .alert("保存失败", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("好") { exportError = nil }
        } message: {
            Text(exportError ?? "请重试。")
        }
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultFilename + ".txt"
        panel.canCreateDirectories = true
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try exportText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                exportError = "无法保存文件，请检查保存位置后重试。"
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
}

// MARK: - Text Document for Export

struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var text: String
    
    init(text: String) {
        self.text = text
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}

// MARK: - Preview

#if DEBUG
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView(historyManager: {
            let manager = HistoryManager()
            // 添加示例数据用于预览
            for record in TranslationRecord.sampleData {
                manager.saveTranslation(record)
            }
            return manager
        }())
    }
}
#endif
