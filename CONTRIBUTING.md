# 贡献指南

## 设计理念
- **简单优先**：优先使用简单的方案解决问题
- **不重复造轮子**：优先使用已有库
- **零配置可用**：尽量避免增加新的设置项 直接使用最受欢迎的设置项
- **功能克制**：在增加新功能之前必须经过严谨的论证 避免软件功能过于复杂

## Issues
1. 提供详细内容 比如截图、日志信息
2. 避免重复提交 在提交之前请检查所有 Issues 内容
3. 请勿将 Issues 和 Discussions 混用
4. 请在问题得到解决之后自行关闭 Issue
5. 如果长期无法取得有效沟通，维护者可能会关闭 Issue

## Pull Request
1. **大改动先在 Issues 论证**
2. 一个 PR 只办一件事
3. PR 的 Commit message 格式应与项目保持一致 详见[Commit Message](#commit-message)

## Commit Message
统一使用以下格式，仅使用英语：

```text
<Type>(<scope>): <Description>
```
例如：
`Fix(logger): Mask the private info`

## AI 使用准则
本项目对 AI 辅助贡献持谨慎态度，你必须对 AI 生成的结果负责。
仅在修复明确、可复现的 Bug 时允许使用 AI。
使用 AI 的贡献者必须能逐行检查并解释 AI 生成的每一处改动。

核心协议实现（`lib/api/`）不接受 AI 的改动！
维护者可以要求修改或关闭不符合准则的 PR。
