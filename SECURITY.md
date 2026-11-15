# Security policy / 安全问题反馈

安全修复以默认分支的当前源码为准。旧版下载包不承诺继续得到补丁；请核对源码版本和下载来源。

发现密钥泄露、未经授权的数据发送、更新包替换或其他安全问题时，请使用本仓库 GitHub 的 **Security → Report a vulnerability** 私密入口（仓库启用该功能时）。若入口不可用，请勿在公开 Issue 贴出密钥、真实对话或可直接利用的细节；可以先提交不含敏感内容的问题，请维护者提供私下反馈渠道。

反馈请说明受影响版本、复现条件、影响范围和不含真实凭据的示例。不要访问他人的服务额度或采集他人的会议内容来验证问题。

## 发布者检查

- 公开应用必须使用空的 `BuiltInKeys.swift`，不得将 GitHub Secrets 注入可分发程序。
- 运行 `python3 scripts/check_public_source.py`。该检查只做基本拦截，不保证发现所有秘密；发布前还应审阅提交内容及历史。
- 不发布 `build-local/`、本机配置、测试备份和真实会议数据。
- 安装包默认使用临时签名，未公证。面向更广泛用户分发时，应使用自己的 Developer ID 签名、公证，并说明验证方式；不指导用户关闭系统安全保护。
- 应用内更新仅打开官方下载页，不静默删除、替换当前应用。

Security reports should use GitHub's private vulnerability reporting feature when enabled. Do not post live credentials, private conversations or exploit details in public issues. If private reporting is unavailable, open a non-sensitive contact request first.
