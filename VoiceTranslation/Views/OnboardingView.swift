//
//  OnboardingView.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-16.
//

import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @EnvironmentObject var appSettings: AppSettings
    @Binding var isPresented: Bool
    @State private var currentStep: OnboardingStep = .welcome
    
    enum OnboardingStep {
        case welcome
        case languageSelection
        case completion
    }
    
    var body: some View {
        VStack(spacing: 0) {
            switch currentStep {
            case .welcome:
                WelcomeView(onNext: {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentStep = .languageSelection
                    }
                })
            case .languageSelection:
                LanguageSelectionView(
                    onSelection: { direction in
                        appSettings.selectedLanguageDirection = direction
                        withAnimation(.easeInOut(duration: 0.5)) {
                            currentStep = .completion
                        }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            currentStep = .welcome
                        }
                    }
                )
            case .completion:
                CompletionView(onComplete: {
                    appSettings.hasCompletedOnboarding = true
                    isPresented = false
                })
            }
        }
        .frame(minWidth: Constants.UI.minWindowWidth, minHeight: Constants.UI.minWindowHeight)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - WelcomeView

struct WelcomeView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: Constants.UI.padding * 3) {
            Spacer()
            
            // 应用图标和标题
            VStack(spacing: Constants.UI.padding * 2) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 120))
                    .foregroundColor(.blue)
                
                VStack(spacing: Constants.UI.padding) {
                    Text("欢迎使用语音实时翻译")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("跨语言交流的智能助手")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            
            // 功能介绍
            VStack(spacing: Constants.UI.padding * 2) {
                FeatureCard(
                    icon: "mic.and.signal.meter",
                    title: "实时语音识别",
                    description: "高精度语音转文本，支持中文和英文"
                )
                
                FeatureCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "智能翻译",
                    description: "基于 GPT-4 的专业翻译，自然流畅"
                )
                
                FeatureCard(
                    icon: "bolt.fill",
                    title: "即时反馈",
                    description: "实时显示翻译结果，提升沟通效率"
                )
            }
            
            Spacer()
            
            // 下一步按钮
            Button(action: onNext) {
                HStack(spacing: 8) {
                    Text("开始使用")
                        .font(.headline)
                    Image(systemName: "arrow.right")
                }
                .frame(height: 50)
                .frame(maxWidth: 300)
                .foregroundColor(.white)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(BorderlessButtonStyle())
            
            Spacer()
        }
        .padding(Constants.UI.padding * 3)
    }
}

// MARK: - LanguageSelectionView

struct LanguageSelectionView: View {
    @EnvironmentObject var appSettings: AppSettings
    let onSelection: (LanguageDirection) -> Void
    let onBack: () -> Void
    @State private var selectedDirection: LanguageDirection?
    
    var body: some View {
        VStack(spacing: Constants.UI.padding * 3) {
            Spacer()
            
            // 标题
            VStack(spacing: Constants.UI.padding) {
                Text("选择翻译方向")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("您希望从哪种语言翻译到哪种语言？")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // 语言方向选择
            VStack(spacing: Constants.UI.padding * 2) {
                ForEach(LanguageDirection.allCases, id: \.self) { direction in
                    LanguageDirectionCard(
                        direction: direction,
                        isSelected: selectedDirection == direction,
                        onSelection: {
                            selectedDirection = direction
                        }
                    )
                }
            }
            
            Spacer()
            
            // 底部按钮
            HStack(spacing: Constants.UI.padding * 2) {
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                        Text("上一步")
                    }
                    .frame(height: 50)
                    .frame(maxWidth: 150)
                    .foregroundColor(.secondary)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(25)
                }
                .buttonStyle(BorderlessButtonStyle())
                
                Spacer()
                
                Button(action: {
                    if let direction = selectedDirection {
                        onSelection(direction)
                    }
                }) {
                    HStack(spacing: 8) {
                        Text("确认选择")
                        Image(systemName: "arrow.right")
                    }
                    .frame(height: 50)
                    .frame(maxWidth: 200)
                    .foregroundColor(.white)
                    .background(
                        selectedDirection != nil ?
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            gradient: Gradient(colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.3)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(25)
                    .shadow(
                        color: selectedDirection != nil ? Color.blue.opacity(0.3) : Color.clear,
                        radius: selectedDirection != nil ? 10 : 0,
                        x: 0,
                        y: selectedDirection != nil ? 5 : 0
                    )
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(selectedDirection == nil)
            }
            
            Spacer()
        }
        .padding(Constants.UI.padding * 3)
        .onAppear {
            // 设置默认选择为当前设置的语言方向
            selectedDirection = appSettings.selectedLanguageDirection
        }
    }
}

// MARK: - CompletionView

struct CompletionView: View {
    @EnvironmentObject var appSettings: AppSettings
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: Constants.UI.padding * 3) {
            Spacer()
            
            // 成功图标
            VStack(spacing: Constants.UI.padding * 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 120))
                    .foregroundColor(.green)
                
