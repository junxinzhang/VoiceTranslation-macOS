#!/bin/bash

# 权限测试脚本
# 用于验证系统音频权限修复

echo "🔍 VoiceTranslation 权限测试脚本"
echo "================================="

# 检查应用是否构建成功
echo "📦 检查应用构建状态..."
cd "$(dirname "$0")/.."

# 清理并重新构建应用
echo "🧹 清理旧构建..."
xcodebuild clean -project VoiceTranslation.xcodeproj -scheme VoiceTranslation -destination "platform=macOS" -quiet

echo "🔨 重新构建应用..."
BUILD_RESULT=$(xcodebuild build -project VoiceTranslation.xcodeproj -scheme VoiceTranslation -destination "platform=macOS" 2>&1)

if [ $? -eq 0 ]; then
    echo "✅ 应用构建成功"
else
    echo "❌ 应用构建失败"
    echo "构建错误详情:"
    echo "$BUILD_RESULT"
    exit 1
fi

# 检查权限配置
echo ""
echo "🔐 检查权限配置..."

# 检查 Info.plist 中的权限声明
PLIST_PATH="VoiceTranslation/Resources/Info.plist"
if /usr/libexec/PlistBuddy -c "Print :NSScreenRecordingUsageDescription" "$PLIST_PATH" >/dev/null 2>&1; then
    SCREEN_RECORDING_DESC=$(/usr/libexec/PlistBuddy -c "Print :NSScreenRecordingUsageDescription" "$PLIST_PATH")
    echo "✅ 屏幕录制权限描述: $SCREEN_RECORDING_DESC"
else
    echo "❌ 缺少屏幕录制权限描述 (NSScreenRecordingUsageDescription)"
fi

if /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$PLIST_PATH" >/dev/null 2>&1; then
    MIC_DESC=$(/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$PLIST_PATH")
    echo "✅ 麦克风权限描述: $MIC_DESC"
else
    echo "❌ 缺少麦克风权限描述 (NSMicrophoneUsageDescription)"
fi

# 检查 entitlements 文件
echo ""
echo "🛡️  检查 entitlements 权限..."

ENTITLEMENTS_PATH="VoiceTranslation/VoiceTranslation.entitlements"
if /usr/libexec/PlistBuddy -c "Print :com.apple.security.device.capture" "$ENTITLEMENTS_PATH" >/dev/null 2>&1; then
    echo "✅ 屏幕录制权限已在 entitlements 中声明"
else
    echo "❌ 屏幕录制权限未在 entitlements 中声明"
fi

if /usr/libexec/PlistBuddy -c "Print :com.apple.security.device.microphone" "$ENTITLEMENTS_PATH" >/dev/null 2>&1; then
    echo "✅ 麦克风权限已在 entitlements 中声明"
else
    echo "❌ 麦克风权限未在 entitlements 中声明"
fi

# 检查代码中的权限检查逻辑
echo ""
echo "🔍 检查代码中的权限处理逻辑..."

if grep -q "CGPreflightScreenCaptureAccess" VoiceTranslation/Services/SystemAudioCapture.swift; then
    echo "✅ 使用了 CGPreflightScreenCaptureAccess 预检查权限"
else
    echo "⚠️  未找到 CGPreflightScreenCaptureAccess 权限预检查"
fi

if grep -q "CGRequestScreenCaptureAccess" VoiceTranslation/Services/SystemAudioCapture.swift; then
    echo "✅ 使用了 CGRequestScreenCaptureAccess 请求权限"
else
    echo "⚠️  未找到 CGRequestScreenCaptureAccess 权限请求"
fi

if grep -q "audioSourceFallbackMessage" VoiceTranslation/ViewModels/MainViewModel.swift; then
    echo "✅ 添加了音频源回退提示机制"
else
    echo "⚠️  未找到音频源回退提示机制"
fi

echo ""
echo "📋 测试总结:"
echo "--------------------------------"
echo "1. 如果所有检查都显示 ✅，说明权限配置正确"
echo "2. 现在可以运行应用并测试系统音频功能"
echo "3. 如果仍有权限弹窗，请完全退出应用并重新启动"
echo "4. 确保在系统设置中手动授予屏幕录制权限"
echo ""
echo "🚀 要启动应用进行测试，请运行:"
echo "   open VoiceTranslation.xcodeproj"
echo ""