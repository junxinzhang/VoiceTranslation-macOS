# Branch Naming / 分支命名规范

## Pattern
`<type>/<scope>-<short>`

## Type
- `feat`: 新功能
- `fix`: 缺陷修复
- `chore`: 工程维护（依赖、脚本、CI、文档等）
- `hotfix`: 线上紧急修复

## Rules
- `scope` 使用 kebab-case，表示模块或领域，如 `audio-capture`、`subtitle`、`ci`。
- `short` 使用 kebab-case，简短描述改动目的，建议 2-6 个词。
- 全部小写，避免空格、下划线、中文和无意义编号。
- 一个分支聚焦一个主题，避免把无关改动塞进同一分支。

## Examples
- `feat/subtitle-adjustable-font-size`
- `feat/translation-add-auto-detect`
- `fix/audio-capture-device-switch-crash`
- `fix/ui-settings-panel-overlap`
- `chore/ci-cache-swiftpm`
- `chore/docs-update-contributing`
- `hotfix/translation-null-pointer-crash`