                VStack(spacing: Constants.UI.padding) {
                    Text("设置完成！")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("您已选择 \(appSettings.selectedLanguageDirection.displayName) 翻译模式")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // 使用提示
            VStack(spacing: Constants.UI.padding * 1.5) {
                Text("使用小贴士")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: Constants.UI.padding) {
                    UsageTip(
                        icon: "mic.circle.fill",
                        text: "点击录音按钮开始实时翻译"
                    )
                    
                    UsageTip(
                        icon: "keyboard",
                        text: "按空格键快速完成当前翻译"
                    )
                    
                    UsageTip(
                        icon: "arrow.triangle.2.circlepath",
                        text: "随时可在主界面切换翻译方向"
                    )
                    
                    UsageTip(
                        icon: "gearshape.fill",
                        text: "在设置中配置 API Key 与服务端点"
                    )
                }
                .padding(Constants.UI.padding * 1.5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(Constants.UI.cornerRadius)
            }
            
            Spacer()
            
            // 开始使用按钮
            Button(action: onComplete) {
                HStack(spacing: 8) {
                    Text("开始翻译")
                        .font(.headline)
                    Image(systemName: "play.fill")
                }
                .frame(height: 50)
                .frame(maxWidth: 300)
                .foregroundColor(.white)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
                .shadow(color: Color.green.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(BorderlessButtonStyle())
            
            Spacer()
        }
        .padding(Constants.UI.padding * 3)
    }
}

// MARK: - Supporting Views

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: Constants.UI.padding * 1.5) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(Constants.UI.padding * 1.5)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(Constants.UI.cornerRadius)
    }
}

struct LanguageDirectionCard: View {
    let direction: LanguageDirection
    let isSelected: Bool
    let onSelection: () -> Void
    
    var body: some View {
        Button(action: onSelection) {
            HStack(spacing: Constants.UI.padding * 1.5) {
                // 语言方向图标
                Text(direction.icon)
                    .font(.largeTitle)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(direction.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("从\(direction.sourceLanguage)翻译到\(direction.targetLanguage)")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 选择指示器
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .padding(Constants.UI.padding * 1.5)
            .background(
                isSelected ?
                Color.blue.opacity(0.1) :
                Color(NSColor.controlBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Constants.UI.cornerRadius)
                    .stroke(
                        isSelected ? Color.blue : Color.clear,
                        lineWidth: 2
                    )
            )
            .cornerRadius(Constants.UI.cornerRadius)
        }
        .buttonStyle(BorderlessButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct UsageTip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: Constants.UI.padding) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 25)
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(isPresented: .constant(true))
            .environmentObject(AppSettings())
    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(onNext: {})
    }
}

struct LanguageSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        LanguageSelectionView(
            onSelection: { _ in },
            onBack: {}
        )
        .environmentObject(AppSettings())
    }
}

struct CompletionView_Previews: PreviewProvider {
    static var previews: some View {
        CompletionView(onComplete: {})
            .environmentObject(AppSettings())
    }
}
#endif
