//
//  HistoryManager.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation
import Combine

class HistoryManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var translationHistory: [TranslationRecord] = []
    @Published var filteredHistory: [TranslationRecord] = []
    @Published var searchText: String = "" {
        didSet {
            filterHistory()
        }
    }
    @Published var selectedDirection: LanguageDirection? {
        didSet {
            filterHistory()
        }
    }
    
    // MARK: - Private Properties
    
    #if DEBUG
    private let userDefaults = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        ? (UserDefaults(suiteName: AppSettings.testUserDefaultsSuiteName) ?? .standard) : .standard
    #else
    private let userDefaults = UserDefaults.standard
    #endif
    @Published private(set) var savedConversations: [SavedConversation] = []
    private let conversationDirectory: URL?
    @Published private(set) var saveError = ""
    private let historyKey = "Translation_History"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(conversationDirectory: URL? = nil) {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.conversationDirectory = conversationDirectory ?? (testing ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceTranslation/Conversations", isDirectory: true))
        reloadConversations()
        loadHistory()
        filterHistory()
    }
    
    func saveConversation(_ conversation: SavedConversation, active: Bool = true) {
        guard let directory = conversationDirectory, !conversation.lines.isEmpty || !conversation.draft.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(conversation)
            try data.write(to: directory.appendingPathComponent("\(conversation.id).json"), options: .atomic)
            if active { try data.write(to: directory.appendingPathComponent("active.json"), options: .atomic) }
            if let i = savedConversations.firstIndex(where: { $0.id == conversation.id }) { savedConversations[i] = conversation }
            else { savedConversations.insert(conversation, at: 0) }
            saveError = ""
        } catch { saveError = "本次内容暂未保存成功，请保留窗口并检查磁盘空间。" }
    }

    func activeConversation() -> SavedConversation? {
        guard let directory = conversationDirectory else { return nil }
        let url = directory.appendingPathComponent("active.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try JSONDecoder().decode(SavedConversation.self, from: Data(contentsOf: url)) }
        catch { saveError = "上次内容暂时无法读取，原文件已保留。"; return nil }
    }

    func finishActiveConversation() {
        guard let directory = conversationDirectory else { return }
        let url = directory.appendingPathComponent("active.json")
        do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
        catch { saveError = "本次内容未能结束保存，请重试。" }
    }

    private func reloadConversations() {
        guard let directory = conversationDirectory, FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            savedConversations = urls.filter { $0.pathExtension == "json" && $0.lastPathComponent != "active.json" }.compactMap { url in
                do { return try JSONDecoder().decode(SavedConversation.self, from: Data(contentsOf: url)) }
                catch { saveError = "部分历史内容暂时无法读取，原文件已保留。"; return nil }
            }.sorted { $0.startedAt > $1.startedAt }
        } catch { saveError = "历史内容暂时无法读取。" }
    }

    // MARK: - Public Methods
    
    func saveTranslation(_ record: TranslationRecord) {
        // 避免重复保存相同的翻译
        if !translationHistory.contains(where: { $0.originalText == record.originalText && $0.translatedText == record.translatedText }) {
            translationHistory.insert(record, at: 0)
            
            
            saveToUserDefaults()
            filterHistory()
        }
    }
    
    func deleteRecord(_ record: TranslationRecord) {
        translationHistory.removeAll { $0.id == record.id }
        saveToUserDefaults()
        filterHistory()
    }
    
    func deleteRecords(at indexSet: IndexSet) {
        // 从过滤后的历史记录中删除
        let recordsToDelete = indexSet.map { filteredHistory[$0] }
        
        for record in recordsToDelete {
            translationHistory.removeAll { $0.id == record.id }
        }
        
        saveToUserDefaults()
        filterHistory()
    }
    
    func clearAllHistory() {
        if let directory = conversationDirectory {
            do {
                for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                    try FileManager.default.removeItem(at: url)
                }
                savedConversations = []
            } catch { saveError = "历史内容未能清空，请重试。" }
        }
        translationHistory.removeAll()
        saveToUserDefaults()
        filterHistory()
    }
    
    func exportHistory() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        var exportText = "语音翻译历史记录\n"
        exportText += "导出时间: \(dateFormatter.string(from: Date()))\n"
        exportText += "记录数量: \(translationHistory.count)\n\n"
        
        for (index, record) in translationHistory.enumerated() {
            exportText += "[\(index + 1)] \(record.direction.displayName)\n"
            exportText += "时间: \(record.formattedTimestamp)\n"
            exportText += "原文: \(record.originalText)\n"
            exportText += "译文: \(record.translatedText)\n\n"
        }
        
        return exportText
    }
    
    // MARK: - Private Methods
    
    private func loadHistory() {
        if let data = userDefaults.data(forKey: historyKey) {
            do {
                let decoder = JSONDecoder()
                translationHistory = try decoder.decode([TranslationRecord].self, from: data)
            } catch {
                print("Failed to load history: \(error)")
                translationHistory = []
            }
        }
    }
    
    private func saveToUserDefaults() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(translationHistory)
            userDefaults.set(data, forKey: historyKey)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    private func filterHistory() {
        var filtered = translationHistory
        
        // 按语言方向过滤
        if let direction = selectedDirection {
            filtered = filtered.filter { $0.direction == direction }
        }
        
        // 按搜索文本过滤
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let searchTerm = searchText.lowercased()
            filtered = filtered.filter {
                $0.originalText.lowercased().contains(searchTerm) ||
                $0.translatedText.lowercased().contains(searchTerm)
            }
        }
        
        filteredHistory = filtered
    }
    
    // MARK: - Statistics
    
    var totalTranslations: Int {
        return translationHistory.count
    }
    
    var englishToChineseCount: Int {
        return translationHistory.filter { $0.direction == .englishToChinese }.count
    }
    
    var chineseToEnglishCount: Int {
        return translationHistory.filter { $0.direction == .chineseToEnglish }.count
    }
    
    var todaysTranslations: Int {
        let calendar = Calendar.current
        let today = Date()
        return translationHistory.filter {
            calendar.isDate($0.timestamp, inSameDayAs: today)
        }.count
    }
    
    var recentTranslations: [TranslationRecord] {
        return Array(translationHistory.prefix(5))
    }
}
/// A whole conversation, including source text not translated yet. Never stores credentials or audio.
struct SavedConversation: Codable, Identifiable {
    var id: UUID
    var startedAt: Date
    var updatedAt: Date
    var lines: [TranslationSession]
    var draft: String
    var draftDirection: LanguageDirection

    var title: String { String((lines.first?.originalText ?? draft).prefix(45)) }
    var unfinishedCount: Int { lines.filter { !$0.isCompleted }.count + (draft.isEmpty ? 0 : 1) }
    var searchText: String { lines.map { $0.originalText + " " + $0.translatedText }.joined(separator: " ") + " " + draft }
}
