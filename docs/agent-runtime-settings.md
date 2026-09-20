# Agent 设置与聊天上下文

## 源码对照

本次对照 `D:/code/hermes-studio`，提交 `b6293a11d9d03c71d191ce4227f7db8730506fb8`，不再以旧版本目录推断新功能。

- `packages/client/src/views/hermes/HermesSettingsView.vue` 及 `components/hermes/settings/{AgentSettings,MemorySettings,SessionSettings,GatewayAutoStartSettings}.vue`
- `packages/client/src/components/layout/VersionManagementModal.vue`、`api/hermes/runtime-versions.ts`
- `packages/client/src/views/ekko/SettingsView.vue`、`api/ekko/config.ts`
- `packages/client/src/components/hermes/chat/ChatInput.vue`
- `packages/server/src/modules/hermes/controllers/config.ts`、`routes/runtime-versions.ts`
- `packages/server/src/modules/studio/sockets/chat-run.ts`、`services/chat-run/usage.ts`

## 移动端入口与布局

「管理 → Agent」点击 Hermes Runtime 或 Ekko Agent。入口遵循当前管理员权限；服务器仍负责最终鉴权。

- **Hermes**：运行、记忆、会话、网关四组设置；运行页进入独立的 Runtime 版本管理。
- **Ekko Agent**：运行、模型、工具、模块、高级五组，覆盖 Web 可见的 32 个设置字段。
- 全屏原生 Flutter 设置页、横向分组标签、统一主题圆角卡片。数值、枚举、多选采用与 App 其他设置一致的底部弹层；长内容滚动，小屏/大字体不挤压横向表单。
- 修改先保留为本地草稿，显式保存；离开/刷新前确认放弃未保存内容。请求失败保留草稿，刷新只更新本页数据，不重新加载整个管理页面。

## Hermes 设置

`GET /api/hermes/config?sections=...` 读取当前 Profile；`PUT /api/hermes/config` 仅提交修改的 section 和字段，携带 `X-Hermes-Profile`、`restart: false`。

- 运行：最大轮次、网关超时、重启等待、工具使用策略。
- 记忆：记忆与用户画像开关、各自字符上限。
- 会话：工具审批、记忆/技能写入审批、空闲/每日重置策略与时间。关闭工具审批需要确认。
- 网关：自动启动、全局管理方式（仅 default Profile 可修改）、包含/排除 Profile。候选项来自服务端。`include: []` 表示不启动任何 Profile，`include: null` 表示全部模式；切换包含模式会清空排除项，保持 Web 语义。
- 多个 section 保存不是服务器事务。前面的 section 已成功、后面的失败时，只重试仍未保存的 section，不假装整体回滚。
- `restart: false` 不代表所有设置绝对没有即时影响：服务端对网关管理方式变更可执行自己的协调逻辑。App 不额外发送重启请求。
- Web 浏览器的「显示最近会话」「只看人类消息」是浏览器本地偏好，不作为 Hermes 服务配置写入；App 历史入口沿用自己的交互。

## Runtime 管理

接口为 `/api/hermes/runtime-versions` 及其 jobs、download、active-runtime、runtime-root、restart-webui 子路由。

- 已安装版本按**服务器平台**过滤；显示远程可下载版本、当前 Agent/Runtime 版本、运行来源、路径及 CLI 详情。
- 支持 GitHub / Cloudflare 下载源、指定版本下载、进度与阶段、失败信息、切换版本、删除非当前版本。
- 运行目录是**服务器绝对路径**，不是手机目录。迁移与恢复默认目录、删除、激活、重启均需明确操作；下载完成不会自动重启服务器。
- 仅有未完成任务时轮询；App 后台或页面关闭停止轮询，网络失败停止并等待手动刷新。检查更新/轮询保留现有内容与阅读位置。
- 当前版本不可删除；迁移、激活、校验、远程目录读取失败分别呈现。
- 用户自行安装的 CLI 不冒充受管理 Runtime；CLI 自身更新仍在服务器进行。这里不管理手机 App 版本，也不提供 Web UI 安装包管理。

## Ekko Agent 设置

`GET/PUT /api/ekko/config` 保留真实服务协议名。App 包名和代码路径仍为 Chat Studio。

- 运行步数/重试/失败恢复、后台委派和子任务限制。
- 模型超时、温度、输出上限、思考深度/摘要、授权提前刷新；温度与输出上限可留空。
- 工具、审批、永久允许名单、代码执行语言/超时/输出限制。
- 记忆、技能、MCP；日志容量和自定义指令。
- 保存保留未知及隐藏字段；不覆盖 Studio 主设置管理的 compression，也不重新暴露 Web 已弃用的字段。
- 服务端返回 deferred runtime refresh 时，提示运行中的任务结束后生效。

## 输入框上下文

- 单聊已有会话时显示在输入框内部右上角。任意文字（包括空格）都会隐藏，清空后恢复；不抢占正文。
- 与 Web 一致：优先正数 `contextTokens`，否则 `inputTokens + outputTokens`；显示已用、上限、剩余及细进度条。
- 上限来自 `/api/studio/sessions/context-length`，按服务器/Profile/会话/模型隔离。接口失败显示上限未知，不编造固定容量。
- usage.updated、完成、压缩、命令回执和 resume 快照驱动更新。计数是绝对值而非累加，压缩可降低使用量；重连快照优先于旧回放。
- 新对话尚无 session 时不显示。群聊没有统一上下文窗口协议，不套用最近单聊的数字。

## 验证

```sh
flutter analyze --no-pub --fatal-infos
flutter test --no-pub
python scripts/verify-app-identity.py
```

专用测试：`context_usage_test.dart`、`agent_settings_test.dart`、`hermes_settings_test.dart`。包含故障重试、未知字段保留、权限拒绝、危险操作取消、生命周期轮询、异步会话隔离和小屏大字体。

可选原生控件预览：设置 `CHATSTUDIO_SETTINGS_PREVIEW_FONT` 为本地可读的中文字体路径，运行 `flutter test test/agent_settings_preview_test.dart`。图片输出到 `.local/settings-previews/`，只是可重复的 Widget 渲染图，不是手机或真实服务器截图；字体不随代码分发。

本轮不自动下载/切换/重启用户的真实服务器。真实服务端安装、迁移和重启的运维结果，需要在目标测试环境另行验证。
