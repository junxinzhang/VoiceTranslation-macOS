//
//  AppSettings.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import Foundation
import Combine
import Security

class AppSettings: ObservableObject {

    // MARK: - Published Properties

    @Published var openAIApiKey: String = "" {
        didSet {
            if !isLoadingStoredSettings { saveStoredAPIKey(openAIApiKey, for: Constants.UserDefaults.openAIApiKey) }
        }
    }

    @Published var customAPIKey: String = "" {
        didSet {
            if !isLoadingStoredSettings { saveStoredAPIKey(customAPIKey, for: Constants.UserDefaults.customAPIKey) }
        }
    }
    @Published private(set) var apiKeyStorageWarning = ""
    private var secureStore: APIKeyStore = SystemAPIKeyStore()
    private var securelyStoredKeys: [String: String] = [:]

    @Published var customAPIBaseURL: String = Constants.CustomAPI.defaultBaseURL {
        didSet {
            saveToUserDefaults()
        }
    }

    @Published var customAPIModel: String = Constants.CustomAPI.defaultModel {
        didSet {
            saveToUserDefaults()
        }
    }

    @Published var apiProvider: APIProvider = .customAPI {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var selectedLanguageDirection: LanguageDirection = .chineseToEnglish {
        didSet {
            print("📝 语言方向已更新: \(selectedLanguageDirection.displayName)")
            print("📝 对应语音识别语言: \(selectedLanguageDirection.speechLocale)")
            saveToUserDefaults()
        }
    }
    
    @Published var keepHistory: Bool = true {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var maxHistoryItems: Int = 100 {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var autoDetectLanguage: Bool = false {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var showTranslationAnimation: Bool = true {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var audioInputSource: AudioInputSource = .microphone {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var hasCompletedOnboarding: Bool = false {
        didSet {
            saveToUserDefaults()
        }
    }
    
    /// 同声传译模式：按文本长度主动触发翻译，不等完整句子
    @Published var simultaneousTranslation: Bool = false {
        didSet {
            saveToUserDefaults()
        }
    }
    
    /// 同声传译触发阈值（字符数）
    @Published var simultaneousThreshold: Double = 50 {
        didSet {
            saveToUserDefaults()
        }
    }
    
    @Published var translationGlossary: [GlossaryTerm] = [] {
        didSet { saveToUserDefaults() }
    }
    @Published var useTranslationContext = true {
        didSet { saveToUserDefaults() }
    }

    // MARK: - Private Properties
    
    static let testUserDefaultsSuiteName = "\(Constants.App.bundleIdentifier).tests"

    private var legacyPreferencesURL: URL? = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Containers/\(Constants.App.bundleIdentifier)/Data/Library/Preferences/\(Constants.App.bundleIdentifier).plist")
    private let isRunningTests: Bool
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var isLoadingStoredSettings = false
    
    // MARK: - Initialization

    init() {
        self.isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.userDefaults = isRunningTests
            ? (UserDefaults(suiteName: Self.testUserDefaultsSuiteName) ?? .standard)
            : .standard

        // 单测环境隔离本机真实配置，不做沙盒迁移。
        if !isRunningTests {
            migrateFromSandboxIfNeeded()
        }
        loadFromUserDefaults()
    }

    /// Isolated storage for migration/failure tests; never touches the real keychain.
    init(secureStore: APIKeyStore, defaults: UserDefaults, legacyPreferencesURL: URL? = nil) {
        self.isRunningTests = false
        self.userDefaults = defaults
        self.secureStore = secureStore
        self.legacyPreferencesURL = legacyPreferencesURL
        migrateFromSandboxIfNeeded()
        loadFromUserDefaults()
    }

    // MARK: - Migration

    /// Revisit old files even after normal preferences have already migrated.
    private func migrateFromSandboxIfNeeded() {
        guard let url = legacyPreferencesURL, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let legacy = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            var removable = Set<String>()
            for key in [Constants.UserDefaults.openAIApiKey, Constants.UserDefaults.customAPIKey] {
                let fields = ["stored_" + key, key]
                guard let candidate = fields.compactMap({ legacy[$0] as? String }).first(where: { !$0.isEmpty }) else { continue }
                let current = loadStoredAPIKey(for: key)
                switch secureStore.read(service: keychainServiceName, account: key, allowInteraction: false) {
                case .value:
                    // An existing (possibly newer) secure key takes precedence over old copies.
                    removable.insert(key)
                case .missing:
                    let value = current.isEmpty ? candidate : current
                    if secureStore.save(value: value, service: keychainServiceName, account: key, allowInteraction: false),
                       case .value(let saved) = secureStore.read(service: keychainServiceName, account: key, allowInteraction: false), saved == value {
                        securelyStoredKeys[key] = saved
                        removable.insert(key)
                    } else { apiKeyStorageWarning = "旧密钥尚未安全迁移，旧副本已保留。请解锁钥匙串后重新保存。" }
                case .unavailable:
                    apiKeyStorageWarning = "暂时无法确认钥匙串中的密钥，旧副本已保留。请解锁钥匙串后重试。"
                }
            }
            if !cleanupLegacyKeyCopies(for: removable) {
                apiKeyStorageWarning = "密钥已安全保存，但旧配置副本尚未清理成功，请检查文件访问权限后重试。"
            }
            // Preserve existing preferences; copy only missing non-secret fields.
            let preferenceKeys = [Constants.UserDefaults.customAPIBaseURL, Constants.UserDefaults.customAPIModel,
                Constants.UserDefaults.apiProvider, Constants.UserDefaults.selectedLanguageDirection,
                Constants.UserDefaults.keepHistory, Constants.UserDefaults.maxHistoryItems,
                Constants.UserDefaults.audioInputSource, Constants.UserDefaults.hasCompletedOnboarding]
            for key in preferenceKeys where userDefaults.object(forKey: key) == nil {
                if let value = legacy[key] { userDefaults.set(value, forKey: key) }
            }
        } catch { apiKeyStorageWarning = "旧配置暂时无法读取，尚未清理密钥副本，请检查文件访问权限后重试。" }
    }

    /// Removes only credential fields, preserving unrelated settings and plist format.
    private func cleanupLegacyKeyCopies(for keys: Set<String>) -> Bool {
        guard !keys.isEmpty, let url = legacyPreferencesURL,
              FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard var values = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: &format) as? [String: Any] else { return false }
            var changed = false
            for key in keys {
                for field in [key, "stored_" + key] {
                    if values.removeValue(forKey: field) != nil { changed = true }
                }
            }
            if changed {
                let data = try PropertyListSerialization.data(fromPropertyList: values, format: format, options: 0)
                try data.write(to: url, options: .atomic)
            }
            guard let saved = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else { return false }
            return keys.allSatisfy { saved[$0] == nil && saved["stored_" + $0] == nil }
        } catch { return false }
    }

    // MARK: - UserDefaults Management

    private func loadFromUserDefaults() {
        isLoadingStoredSettings = true
        defer { isLoadingStoredSettings = false }

        openAIApiKey = loadStoredAPIKey(for: Constants.UserDefaults.openAIApiKey)
        customAPIKey = loadStoredAPIKey(for: Constants.UserDefaults.customAPIKey)
        customAPIBaseURL = userDefaults.string(forKey: Constants.UserDefaults.customAPIBaseURL) ?? Constants.CustomAPI.defaultBaseURL
        customAPIModel = userDefaults.string(forKey: Constants.UserDefaults.customAPIModel) ?? Constants.CustomAPI.defaultModel

        if let providerRaw = userDefaults.string(forKey: Constants.UserDefaults.apiProvider),
           let provider = APIProvider(rawValue: providerRaw) {
            apiProvider = provider
        }

        if let directionRaw = userDefaults.string(forKey: Constants.UserDefaults.selectedLanguageDirection),
           let direction = LanguageDirection(rawValue: directionRaw) {
            selectedLanguageDirection = direction
        }
        
        if userDefaults.object(forKey: Constants.UserDefaults.keepHistory) != nil {
            keepHistory = userDefaults.bool(forKey: Constants.UserDefaults.keepHistory)
        }
        
        let maxItems = userDefaults.integer(forKey: Constants.UserDefaults.maxHistoryItems)
        if maxItems > 0 {
            maxHistoryItems = maxItems
        }
        
        autoDetectLanguage = userDefaults.bool(forKey: Constants.UserDefaults.autoDetectLanguage)
        if userDefaults.object(forKey: Constants.UserDefaults.showTranslationAnimation) != nil {
            showTranslationAnimation = userDefaults.bool(forKey: Constants.UserDefaults.showTranslationAnimation)
        }
        
        if let audioSourceRaw = userDefaults.string(forKey: Constants.UserDefaults.audioInputSource),
           let audioSource = AudioInputSource(rawValue: audioSourceRaw) {
            audioInputSource = audioSource
        }
        
        hasCompletedOnboarding = userDefaults.bool(forKey: Constants.UserDefaults.hasCompletedOnboarding)
        
        if userDefaults.object(forKey: "simultaneousTranslation") != nil {
            simultaneousTranslation = userDefaults.bool(forKey: "simultaneousTranslation")
        }
        
        if let data = userDefaults.data(forKey: "translationGlossary"),
           let terms = try? JSONDecoder().decode([GlossaryTerm].self, from: data) {
            translationGlossary = terms
        }
        if userDefaults.object(forKey: "useTranslationContext") != nil {
            useTranslationContext = userDefaults.bool(forKey: "useTranslationContext")
        }
        let savedThreshold = userDefaults.double(forKey: "simultaneousThreshold")
        if savedThreshold > 0 {
            simultaneousThreshold = savedThreshold
        }
    }
    
    private func saveToUserDefaults() {
        guard !isLoadingStoredSettings else {
            return
        }

        if let data = try? JSONEncoder().encode(translationGlossary) {
            userDefaults.set(data, forKey: "translationGlossary")
        }
        userDefaults.set(useTranslationContext, forKey: "useTranslationContext")
        userDefaults.set(customAPIBaseURL, forKey: Constants.UserDefaults.customAPIBaseURL)
        userDefaults.set(customAPIModel, forKey: Constants.UserDefaults.customAPIModel)
        userDefaults.set(apiProvider.rawValue, forKey: Constants.UserDefaults.apiProvider)
        userDefaults.set(selectedLanguageDirection.rawValue, forKey: Constants.UserDefaults.selectedLanguageDirection)
        userDefaults.set(keepHistory, forKey: Constants.UserDefaults.keepHistory)
        userDefaults.set(maxHistoryItems, forKey: Constants.UserDefaults.maxHistoryItems)
        userDefaults.set(autoDetectLanguage, forKey: Constants.UserDefaults.autoDetectLanguage)
        userDefaults.set(showTranslationAnimation, forKey: Constants.UserDefaults.showTranslationAnimation)
        userDefaults.set(audioInputSource.rawValue, forKey: Constants.UserDefaults.audioInputSource)
        userDefaults.set(hasCompletedOnboarding, forKey: Constants.UserDefaults.hasCompletedOnboarding)
        userDefaults.set(simultaneousTranslation, forKey: "simultaneousTranslation")
        userDefaults.set(simultaneousThreshold, forKey: "simultaneousThreshold")
    }

    /// Migrate old preferences only after the keychain confirms a successful write.
    private func loadStoredAPIKey(for key: String) -> String {
        let oldKey = "stored_\(key)"
        if isRunningTests { return userDefaults.string(forKey: oldKey) ?? userDefaults.string(forKey: key) ?? "" }
        if let cached = securelyStoredKeys[key] { return cached }
        let legacy = userDefaults.string(forKey: oldKey) ?? userDefaults.string(forKey: key) ?? ""
        if !legacy.isEmpty {
            if secureStore.save(value: legacy, service: keychainServiceName, account: key, allowInteraction: false) {
                securelyStoredKeys[key] = legacy
                userDefaults.removeObject(forKey: oldKey)
                userDefaults.removeObject(forKey: key)
            } else {
                apiKeyStorageWarning = "旧密钥尚未迁入钥匙串，原配置已保留。请解锁钥匙串后重新保存密钥。"
            }
            return legacy
        }
        switch secureStore.read(service: keychainServiceName, account: key, allowInteraction: false) {
        case .value(let value): securelyStoredKeys[key] = value; return value
        case .missing: return ""
        case .unavailable:
            apiKeyStorageWarning = "暂时无法读取钥匙串中的密钥，请解锁钥匙串后重新打开应用，或重新填写密钥。"
            return ""
        }
    }

    @discardableResult
    private func saveStoredAPIKey(_ value: String, for key: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldKey = "stored_\(key)"
        if isRunningTests {
            if trimmed.isEmpty { userDefaults.removeObject(forKey: oldKey) }
            else { userDefaults.set(trimmed, forKey: oldKey) }
            return true
        }
        if securelyStoredKeys[key] == trimmed {
            let cleaned = cleanupLegacyKeyCopies(for: [key])
            if !cleaned { apiKeyStorageWarning = "旧配置中的密钥副本尚未清理成功，请检查文件访问权限后重试。" }
            return cleaned
        }
        let saved = trimmed.isEmpty
            ? secureStore.delete(service: keychainServiceName, account: key, allowInteraction: true)
            : secureStore.save(value: trimmed, service: keychainServiceName, account: key, allowInteraction: true)
        guard saved else {
            apiKeyStorageWarning = trimmed.isEmpty
                ? "钥匙串中的密钥暂未删除成功，请解锁钥匙串后重试。"
                : "密钥未能存入钥匙串，本次填写仅当前运行有效。请解锁钥匙串后重新保存。"
            return false
        }
        securelyStoredKeys[key] = trimmed
        userDefaults.removeObject(forKey: oldKey)
        userDefaults.removeObject(forKey: key)
        let cleaned = cleanupLegacyKeyCopies(for: [key])
        apiKeyStorageWarning = cleaned ? "" : "旧配置中的密钥副本尚未清理成功，请检查文件访问权限后重试。"
        return cleaned
    }

    /// Explicit user action may show macOS's Keychain approval after a signing change.
    func retryKeychainAccess() {
        guard !isRunningTests else { return }
        isLoadingStoredSettings = true
        defer { isLoadingStoredSettings = false }
        var blocked = false
        for key in [Constants.UserDefaults.openAIApiKey, Constants.UserDefaults.customAPIKey] {
            switch secureStore.read(service: keychainServiceName, account: key, allowInteraction: true) {
            case .value(let value):
                securelyStoredKeys[key] = value
                if key == Constants.UserDefaults.openAIApiKey { openAIApiKey = value }
                else { customAPIKey = value }
            case .missing: break
            case .unavailable: blocked = true
            }
        }
        apiKeyStorageWarning = blocked ? "仍无法读取已保存的密钥，请在 macOS 钥匙串提示中允许访问，或重新填写密钥。" : ""
    }

    private var keychainServiceName: String {
        (Bundle.main.bundleIdentifier ?? Constants.App.bundleIdentifier) + ".api-keys"
    }

    // MARK: - Built-in Key Support

    /// 用户是否正在使用内置 Key（没有自定义 Key 时自动回退到内置 Key）
    var isUsingBuiltInKey: Bool {
        switch apiProvider {
        case .openAI:
            return openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && BuiltInKeys.hasOpenAIKey
        case .customAPI:
            return customAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && BuiltInKeys.hasCustomAPIKey
        }
    }

    /// 当前 Provider 对应的用户自定义 Key（不含内置 Key）
    var userCustomKey: String {
        switch apiProvider {
        case .openAI:
            return openAIApiKey
        case .customAPI:
            return customAPIKey
        }
    }

    // MARK: - Validation
    
    var isApiKeyValid: Bool {
        // 如果使用内置 Key，直接视为有效
        if isUsingBuiltInKey {
            return true
        }

        let trimmedKey = currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        switch apiProvider {
        case .openAI:
            return trimmedKey.hasPrefix("sk-") && trimmedKey.count > 10
        case .customAPI:
            return trimmedKey.count >= 8
        }
    }

    var canTranslate: Bool {
        return isApiKeyValid && isCurrentProviderConfigurationValid
    }

    /// 当前实际使用的 API Key（优先用户自定义，否则回退到内置 Key）
    var currentAPIKey: String {
        switch apiProvider {
        case .openAI:
            let userKey = openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userKey.isEmpty {
                return userKey
            }
            return BuiltInKeys.openAIKey
        case .customAPI:
            let userKey = customAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userKey.isEmpty {
                return userKey
            }
            return BuiltInKeys.customAPIKey
        }
    }

    var currentAPIBaseURL: String {
        switch apiProvider {
        case .openAI:
            return Constants.OpenAI.baseURL
        case .customAPI:
            let trimmed = customAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? Constants.CustomAPI.defaultBaseURL : trimmed
        }
    }

    var currentModel: String {
        switch apiProvider {
        case .openAI:
            return Constants.OpenAI.model
        case .customAPI:
            let trimmed = customAPIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? Constants.CustomAPI.defaultModel : trimmed
        }
    }

    var isCurrentProviderConfigurationValid: Bool {
        switch apiProvider {
        case .openAI:
            return true
        case .customAPI:
            let trimmedModel = currentModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedModel.isEmpty else {
                return false
            }
            return Self.isValidHTTPURL(currentAPIBaseURL)
        }
    }

    private static func isValidHTTPURL(_ string: String) -> Bool {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              let host = url.host else {
            return false
        }
        return (scheme == "https" || scheme == "http") && !host.isEmpty
    }
    
    // MARK: - Reset Methods
    
    func resetToDefaults() {
        translationGlossary = []
        useTranslationContext = true
        openAIApiKey = ""
        customAPIKey = ""
        customAPIBaseURL = Constants.CustomAPI.defaultBaseURL
        customAPIModel = Constants.CustomAPI.defaultModel
        apiProvider = APIProvider.customAPI
        selectedLanguageDirection = .chineseToEnglish  // 默认为中文翻译英文，更符合中文用户习惯
        keepHistory = true
        maxHistoryItems = 100
        autoDetectLanguage = false
        showTranslationAnimation = true
        audioInputSource = .microphone
        hasCompletedOnboarding = false
    }
    
    func clearApiKey() {
        switch apiProvider {
        case .openAI:
            openAIApiKey = ""
        case .customAPI:
            customAPIKey = ""
        }
    }
}

// MARK: - Extensions

extension AppSettings {
    
    // MARK: - Computed Properties for UI
    
    var apiKeyDisplayText: String {
        // 使用内置 Key 时，显示特殊文本，不暴露任何 Key 信息
        if isUsingBuiltInKey {
            return "使用内置 Key"
        }

        let currentKey = userCustomKey
        if currentKey.isEmpty {
            return "未设置"
        } else if isApiKeyValid {
            let maskedSuffix = String(currentKey.suffix(4))
            switch apiProvider {
            case .openAI:
                return "sk-****" + maskedSuffix
            case .customAPI:
                return "****" + maskedSuffix
            }
        } else {
            return "无效密钥"
        }
    }
    
    var statusText: String {
        if !canTranslate {
            return "请检查 API 配置"
        } else {
            return "准备就绪"
        }
    }
}

enum APIKeyReadResult {
    case value(String)
    case missing
    case unavailable
}

protocol APIKeyStore {
    func save(value: String, service: String, account: String, allowInteraction: Bool) -> Bool
    func read(service: String, account: String, allowInteraction: Bool) -> APIKeyReadResult
    func delete(service: String, account: String, allowInteraction: Bool) -> Bool
}

struct SystemAPIKeyStore: APIKeyStore {
    private static let interactionLock = NSLock()

    /// kSecUseAuthenticationUIFail alone does not suppress classic macOS Keychain ACL prompts.
    /// Scope the legacy process-local UI setting to this one operation and restore it exactly.
    private func perform<T>(allowInteraction: Bool, failure: T, operation: () -> T) -> T {
        Self.interactionLock.lock()
        defer { Self.interactionLock.unlock() }
        var original = DarwinBoolean(true)
        guard SecKeychainGetUserInteractionAllowed(&original) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(allowInteraction) == errSecSuccess else { return failure }
        defer { SecKeychainSetUserInteractionAllowed(original.boolValue) }
        return operation()
    }

    private func query(service: String, account: String, allowInteraction: Bool) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        return query
    }

    func save(value: String, service: String, account: String, allowInteraction: Bool) -> Bool {
        perform(allowInteraction: allowInteraction, failure: false) {
            guard let data = value.data(using: .utf8) else { return false }
            let lookup = query(service: service, account: account, allowInteraction: allowInteraction)
            let result = SecItemUpdate(lookup as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if result == errSecSuccess { return true }
            guard result == errSecItemNotFound else { return false }
            var create = lookup
            create.removeValue(forKey: kSecUseAuthenticationUI as String)
            create[kSecValueData as String] = data
            return SecItemAdd(create as CFDictionary, nil) == errSecSuccess
        }
    }

    func read(service: String, account: String, allowInteraction: Bool) -> APIKeyReadResult {
        perform(allowInteraction: allowInteraction, failure: APIKeyReadResult.unavailable) {
            var lookup = query(service: service, account: account, allowInteraction: allowInteraction)
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let result = SecItemCopyMatching(lookup as CFDictionary, &item)
            if result == errSecItemNotFound { return .missing }
            guard result == errSecSuccess, let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else { return .unavailable }
            return .value(value)
        }
    }

    func delete(service: String, account: String, allowInteraction: Bool) -> Bool {
        perform(allowInteraction: allowInteraction, failure: false) {
            let result = SecItemDelete(query(service: service, account: account, allowInteraction: allowInteraction) as CFDictionary)
            return result == errSecSuccess || result == errSecItemNotFound
        }
    }
}
