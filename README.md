# Voice Real-time Translation · 语音实时翻译

macOS 实时语音转写与英中双向翻译。可听麦克风，也可翻译电脑正在播放的会议、视频和课程。

[English](README.en.md) · [使用说明](docs/guides/USER_GUIDE.md) · [隐私说明](PRIVACY.md) · [贡献指南](CONTRIBUTING.md) · [MIT License](LICENSE) · [实测记录](docs/VALIDATION.md) · [安装说明](docs/guides/INSTALLATION.md)

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![MIT](https://img.shields.io/badge/License-MIT-green) [![Build macOS](https://github.com/junxinzhang/VoiceTranslation-macOS/actions/workflows/build-macos.yml/badge.svg)](https://github.com/junxinzhang/VoiceTranslation-macOS/actions/workflows/build-macos.yml)

> **v1.0.3 安装包尚未完成 Apple Developer ID 签名和 Apple 公证。** macOS 可能阻止首次打开；下载不代表已通过苹果安全认证。请先阅读[安装与安全提示](docs/guides/INSTALLATION.md)。使用翻译功能需要自己的服务密钥，服务费用由所选服务商收取。

**[下载 DMG 安装包](https://github.com/junxinzhang/VoiceTranslation-macOS/releases/latest/download/VoiceTranslation.dmg)** · [ZIP 备用下载](https://github.com/junxinzhang/VoiceTranslation-macOS/releases/latest/download/VoiceTranslation.app.zip) · [版本说明与校验文件](https://github.com/junxinzhang/VoiceTranslation-macOS/releases/latest)

同一个安装包包含 Apple Silicon 和 Intel 两种架构；最低要求 macOS 13。Intel 和所有旧系统版本尚未逐一实机验证。

## 能做什么

- 麦克风与系统音频两种输入；支持静音时捕获系统音频。
- 实时显示原文和译文；短回答也翻译，连续讲话按意思分段。
- 通用术语表、本场名单和明确保存的纠错记忆辅助识别人名、专业词，保持译名一致；可参考前文。
- 重点核对数字、金额、日期和单位；发现译文改值或擅自补内容时重试，仍有疑点就保留原文并标明待核对。
- 听错后可修改某一段原文，自动更新译文；后续识别不会覆盖手动修改。
- 最多同时翻译两段，减少单段慢回复对后文的影响；显示剩余待译数量。
- 暂时失败会自动补译，也可手动重试；整场文字自动保存，重开后继续补译。
- 耳机切换、暂时断连和睡眠唤醒后尝试恢复收音；跟随系统当前麦克风，显示真实收音状态。
- 历史记录、文字导出和悬浮窗。

## 安装与首次使用

需要 **macOS 13 或更新版本**。系统音频在 macOS 14.2 及以上优先使用 Core Audio Tap，较早版本使用 ScreenCaptureKit；设备、权限和系统版本会影响实际表现。

1. 从上面的下载入口获取 DMG，打开后将应用拖入“应用程序”，推出安装镜像，再从“应用程序”打开。遇到安全提示时，按[安装说明](docs/guides/INSTALLATION.md)核对来源；不想使用未公证安装包时，可以按下文从源码构建。
2. 首次打开后允许麦克风和语音识别。系统音频模式还可能需要“屏幕与系统音频录制”权限，按应用提示操作。
3. 在“设置”填写自己的 API Key。支持 OpenAI 和兼容 Chat Completions 的自定义服务；填写完整接口地址和模型名称，然后测试连接。
4. 选择语言方向及声音来源，点击“开始翻译”。结束时点击“停止翻译”。

**公开版本不附送服务密钥或免费额度。** 识别和翻译并非始终离线：系统识别可能使用 Apple 在线服务；原文、相关术语及启用的前文会发送给你选择的翻译服务。开始前请阅读[隐私说明](PRIVACY.md)。

本地构建和 CI 默认是临时签名，未经过 Apple 公证；更新后可能再次要求授权。请自行核实下载来源，不要通过关闭系统安全保护来安装。应用内更新会打开官方下载页，由你选择安装。

## 从源码运行

需要完整 Xcode（含 macOS SDK）。代码没有第三方运行时包依赖。使用能构建当前 SDK 的 Xcode；macOS 13 是部署目标，不代表所有旧 Xcode 都能构建当前源码。

```bash
git clone https://github.com/junxinzhang/VoiceTranslation-macOS.git
cd VoiceTranslation-macOS
open VoiceTranslation.xcodeproj
```

在 Xcode 选择 `VoiceTranslation` 和 `My Mac` 运行；或使用命令行：

```bash
xcodebuild build \
  -project VoiceTranslation.xcodeproj -scheme VoiceTranslation \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build-local/DerivedData \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
open build-local/DerivedData/Build/Products/Release/VoiceTranslation.app
```

初次运行仍需在系统提示中授权，并在应用里填写服务配置。无需生成含密钥的源码文件，也无需配置 GitHub 服务密钥。

## 检查与测试

```bash
python3 scripts/check_public_source.py
bash scripts/test.sh
```

默认测试使用模拟回复，不需要真实服务密钥、麦克风授权或声音输入。测试结果放在忽略提交的 `build-local/`。真实音频、蓝牙和睡眠恢复需要单独在实际设备上验收，不能用单元测试通过替代。详见[测试说明](docs/guides/README_TESTING.md)。

## 当前限制

- 目前支持英中双向翻译；多人同时讲话、强噪声、口音和少见名字仍可能听错。
- 术语提示提高被识别的机会，不保证每次准确；最多使用前 100 个简短且不重复的源语言词组辅助识别，分段时也尽量保留这些词组。录音前保存术语可确保新识别请求采用它们。
- 两段同时翻译可以绕开个别慢回复，无法消除服务端整体拥堵；限流时会等待并自动重试。
- 本机文字历史和服务配置含敏感信息。密钥存于 macOS 钥匙串，旧配置迁移失败时会保留原值并提示；详见隐私说明。勿将本机设置、导出内容或测试备份上传。

## 目录

```text
VoiceTranslation/       macOS 应用源码
VoiceTranslationTests/  测试与模拟回复
scripts/                构建、测试、公开源码检查
docs/                   使用、测试与分发说明
assets/                 项目资源
```

欢迎提交问题和改进。[安全问题请按 SECURITY.md 处理](SECURITY.md)。本项目采用 [MIT License](LICENSE)；Apple 系统框架和第三方服务遵守各自条款。
