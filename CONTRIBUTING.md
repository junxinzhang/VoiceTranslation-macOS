# Contributing / 贡献流程

## Quick Workflow（Issue -> Branch -> PR -> CI）
1. 提交 `Issue`
- Bug 用 `Bug Report` 模板，需求用 `Feature Request` 模板。
- 填写完整复现信息/验收标准，并给出预期分支名。

2. 创建 `Branch`
- 按 [branch-naming](docs/branch-naming.md) 命名：
`feat/<scope>-<short>`、`fix/<scope>-<short>`、`chore/<scope>-<short>`、`hotfix/<scope>-<short>`。

3. 发起 `PR`
- 使用 `.github/pull_request_template.md`。
- 若有 UI 变更，必须提供 Before/After 截图链接。
- 写清测试证据、风险与回滚方案、关联 issue。

4. 等待 `CI`
- 确保 GitHub Actions 全部通过后再合并。
- 若失败，先修复再请求 review。

## 代码卫生规则
- 不要提交历史备份实现文件（如 `*_old.swift`、`*_backup.swift`）。
- 历史版本以 Git 提交历史/Tag 为准，不在主源码目录保留并行实现。


## 本地验证

从仓库根目录执行 `python3 scripts/check_public_source.py` 和 `bash scripts/test.sh`。默认测试使用模拟回复；不要提交真实 API 密钥、对话、录音、个人截图或 `build-local/`。新增测试必须加入 Xcode 工程，不能只新增未运行的文件。

涉及声音采集、设备切换和睡眠唤醒的修改，需要实际设备验收并说明系统与输入来源。不得把旧版本的验收结果当成新版通过，也不得用状态文字替代新的识别与译文。

公开版本不附带服务凭据。不要恢复向安装包注入 GitHub 服务密钥的流程。安全问题按 [SECURITY.md](SECURITY.md) 私下反馈。贡献的项目代码按 [MIT License](LICENSE) 提供。
