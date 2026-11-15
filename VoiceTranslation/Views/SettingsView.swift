//
//  SettingsView.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-11.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SettingsViewModel
    
    init(appSettings: AppSettings, translationService: TranslationService) {
        self._viewModel = StateObject(wrappedValue: SettingsViewModel(
            appSettings: appSettings,
            translationService: translationService
        ))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 内容区域
                ScrollView {
                    VStack(spacing: Constants.UI.padding * 2) {
                        // API 配置部分
                        apiConfigurationSection
                        if !viewModel.appSettings.apiKeyStorageWarning.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(viewModel.appSettings.apiKeyStorageWarning)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .accessibilityLabel("密钥保存提示")
                                Button("重新读取已保存的密钥") { viewModel.retryKeychainAccess() }
                            }
                        }
                        
                        Divider()
                        
                        terminologySection
                        Divider()

                        // 通用设置部分
                        generalSettingsSection
                        
                        Divider()
                        
                        // 关于部分
                        aboutSection
                    }
                    .padding(Constants.UI.padding * 2)
                }
                
                // 底部按钮栏
                bottomButtonBar
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .navigationTitle("设置")
        .alert("重置设置", isPresented: $viewModel.showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("确认重置", role: .destructive) {
                viewModel.confirmResetSettings()
            }
        } message: {
            Text("这将清除所有设置并恢复默认值。此操作无法撤销。")
        }
    }
    
    private var terminologySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("术语与前文")
                .font(.title2).fontWeight(.semibold)
            Text("填写常用人名、产品名和专业词，帮助识别并保持译名一致。最多 100 个简短词组用于识别，翻译仍使用完整术语表。")
                .font(.caption).foregroundColor(.secondary)
            Text("每行一条：英文 = 中文")
                .font(.subheadline)
            TextEditor(text: $viewModel.glossaryText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor)))
                .accessibilityLabel("术语表")
            Text("例如：Jensen Huang = 黄仁勋\nretrieval-augmented generation = 检索增强生成")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Button("保存术语表") { viewModel.saveGlossary() }
                if !viewModel.glossaryMessage.isEmpty {
                    Text(viewModel.glossaryMessage)
                        .font(.caption)
                        .foregroundColor(viewModel.glossaryHasError ? .red : .secondary)
                }
            }
            Toggle("参考前面说过的话", isOn: $viewModel.appSettings.useTranslationContext)
            Text("结合本次对话最近几段原文与已完成的译文，帮助理解代词并保持人名和专业词一致。清空本次内容后重新开始。")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - API Configuration Section
    
    private var apiConfigurationSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.padding) {
            Text("API 配置")
                .font(.title2)
                .fontWeight(.semibold)

            // API 提供者选择
            VStack(alignment: .leading, spacing: 8) {
                Text("API 提供者")
                    .fontWeight(.medium)

                Picker("", selection: $viewModel.selectedProvider) {
                    ForEach(APIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.bottom, 8)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.selectedProvider == .customAPI {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Base URL")
                            .fontWeight(.medium)

                        TextField(
                            "https://your-endpoint/v1/chat/completions",
                            text: $viewModel.tempCustomBaseURL
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        HStack {
                            if viewModel.isCustomBaseURLValid {
                                Label("Base URL 格式正确", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else {
                                Label("Base URL 需为 http/https 完整地址", systemImage: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            Spacer()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .fontWeight(.medium)

                        TextField(
                            "例如: anthropic/claude-sonnet-4 或 gpt-4o-mini",
                            text: $viewModel.tempCustomModel
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }

                HStack {
                    Text("API Key")
                        .fontWeight(.medium)

                    Spacer()

                    if viewModel.selectedProvider == .openAI {
                        Button("获取 API Key") {
                            viewModel.openOpenAIWebsite()
                        }
                        .buttonStyle(LinkButtonStyle())
                    }
                }
                
                // API Key 输入框
                HStack {
                    Group {
                        if viewModel.isUsingBuiltInKey {
                            // 内置 Key：显示固定遮罩文本，不暴露任何 Key 内容
                            Text("••••••••（内置）")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                )
                        } else if viewModel.showApiKey {
                            TextField(viewModel.selectedProvider == .openAI ? "sk-..." : "输入 API Key（留空使用内置 Key）", text: $viewModel.tempApiKey)
                        } else {
                            SecureField(viewModel.selectedProvider == .openAI ? "sk-..." : "输入 API Key（留空使用内置 Key）", text: $viewModel.tempApiKey)
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: viewModel.toggleApiKeyVisibility) {
                        Image(systemName: viewModel.showApiKey ? "eye.slash" : "eye")
                            .foregroundColor(viewModel.isUsingBuiltInKey ? .secondary.opacity(0.3) : .secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help(viewModel.isUsingBuiltInKey ? "内置 Key 不可查看" : (viewModel.showApiKey ? "隐藏 API Key" : "显示 API Key"))
                    .disabled(viewModel.isUsingBuiltInKey)
                }
                
                // API Key 状态
                HStack {
                    if viewModel.isUsingBuiltInKey {
                        Label(
                            "使用内置 API Key，无需配置",
                            systemImage: "checkmark.shield.fill"
                        )
                            .foregroundColor(.green)
                            .font(.caption)
                    } else if viewModel.isApiKeyValid {
                        Label(
                            viewModel.selectedProvider == .openAI ? "API Key 格式正确" : "API Key 已填写",
                            systemImage: "checkmark.circle.fill"
                        )
                            .foregroundColor(.green)
                            .font(.caption)
                    } else if !viewModel.tempApiKey.isEmpty {
                        Label(
                            viewModel.selectedProvider == .openAI ? "API Key 格式无效" : "API Key 长度过短",
                            systemImage: "xmark.circle.fill"
                        )
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Spacer()
                }
                
                // 连接测试结果
                if let result = viewModel.connectionTestResult {
                    HStack {
                        Image(systemName: result.icon)
                            .foregroundColor(result.color)
                        
                        Text(result.message)
                            .font(.caption)
                            .foregroundColor(result.color)
                    }
                }
                
                // 操作按钮
                HStack(spacing: 12) {
                    Button("测试连接") {
                        viewModel.testConnection()
                    }
                    .disabled(!viewModel.canTestConnection || viewModel.isTestingConnection)
                    
                    if viewModel.isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    
                    Spacer()

                    if viewModel.isUsingBuiltInKey {
                        // 当前使用内置 Key，显示切换到自定义的选项
                        Button("使用自定义 Key") {
                            viewModel.switchToCustomKey()
                        }
                        .font(.caption)
                    } else {
                        // 当前使用自定义 Key，如果内置 Key 可用则可以切换回去
                        let hasBuiltIn = (viewModel.selectedProvider == .openAI && BuiltInKeys.hasOpenAIKey) ||
                                         (viewModel.selectedProvider == .customAPI && BuiltInKeys.hasCustomAPIKey)
                        if hasBuiltIn {
                            Button("使用内置 Key") {
                                viewModel.switchToBuiltInKey()
                            }
                            .font(.caption)
                        }
                    }
                    
                    if viewModel.hasUnsavedChanges {
                        Button("保存", action: viewModel.saveApiKey)
                            .buttonStyle(BorderedProminentButtonStyle())
                    }
                    
                    Button("清空", action: viewModel.clearApiKey)
                        .disabled(viewModel.tempApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(Constants.UI.padding)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(Constants.UI.cornerRadius)
        }
    }
    
    // MARK: - General Settings Section
    
    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.padding) {
            Text("通用设置")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: Constants.UI.padding) {
                // 保持历史记录
                Toggle(isOn: $viewModel.appSettings.keepHistory) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("保存翻译历史")
                            .fontWeight(.medium)
                        Text("自动保存翻译记录到本地")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 最大历史记录数量
                if viewModel.appSettings.keepHistory {
                    HStack {
                        Text("最大历史记录数量")
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Stepper(value: $viewModel.appSettings.maxHistoryItems, 
                               in: 10...1000, 
                               step: 10) {
                            Text("\(viewModel.appSettings.maxHistoryItems)")
                                .frame(minWidth: 40)
                        }
                    }
                }
                
                Divider()
                
                // 显示翻译动画
                Toggle(isOn: $viewModel.appSettings.showTranslationAnimation) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("显示翻译动画")
                            .fontWeight(.medium)
                        Text("在翻译时显示动画效果")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 自动检测语言（未来功能）
                Toggle(isOn: $viewModel.appSettings.autoDetectLanguage) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动检测语言")
                            .fontWeight(.medium)
                        Text("自动识别输入语言（实验性功能）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(true) // 暂时禁用
            }
            .padding(Constants.UI.padding)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(Constants.UI.cornerRadius)
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.padding) {
            Text("关于")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("应用名称:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(Constants.App.appName)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("版本:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(Constants.App.version)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(viewModel.isCheckingUpdate ? "检查中..." : "检查更新") {
                            viewModel.checkForUpdates()
                        }
                        .disabled(viewModel.isCheckingUpdate || viewModel.isUpdatingApp)

                        Button("打开下载页") {
                            viewModel.updateNow()
                        }
                        .disabled(!viewModel.hasUpdateAvailable || viewModel.isUpdatingApp || viewModel.isCheckingUpdate)
                        .buttonStyle(BorderedProminentButtonStyle())
                    }

                    if !viewModel.updateStatusMessage.isEmpty {
                        Text(viewModel.updateStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("最低系统要求:")
                        .fontWeight(.medium)
                    Spacer()
                    Text("macOS 12.0+")
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                Text("功能特点:")
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("• 实时语音识别")
                    Text("• AI 智能翻译")
                    Text("• 中英文双向翻译")
                    Text("• 翻译历史记录")
                    Text("• 简洁易用界面")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(Constants.UI.padding)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(Constants.UI.cornerRadius)
        }
    }
    
    // MARK: - Bottom Button Bar
    
    private var bottomButtonBar: some View {
        HStack {
            Button("重置所有设置", action: viewModel.resetSettings)
                .foregroundColor(.red)
            
            Spacer()
            
            Button("完成") {
                guard viewModel.saveGlossary() else { return }
                if viewModel.hasUnsavedChanges {
                    viewModel.saveApiKey()
                }
                dismiss()
            }
            .buttonStyle(BorderedProminentButtonStyle())
        }
        .padding(Constants.UI.padding * 2)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .top
        )
    }
}

// MARK: - Custom Button Styles

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.blue)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .offset(y: 8)
                    .foregroundColor(.blue)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            appSettings: AppSettings(),
            translationService: TranslationService()
        )
    }
}
#endif
