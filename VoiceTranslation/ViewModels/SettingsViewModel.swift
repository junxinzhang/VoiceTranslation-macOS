//
//  SettingsViewModel.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation
import SwiftUI
import AppKit

@MainActor
class SettingsViewModel: ObservableObject {
    
    // MARK: - Published Properties

    @Published var tempApiKey: String = ""
    @Published var tempCustomBaseURL: String = Constants.CustomAPI.defaultBaseURL
    @Published var tempCustomModel: String = Constants.CustomAPI.defaultModel
    @Published var showApiKey: Bool = false
    @Published var isTestingConnection: Bool = false
    @Published var connectionTestResult: ConnectionTestResult?
    @Published var showDeleteConfirmation: Bool = false
    @Published var isCheckingUpdate: Bool = false
    @Published var isUpdatingApp: Bool = false
    @Published var updateStatusMessage: String = ""
    @Published var latestVersion: String?
    @Published var hasUpdateAvailable: Bool = false
    @Published var wantsCustomKey: Bool = false
    @Published var selectedProvider: APIProvider = .openAI {
        didSet {
            onProviderChanged()
        }
    }
    
    @Published var glossaryText = ""
    @Published var glossaryMessage = ""
    @Published var glossaryHasError = false

    @discardableResult
    func saveGlossary() -> Bool {
        do {
            let terms = try Glossary.parse(glossaryText)
            appSettings.translationGlossary = terms
            glossaryMessage = "已保存 \(terms.count) 条术语，会辅助识别并统一新译文。"
            glossaryHasError = false
            return true
        } catch {
            glossaryMessage = error.localizedDescription
            glossaryHasError = true
            return false
        }
    }

    // MARK: - Dependencies
    
    @Published var appSettings: AppSettings
    private let translationService: TranslationService
    
    // MARK: - Initialization
    
    init(appSettings: AppSettings, translationService: TranslationService) {
        self.appSettings = appSettings
        self.translationService = translationService
        self.glossaryText = Glossary.text(appSettings.translationGlossary)
        self.selectedProvider = appSettings.apiProvider
        loadInputsForSelectedProvider()
        // 如果用户已经有自定义 Key，设置 wantsCustomKey = true
        self.wantsCustomKey = !tempApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Public Methods
    
    func saveApiKey() {
        applyTemporaryInputsToSettings()
        appSettings.apiProvider = selectedProvider
        connectionTestResult = nil
    }
    
    func retryKeychainAccess() {
        appSettings.retryKeychainAccess()
        loadInputsForSelectedProvider()
        connectionTestResult = nil
    }

    func clearApiKey() {
        tempApiKey = ""
        switch selectedProvider {
        case .openAI:
            appSettings.openAIApiKey = ""
        case .customAPI:
            appSettings.customAPIKey = ""
        }

        connectionTestResult = nil
    }
    
    func toggleApiKeyVisibility() {
        // 内置 Key 时不允许显示
        guard !isUsingBuiltInKey else { return }
        showApiKey.toggle()
    }
    
    func testConnection() {
        guard !translationService.isTranslating else {
            connectionTestResult = .failure("正在翻译，请稍后再测试连接。")
            return
        }
        guard canTestConnection else {
            connectionTestResult = .failure(connectionValidationMessage)
            return
        }
        
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            let originalContext = translationService.context
            translationService.context = TranslationContext()
            defer { translationService.context = originalContext }
            let originalProvider = appSettings.apiProvider
            let originalOpenAIKey = appSettings.openAIApiKey
            let originalCustomKey = appSettings.customAPIKey
            let originalCustomBaseURL = appSettings.customAPIBaseURL
            let originalCustomModel = appSettings.customAPIModel

            appSettings.apiProvider = selectedProvider
            applyTemporaryInputsToSettings()
            
            await translationService.translateText("Hello", direction: .englishToChinese)
            
            await MainActor.run {
                if let error = translationService.error {
                    self.connectionTestResult = .failure(error.localizedDescription)
                } else if !translationService.translatedText.isEmpty {
                    self.connectionTestResult = .success("连接成功！配置有效。")
                } else {
                    self.connectionTestResult = .failure("连接测试失败，请检查 API 配置。")
                }
                
                if case .failure = self.connectionTestResult {
                    self.appSettings.apiProvider = originalProvider
                    self.appSettings.openAIApiKey = originalOpenAIKey
                    self.appSettings.customAPIKey = originalCustomKey
                    self.appSettings.customAPIBaseURL = originalCustomBaseURL
                    self.appSettings.customAPIModel = originalCustomModel
                    self.loadInputsForSelectedProvider()
                }
                
                self.isTestingConnection = false
            }
        }
    }
    
