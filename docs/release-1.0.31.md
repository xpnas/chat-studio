# 1.0.31（32）群聊与多语言体验修复

- 单聊、群聊、历史页面的固定界面文案接入语言切换，动态的 Agent 名称、模型名和服务端内容保持原样。
- 修复群聊结构化 `@Agent` mention 使用成员记录 ID 的问题，改为发送服务端要求的 room `agentId`，同时覆盖 `@all`。
- 群聊流式回复在首个文本 delta 到达前即可显示对应 Agent 的头像和名称；思考/工具空行不会抢占正文的头像标题区域。
- 统一 `/` 命令消息的视觉入口，使用 slash 标识和独立的命令标题，同时继续使用与 AI 正文一致的 Markdown 渲染。

## 验证

- Flutter tests：311 项通过，11 项按环境默认跳过。
- `flutter analyze --no-pub --fatal-infos` 通过。
- 已完成 Android release 构建；未连接真实 Android/iOS 设备与最新服务端进行联调。
