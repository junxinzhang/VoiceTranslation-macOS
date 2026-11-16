# 下载、安装与首次使用

[English](#english) · [完整使用说明](USER_GUIDE.md) · [版本与下载](https://github.com/junxinzhang/VoiceTranslation-macOS/releases/latest)

## 苹果认证状态

**v1.0.3 尚未使用 Apple Developer ID 签名，也未通过 Apple 公证。** 安装包使用临时签名，不是 App Store 版本，不能宣称已通过苹果的恶意软件检查。macOS 可能阻止首次启动；构建通过和文件校验一致均不能替代苹果认证。

如果不愿使用尚未公证的安装包，请先不要安装，可审阅源码后自行构建，或等待完成认证的后续版本。是否继续安装应由你自己决定。

## 需要准备什么

- macOS 13 或更新版本。下载包同时包含 Apple Silicon 与 Intel 架构，但不是所有机型和旧系统版本都已实测。
- 自己的 OpenAI 或兼容服务密钥及可用额度。安装包不含服务密钥和免费额度，翻译可能产生服务费用。
- 麦克风、语音识别和所选声音来源需要的系统音频权限。

## 下载及核对

只从本项目的 [GitHub Releases](https://github.com/junxinzhang/VoiceTranslation-macOS/releases/latest) 下载。推荐 `VoiceTranslation.dmg`；`VoiceTranslation.app.zip` 是备用形式。不要从不明网盘、私信附件或镜像下载。

同时下载本版 `SHA256SUMS.txt`。如需核对，在下载目录打开终端运行：

```bash
shasum -a 256 VoiceTranslation.dmg
```

将输出与校验文件中同名文件的那一行逐字比较。ZIP 使用同样方式核对。校验不一致时停止安装，重新从本页下载并反馈；校验一致仅表示文件内容一致，不证明软件安全。

## 安装

1. 打开 DMG，把 `VoiceTranslation.app` 拖入“应用程序”。若使用 ZIP，解压后把应用移入“应用程序”。
2. 如果替换旧版本，先在应用内停止录音并正常退出。重要内容先导出；不要在更新时删除本机历史或钥匙串。
3. 推出安装镜像，从“应用程序”打开“语音翻译”。不要一直在安装镜像里运行。
4. 阅读系统实际显示的安全提示。不要输入任何来自陌生人的所谓解锁命令。

## 遇到系统安全提醒

Apple 的[官方说明](https://support.apple.com/zh-cn/102445)介绍了不同提醒的含义和处理方式：

- **无法验证开发者 / Apple 无法检查是否包含恶意软件**：这是本版尚未完成签名、公证时可能出现的提醒。只有在你确认来源可信、文件未被修改并愿意接受风险后，才按 Apple 官方说明，在尝试打开后查看“系统设置 → 隐私与安全性”中针对这个应用的“仍要打开”选项。它只应由你手动决定，本文不会替你关闭安全保护。
- **将损坏电脑 / App 已损坏 / 已移入废纸篓**：停止安装。先核对下载来源与校验值，不要把这类提醒当成普通的首次打开提示，也不要通过清除隔离属性来隐藏提醒。
- **企业管理的 Mac**：可能没有相应选项，按组织要求联系 IT，不绕过管理策略。

不提供关闭 Gatekeeper、全局放开应用来源或批量移除隔离属性的安装步骤。

## 首次使用

1. 在系统弹窗中允许语音识别及麦克风。选择系统音频时，再按实际提示允许系统录音；部分系统版本使用“录屏与系统录音”这一名称。
2. 在“设置”选择翻译服务，填写自己的密钥。自定义服务填写完整 Chat Completions 地址和模型名称，点击“测试连接”。不要在公开反馈里贴密钥。
3. 选择 English → 中文，或反向中文 → English；选择麦克风听现场声音，或系统音频听电脑播放内容。
4. 点击“开始翻译”，等状态显示已准备好再讲话或播放。先用无隐私的短句试一下，确认本次有新的文字及译文。
5. 停止后等“待译”数量归零，再用“导出本次”保存。术语表、原文纠正与重开补译的详细操作见[使用说明](USER_GUIDE.md)。

权限开启不等于本次已收到声音；旧文字也不代表仍在收音。更新后若再次询问权限，请确认当前应用后在系统提示中处理。若设置里已开启但仍不能收音，请提供系统版本、声音来源及无隐私的错误描述，勿上传真实会议或本机配置文件。

语音识别可能使用 Apple 在线服务，原文、相关术语及启用的前文会发给你选定的翻译服务。本机保存的是文字历史，并非加密保险箱。使用前阅读[隐私说明](../../PRIVACY.md)。

## English

### Distribution status

**v1.0.3 is NOT signed with an Apple Developer ID and is NOT notarized by Apple.** It uses ad-hoc signing and is not an App Store release. macOS may block first launch. Build success and matching checksums are not Apple security approval. If you do not accept this, do not install the binaries; review/build the source or wait for a notarized version.

### Download and install

Download only from this repository's [Releases](https://github.com/junxinzhang/VoiceTranslation-macOS/releases/latest). Choose `VoiceTranslation.dmg` or the ZIP alternative and get `SHA256SUMS.txt`. Run `shasum -a 256 VoiceTranslation.dmg` in the download directory and compare with the matching entry; a checksum confirms file integrity, not safety.

Open the DMG, drag the app into Applications, eject the image and launch from Applications. For ZIP, unzip and move the app into Applications. Stop recording and quit the old app before replacing it; keep important exports and do not delete history or Keychain data.

For unverified-developer or malware-check-unavailable notices, consult [Apple's guidance](https://support.apple.com/en-us/102445). Only if you trust the source, have verified integrity and accept the risk should you consider Apple's manual per-app option in Privacy & Security. Do not disable system protections. Stop and investigate any corruption or malware warning. Managed Macs may require IT approval.

### First run

Grant the requested speech, microphone and system-audio permissions. Configure your own OpenAI or compatible provider credentials, endpoint and model in Settings; test the connection. Select English–Chinese direction and the audio source, start translation and wait until capture is ready. Test a non-sensitive sentence, then stop and wait for pending translations before exporting. See the [user guide (Chinese)](USER_GUIDE.md) and [privacy notice](../../PRIVACY.md).