    func resetSettings() {
        showDeleteConfirmation = true
    }
    
    func confirmResetSettings() {
        appSettings.resetToDefaults()
        glossaryText = ""
        glossaryMessage = ""
        glossaryHasError = false
        selectedProvider = appSettings.apiProvider
        loadInputsForSelectedProvider()
        connectionTestResult = nil
        showDeleteConfirmation = false
    }
    
    func openOpenAIWebsite() {
        if let url = URL(string: "https://platform.openai.com/api-keys") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func validateApiKey(_ key: String) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        switch selectedProvider {
        case .openAI:
            return trimmedKey.hasPrefix("sk-") && trimmedKey.count > 20
        case .customAPI:
            return trimmedKey.count >= 8
        }
    }

    func checkForUpdates() {
        isCheckingUpdate = true
        updateStatusMessage = "正在检查更新..."

        Task {
            do {
                let release = try await fetchLatestRelease()
                let latest = normalizeVersion(release.tagName)
                let current = normalizeVersion(Constants.App.shortVersion)

                await MainActor.run {
                    self.latestVersion = latest
                    self.hasUpdateAvailable = compareVersion(latest, current) == .orderedDescending
                    if self.hasUpdateAvailable {
                        self.updateStatusMessage = "发现新版本 \(latest)，可打开下载页"
                    } else {
                        self.updateStatusMessage = "当前已是最新版本（\(current)）"
                    }
                    self.isCheckingUpdate = false
                }
            } catch {
                await MainActor.run {
                    self.updateStatusMessage = "检查更新失败：\(error.localizedDescription)"
                    self.isCheckingUpdate = false
                }
            }
        }
    }

    func updateNow() {
        let url = URL(string: "https://github.com/junxinzhang/VoiceTranslation-macOS/releases/latest")!
        updateStatusMessage = NSWorkspace.shared.open(url)
            ? "已打开官方下载页，当前应用会继续运行。"
            : "无法打开下载页，请在浏览器中访问项目的 Releases 页面。"
    }
    
    // MARK: - Computed Properties

