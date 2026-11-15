# 隐私与数据说明 / Privacy and data

## 声音与文字会去哪里

- 麦克风模式读取所选麦克风；系统音频模式读取电脑播放的声音，不主动混入麦克风。系统授权范围及实际输入应以应用状态和 macOS 提示为准。
- 识别使用 Apple Speech。某些设备、语言和恢复路径可能使用 Apple 在线识别，不能把本应用理解为全程离线。
- 翻译把原文发送到你设置的服务地址，并使用你提供的密钥。相关术语和开启的前文也会随请求发送。前文限于同一场、相同方向的前面几段原文和已完成的译文，不包含尚未说到的后文。
- 悬浮窗中的建议功能也可能将对话内容发送给同一配置的服务；不需要时请勿触发建议生成。
- 应用不提供自有转发服务器或共享服务密钥。所选服务可能收费并保留请求，请自行查看该服务的政策。
- 手动“检查更新”会访问本项目的 GitHub Releases；下载按钮打开官方下载页。

## 本机保存

- 应用保存识别文字和译文，**不将整场录音保存成音频文件**。
- 开启历史记录时，整场内容保存在 `~/Library/Application Support/VoiceTranslation/Conversations/`，旧版逐条记录可能仍在应用偏好设置中。导出的文字也含原文和译文。
- 关闭历史记录不会自动删除之前已保存的内容。“清空”主界面会结束当前场次，保留已保存的历史；删除历史请使用历史记录中的删除操作。
- 正式运行时，API 密钥存入 macOS 钥匙串，不写入新偏好设置。升级时会尝试将旧版偏好设置中的密钥迁入钥匙串，确认保存成功后才移除旧值。
- 如果迁移失败，旧配置保留并显示提示；新填写的密钥如保存失败，仅在当前运行中有效，不会退回明文保存。临时签名、钥匙串锁定、系统权限可能影响读取，请留意设置中的保存提示。更新后如需再次授权，可在设置中点击“重新读取已保存的密钥”，由你在 macOS 提示中批准；应用不会绕过系统认证。
- 文字历史、术语表和导出文件不是加密保险箱。设备备份可能包含它们；请使用自己的设备访问保护并管理好导出文件。
- 常规日志不写出识别原文、译文或服务密钥；设备故障诊断仍可能包含设备名称、系统版本和错误描述。提交日志前请自行检查。

## 发布源码或反馈问题前

不要上传本机偏好设置、钥匙串导出、真实对话、音频、私人截图、API 密钥、`build-local/` 或本机备份。请用虚构样例描述问题。

如果你曾把密钥放进公开源码或安装包，仅删除文件不能撤销泄露；应到原服务撤销该密钥并检查用量。

## English summary

Apple Speech may use online recognition. Transcripts, matching glossary terms and enabled recent context are sent to the translation provider you configure; optional conversation suggestions use that provider as well. Your provider's retention and billing policies apply. Manual update checks contact GitHub.

The app saves conversation text locally when history is enabled, not full audio recordings. Existing history is not deleted by disabling future history saving. The main Clear action ends the current conversation and retains saved history.

Production API keys use macOS Keychain. Legacy preference values are removed only after a successful migration; failed migrations retain the old configuration and display a warning. New keys are never saved back to plain preferences if secure storage fails. Ad-hoc signing or a locked keychain can affect access. Conversation files, glossary settings, exports and diagnostic device information may still be sensitive. Do not upload them or local backups when reporting issues.
