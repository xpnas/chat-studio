## Why

当前工作区已合入上游 Studio v0.8.21 核心同步与 `1.0.39`–`1.0.44` 的三端（单聊 / 群聊 / BOT）聊天阅读体验统一，但在交互细节审核中发现多处跨页面不一致与 P0 级缺陷：BOT 交互卡片会在结构化问答上方直接渲染原始 JSON 且遗漏 `questions` 字段；群聊审批卡片读取了错误字段且裸露协议枚举值；协作表单在分组 `12` 下新增阶段会触发越界崩溃；折叠输入栏、模型选择器、会话抽屉、右侧面板、二级页面布局及英文词典均存在不同程度的割裂。

## What Changes

- 抽出共享审批/澄清交互卡片，在单聊、群聊、BOT 三端统一结构化问题解析、审批描述/命令展示、本地化按钮、永久授权确认及自由回答提交清空行为。
- 修复 `PersonFlowForm` 新增阶段分组越界崩溃，并统一协作表单与详情页的分组序号展示与无障碍提示。
- 统一 `ChatComposer` 在三端待处理交互时的折叠保护、运行态次级停止按钮守卫、单聊模式芯片只读态与运行态模型锁定提示、API 协议覆盖可见提示，以及 BOT 改模型报错的国际化。
- 统一 `ConversationDrawer` 四 Tab 顶部搜索区高度与禁用提示、单聊搜索词回显、新建按钮与清理死分支，统一 `HistoryBrowser` 标题样式。
- 统一 AppBar、抽屉宽度/关闭按钮、错误与空状态排版、`GroupChatScreen` 索引缓存，补齐 Phase B/C 二级页面（任务中心、消息选择、协作详情/表单、BOT 任务详情）的 `SafeArea`、内边距、错误着色、状态本地化与时间格式。
- 补全硬编码中文的 `context.tr(...)` 包裹及 `lib/l10n_catalog.dart` 全部缺失词条，并新增回归与专项 UI 一致性组件测试。

## Capabilities

### New Capabilities

- `mobile-ui-consistency`: 规范单聊、群聊、BOT 及新增二级页面在交互卡片、输入栏、抽屉、模型选择、布局规范与双语文案上的一致性行为。

### Modified Capabilities

- 无（不修改既有服务端协议契约与资源隔离边界）。

## Impact

- 共享组件：`lib/ui/widgets/chat_interaction_card.dart`（新增）、`chat_composer.dart`、`conversation_drawer.dart`、`history_browser.dart`、`workspace_drawer.dart`、`model_sheet.dart`。
- 页面：`lib/ui/home_screen.dart`、`group_chat_screen.dart`、`person_screens.dart`、`session_tasks_screen.dart`、`message_selection_screen.dart`。
- 本地化与测试：`lib/l10n_catalog.dart`、`test/person_widgets_test.dart`、`test/ui_consistency_audit_test.dart`（新增）。