    /// 当前是否正在使用内置 Key（用户没有填写自定义 Key，且内置 Key 可用，且用户没有主动选择自定义）
    var isUsingBuiltInKey: Bool {
        // 用户主动要求使用自定义 Key 时，不返回 true
        if wantsCustomKey {
            return false
        }
        let trimmed = tempApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return false
        }
        switch selectedProvider {
        case .openAI:
            return BuiltInKeys.hasOpenAIKey
        case .customAPI:
            return BuiltInKeys.hasCustomAPIKey
        }
    }

    /// 切换到自定义 Key 输入模式
    func switchToCustomKey() {
        wantsCustomKey = true
    }

    /// 切换回内置 Key 模式
    func switchToBuiltInKey() {
        tempApiKey = ""
        wantsCustomKey = false
        // 同时清空已保存的自定义 Key
        clearApiKey()
    }

    var isApiKeyValid: Bool {
        // 内置 Key 直接视为有效
        if isUsingBuiltInKey {
            return true
        }
        return validateApiKey(tempApiKey)
    }

    var isCustomBaseURLValid: Bool {
        return Self.validateHTTPURL(tempCustomBaseURL)
    }

    var isCustomModelValid: Bool {
        return !tempCustomModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canTestConnection: Bool {
        guard isApiKeyValid else {
            return false
        }

        if selectedProvider == .customAPI {
            return isCustomBaseURLValid && isCustomModelValid
        }
        return true
    }

    var connectionValidationMessage: String {
        if tempApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请输入 API Key"
        }

        if !isApiKeyValid {
            return selectedProvider == .openAI ? "OpenAI Key 格式无效" : "Custom API Key 格式无效"
        }

        if selectedProvider == .customAPI {
            if !isCustomBaseURLValid {
                return "请输入合法的 Base URL（需包含 http/https）"
            }
            if !isCustomModelValid {
                return "请输入 Model"
            }
        }

        return "配置不完整"
    }
    
    var hasUnsavedChanges: Bool {
        switch selectedProvider {
        case .openAI:
            return tempApiKey != appSettings.openAIApiKey || selectedProvider != appSettings.apiProvider
        case .customAPI:
            let normalizedBaseURL = normalizedCustomBaseURL
            let normalizedModel = normalizedCustomModel
            return tempApiKey != appSettings.customAPIKey ||
                   normalizedBaseURL != appSettings.customAPIBaseURL ||
                   normalizedModel != appSettings.customAPIModel ||
                   selectedProvider != appSettings.apiProvider
        }
    }

    // MARK: - Private Methods

    private func onProviderChanged() {
        loadInputsForSelectedProvider()
        // 切换 provider 时，检查新 provider 是否有自定义 Key
        wantsCustomKey = !tempApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        connectionTestResult = nil
    }

    private func loadInputsForSelectedProvider() {
        switch selectedProvider {
        case .openAI:
            tempApiKey = appSettings.openAIApiKey
        case .customAPI:
            tempApiKey = appSettings.customAPIKey
            tempCustomBaseURL = appSettings.customAPIBaseURL
            tempCustomModel = appSettings.customAPIModel
        }
    }

    private func applyTemporaryInputsToSettings() {
        let trimmedKey = tempApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch selectedProvider {
        case .openAI:
            appSettings.openAIApiKey = trimmedKey
        case .customAPI:
            appSettings.customAPIKey = trimmedKey
            appSettings.customAPIBaseURL = normalizedCustomBaseURL
            appSettings.customAPIModel = normalizedCustomModel
            tempCustomBaseURL = appSettings.customAPIBaseURL
            tempCustomModel = appSettings.customAPIModel
        }
    }

    private var normalizedCustomBaseURL: String {
        let trimmed = tempCustomBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.CustomAPI.defaultBaseURL : trimmed
    }

    private var normalizedCustomModel: String {
        let trimmed = tempCustomModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Constants.CustomAPI.defaultModel : trimmed
    }

    private static func validateHTTPURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host else {
            return false
        }
        return (scheme == "https" || scheme == "http") && !host.isEmpty
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/junxinzhang/VoiceTranslation-macOS/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Updater", code: 500, userInfo: [NSLocalizedDescriptionKey: "获取最新 release 失败"]) 
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func normalizeVersion(_ raw: String) -> String {
        let noPrefix = raw.replacingOccurrences(of: "v", with: "", options: .caseInsensitive)
        return noPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let la = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let ra = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(la.count, ra.count)
        for i in 0..<count {
            let lv = i < la.count ? la[i] : 0
            let rv = i < ra.count ? ra[i] : 0
            if lv > rv { return .orderedDescending }
            if lv < rv { return .orderedAscending }
        }
        return .orderedSame
    }


}

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

// MARK: - Supporting Types

extension SettingsViewModel {
    enum ConnectionTestResult {
        case success(String)
        case failure(String)
        
        var isSuccess: Bool {
            switch self {
            case .success:
                return true
            case .failure:
                return false
            }
        }
        
        var message: String {
            switch self {
            case .success(let message), .failure(let message):
                return message
            }
        }
        
        var color: Color {
            switch self {
            case .success:
                return .green
            case .failure:
                return .red
            }
        }
        
        var icon: String {
            switch self {
            case .success:
                return "checkmark.circle.fill"
            case .failure:
                return "xmark.circle.fill"
            }
        }
    }
}
