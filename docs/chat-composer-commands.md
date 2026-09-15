# 聊天页与斜杠命令调整

## 交互

- 顶部显示当前聊天名称（空白聊天显示「新对话」），单行省略；保留记录入口和新建按钮。
- 模型选择与附件、思考深度、语音、发送位于输入框底部同一行。沿用提供商分组、当前模型优先、搜索与服务端模型写入，不修改运行中的模型。
- 输入框首字输入 `/` 时在输入框上方悬浮显示候选（不再设置独立命令按钮）；只在输入开头、光标前尚无空格/换行且不在 IME 合成中触发。
- 支持命令前缀/中文描述过滤、点击补全、↑↓ 选择、Enter/Tab 补全、Esc 关闭。选择只填写草稿，必须点击发送才执行。
- 命令列表限高并可滚动。技能/Bundle 选择器按当前 Profile 加载，失败可重试；Bundle 创建使用官方 REST，而不是发送不被服务端支持的 `/bundles create` 文本。
- 模型/技能选择期间切换聊天或 Profile，旧面板结果不会覆盖新聊天的草稿/模型。

## 官方一致性基线

对照本项目已锁定的官方 Studio **v1.0.3**，commit `b44c74318fe5a0a1f3aed29d5095393964fc3d62`：

- `packages/client/src/utils/hermes/bridge-session-commands.ts`：29 个候选（含子命令）及 `reload_skills` 别名。
- `packages/client/src/components/hermes/chat/ChatInput.vue`：输入触发、过滤、补全，以及 coding-agent 候选限制。
- `packages/client/src/stores/hermes/chat.ts`：原文 `run` 发送、Hermes command 展示、`session.command` 回执。
- `packages/server/src/modules/studio/services/chat-run/session-command.ts`：命令解析、清屏/历史清理、改名、fork、终止标记。
- `packages/client/src/api/hermes/skills.ts`、`skill-bundles.ts`：技能与 Bundle 的 Profile 查询和创建契约。

Hermes 提示完整命令列表；Ekko/Codex 与官方 coding-agent 聊天一致，只提示 `/usage`、`/context`、`/status`、`/compact`。未识别的 `/xxx` 不在 App 中擅自解释，继续沿用原有普通输入协议。App 不实现另一套命令执行器，始终由服务端/对应 runtime 决定实际行为。

运行中 Hermes 命令可走同一 `run` 通道（例如 `/abort`、`/steer`、`/queue`），普通消息仍保留原 App 的运行中禁发限制；此时不允许携带附件，避免 content blocks 使服务端绕过字符串命令解析。独立停止入口保留。

## 回执与安全边界

- 命令消息单独标为「命令」，不伪装成 AI 回答；历史中的 `command` 角色也显示。
- `session.command` 的 started/terminal 控制运行状态；无 terminal 的查询/改名不会凭空建立一个永不结束的运行。
- `/clear` 成功仅清显示，不调用删除会话；`/clear --history` 由服务端删除历史，App 保留结果提示。失败回执不清除消息。
- `/title` 更新所属聊天的标题；后台回执不修改当前其他聊天。fork 只有当前聊天发起的回执才能自动切换。
- 不自动重发命令；离线禁发。命令描述明确显示 YOLO 跳过危险审批以及历史删除的语义，不额外绕过服务端权限。

## 验证与限制

新增单元/Widget 测试覆盖命令目录、别名、原文发送、运行中控制、终止回执、清屏失败、跨会话改名、Profile REST、技能选择、模型弹层竞态、键盘补全及 320px 小屏。

本次已通过隔离官方服务端的真实 HTTP/Socket.IO 联调，验证 usage/context/title/clear/history-clear 回执及技能/Bundle 目录，并完成本地 mock/Widget 回归；未对完整 Hermes/Codex runtime 逐条执行命令。服务端版本和 runtime 能力会影响实际结果。Bundle 管理器的删除功能、Web 端完整队列管理与命令结果的专用可视化卡片不在本次范围内；App 显示服务端返回的命令文本。后续升级官方版本应同步检查命令目录与回执契约。
