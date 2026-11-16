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
    enum Deletion { case records(Set<UUID>), all }
    let deletions = PassthroughSubject<Deletion, Never>()
    private struct RemovedContent: Codable {
        var records = Set<UUID>()
        var conversations = Set<UUID>()
    }
    private var removed = RemovedContent()
    private var deletionStateReadable = true
    private let historyKey = "Translation_History"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(conversationDirectory: URL? = nil) {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.conversationDirectory = conversationDirectory ?? (testing ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VoiceTranslation/Conversations", isDirectory: true))
        loadDeletionState()
        reloadConversations()
        loadHistory()
        filterHistory()
    }
    
    func saveConversation(_ conversation: SavedConversation, active: Bool = true) {
        guard deletionStateReadable, !removed.conversations.contains(conversation.id) else { return }
        var conversation = conversation
        conversation.lines.removeAll { removed.records.contains($0.id) }
        guard let directory = conversationDirectory else { return }
        let existing = directory.appendingPathComponent("\(conversation.id).json")
        // Clearing a names-only scene must overwrite its old metadata, not leave
        // an active pointer that restores the removed names next launch.
        guard conversation.hasContent || FileManager.default.fileExists(atPath: existing.path) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(conversation)
            try data.write(to: directory.appendingPathComponent("\(conversation.id).json"), options: .atomic)
            if active { try data.write(to: directory.appendingPathComponent("active.json"), options: .atomic) }
            if !conversation.hasContent { savedConversations.removeAll { $0.id == conversation.id } }
            else if let i = savedConversations.firstIndex(where: { $0.id == conversation.id }) { savedConversations[i] = conversation }
            else { savedConversations.insert(conversation, at: 0) }
            saveError = ""
        } catch { saveError = "本次内容暂未保存成功，请保留窗口并检查磁盘空间。" }
    }

    func activeConversation() -> SavedConversation? {
        guard deletionStateReadable, let directory = conversationDirectory else { return nil }
        let url = directory.appendingPathComponent("active.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            var saved = try JSONDecoder().decode(SavedConversation.self, from: Data(contentsOf: url))
            guard !removed.conversations.contains(saved.id) else { return nil }
            saved.lines.removeAll { removed.records.contains($0.id) }
            return saved.hasContent ? saved : nil
        }
        catch { saveError = "上次内容暂时无法读取，原文件已保留。"; return nil }
    }

    func finishActiveConversation() {
        guard let directory = conversationDirectory else { return }
        let url = directory.appendingPathComponent("active.json")
        do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
        catch { saveError = "本次内容未能结束保存，请重试。" }
    }

    private func reloadConversations() {
        guard deletionStateReadable, let directory = conversationDirectory, FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            savedConversations = urls.filter { $0.pathExtension == "json" && $0.lastPathComponent != "active.json" }.compactMap { url in
                do {
                    var saved = try JSONDecoder().decode(SavedConversation.self, from: Data(contentsOf: url))
                    guard !removed.conversations.contains(saved.id) else { return nil }
                    saved.lines.removeAll { removed.records.contains($0.id) }
                    return saved.hasContent ? saved : nil
                }
                catch { saveError = "部分历史内容暂时无法读取，原文件已保留。"; return nil }
            }.sorted { $0.startedAt > $1.startedAt }
        } catch { saveError = "历史内容暂时无法读取。" }
    }

    // MARK: - Public Methods
    
    func saveTranslation(_ record: TranslationRecord) {
        guard deletionStateReadable, !removed.records.contains(record.id) else { return }
        // 避免重复保存相同的翻译
        if !translationHistory.contains(where: { $0.originalText == record.originalText && $0.translatedText == record.translatedText }) {
            translationHistory.insert(record, at: 0)
            
            
            saveToUserDefaults()
            filterHistory()
        }
    }
    
    /// Used only when a corrected translation replaces the same row, not user deletion.
    func removeReplacedRecord(_ record: TranslationRecord) {
        translationHistory.removeAll { $0.id == record.id }
        saveToUserDefaults()
        filterHistory()
    }

    func deleteRecord(_ record: TranslationRecord) { deleteContent([record]) }

    func deleteRecords(at indexSet: IndexSet) {
        deleteContent(indexSet.compactMap { filteredHistory.indices.contains($0) ? filteredHistory[$0] : nil })
    }

    private func deleteContent(_ records: [TranslationRecord]) {
        var ids = Set(records.map(\.id))
        // Old versions used a separate UUID for the per-row history copy.
        for saved in savedConversations {
            for line in saved.lines where records.contains(where: {
                $0.originalText == line.originalText && $0.direction == line.direction && $0.timestamp == line.createdAt
            }) { ids.insert(line.id) }
        }
        var next = removed
        next.records.formUnion(ids)
        guard persistDeletionState(next) else { return }
        removed = next
        deletions.send(.records(ids))
        scrubConversationFiles()
        translationHistory.removeAll { ids.contains($0.id) }
        saveToUserDefaults()
        filterHistory()
    }

    func clearAllHistory() {
        var next = removed
        next.records.formUnion(translationHistory.map(\.id))
        next.conversations.formUnion(savedConversations.map(\.id))
        next.records.formUnion(savedConversations.flatMap { $0.lines.map(\.id) })
        if let active = activeConversation() { next.conversations.insert(active.id) }
        guard persistDeletionState(next) else { return }
        removed = next
        deletions.send(.all)
        scrubConversationFiles()
        translationHistory.removeAll()
        saveToUserDefaults()
        filterHistory()
    }

    func isDeleted(_ id: UUID) -> Bool { !deletionStateReadable || removed.records.contains(id) }
    func isConversationDeleted(_ id: UUID) -> Bool { !deletionStateReadable || removed.conversations.contains(id) }

    private func loadDeletionState() {
        guard let directory = conversationDirectory else { return }
        let url = directory.appendingPathComponent("removed-content.plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { removed = try PropertyListDecoder().decode(RemovedContent.self, from: Data(contentsOf: url)) }
        catch { deletionStateReadable = false; saveError = "删除记录无法读取，请先修复文件访问权限后重试。" }
    }

    private func persistDeletionState(_ state: RemovedContent) -> Bool {
        guard deletionStateReadable else { return false }
        guard let directory = conversationDirectory else { return true }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try PropertyListEncoder().encode(state).write(to: directory.appendingPathComponent("removed-content.plist"), options: .atomic)
            saveError = ""
            return true
        } catch { saveError = "内容尚未删除成功，请检查磁盘空间和文件访问权限后重试。"; return false }
    }

    private func scrubConversationFiles() {
        guard let directory = conversationDirectory else { return }
        defer { reloadConversations() }
        do {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                var saved = try JSONDecoder().decode(SavedConversation.self, from: Data(contentsOf: url))
                saved.lines.removeAll { removed.records.contains($0.id) }
                if removed.conversations.contains(saved.id) || !saved.hasContent {
                    try FileManager.default.removeItem(at: url)
                } else {
                    try JSONEncoder().encode(saved).write(to: url, options: .atomic)
                }
            }
        } catch { saveError = "部分保存副本尚未清理成功，请检查文件访问权限后再次删除。" }
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
        guard deletionStateReadable else { return }
        if let data = userDefaults.data(forKey: historyKey) {
            do {
                let decoder = JSONDecoder()
                translationHistory = try decoder.decode([TranslationRecord].self, from: data).filter { !removed.records.contains($0.id) }
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
    var sessionTerms: [GlossaryTerm]? = nil
    var hasContent: Bool { !lines.isEmpty || !draft.isEmpty || !(sessionTerms ?? []).isEmpty }

    var title: String { String((lines.first?.originalText ?? (draft.isEmpty && !(sessionTerms ?? []).isEmpty ? "本场名单" : draft)).prefix(45)) }
    var unfinishedCount: Int { lines.filter { !$0.isCompleted }.count + (draft.isEmpty ? 0 : 1) }
    var searchText: String { lines.map { $0.originalText + " " + $0.translatedText }.joined(separator: " ") + " " + draft }
}
