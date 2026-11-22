## Context

基于 2026-11-22 对当前未提交代码的 UI 交互一致性审查，单聊（`HomeScreen`）、群聊（`GroupChatScreen`）与 BOT（`PersonScreen`）已经共享了 `ChatReadingState`、`ChatReadingLayout`、`ChatHistoryList`、`ChatComposer` 和 `ConversationDrawer`，但各端各自维护的交互卡片、模型弹窗、抽屉细节与 Phase B/C 二级页存在明显的行为与视觉漂移。

## Goals / Non-Goals

**Goals:**
- 消除全部已发现的 P0 崩溃/渲染缺陷、P1 三端核心交互不一致与 P2 布局/视觉/国际化割裂。
- 保持既有协议隔离边界（单聊/群聊/BOT 的发送、停止、审批/澄清、模型写入互不串用）与所有已有测试契约稳定。

**Non-Goals:**
- 不改动上游服务端协议，不新增 BOT 语音 STT 或 BOT 消息多选删除（仍按既有规格隔离）。
- 不重做 `HomeScreen` / `GroupChatScreen` 的核心视觉风格，仅向既有成熟规范对齐。

## Decisions

### 1. 共用交互卡片 `ChatInteractionCard`
- 新增 [chat_interaction_card.dart](file:///e:/code/ekko-app/lib/ui/widgets/chat_interaction_card.dart)，由单聊、群聊与 BOT 复用：
  - 统一使用 `secondaryContainer`、`borderRadius: 16`、统一内边距与标题风格。
  - 结构化问题统一按 `StructuredQuestionSet.parse(data['questions']) ?? StructuredQuestionSet.parse(data['question'])` 解析；解析成功后**不再**额外打印原始 `question` 字符串。
  - 审批请求统一读取 `description`（回退 `question`）与 `command`（等宽字体展示）；统一使用 `OutlinedButton('拒绝')` + `FilledButton('仅允许本次')`，并在 `choices.contains('always') && data['allow_permanent'] == true` 时提供带二次确认弹窗的 `OutlinedButton('永久允许')`；对于 `choices` 为空的审批（如持久 BOT 审批），默认提供拒绝与仅允许本次且严禁永久授权。
  - 自由澄清统一展示带间距的 `ActionChip` 选项与带 `Icons.send_rounded` + `tooltip` 的输入框，提交后清空输入框。
  - 保留各端独立的状态参数（`enabled`、`submitting`、`error`、`onSync`、`maxHeight`、`showLinearProgress`）。

### 2. 输入栏折叠与模型选择器一致性
- `ChatComposer` 折叠判断补齐 `group?.timeline.interaction == null` 与 `person == null || (person!.live.interaction == null && person!.interactions.isEmpty)`，确保三端存在待处理审批/澄清时输入栏均不折叠。
- 运行态次级停止按钮与主停止按钮共用同一 `canStop` 条件（含 `c.current?.canContinue != false`）。
- 单聊模型弹窗：
  - 仅在 `c.agentModes.length > 1` 或已存在会话且支持多模式时展示模式切换提示；`c.sessionId != null` 时禁用 `ChoiceChip`（`onSelected: null`），避免点击后提示被弹窗遮挡。
  - 打开弹窗后若 `!c.canConfigure`，与 `PersonModelPicker` 一致展示等待提示并用 `AbsorbPointer` 禁用列表点选。
  - 对可覆盖协议的已选模型在 `ModelSheet` 副标题中附带轻提示（`点击可切换 API 协议`），提升可发现性。
  - BOT 改模型报错写入 `_inlineError` 后经 `context.tr(...)` 渲染，使英文环境正确翻译。

### 3. 会话抽屉、AppBar 与右侧抽屉统一
- `ConversationDrawer` 初始化 `_search.text = c.search`，避免重开抽屉时输入框与当前过滤条件失步。
- 顶部搜索框在 4 个 Tab 均保持稳定占位高度：单聊与 BOT 启用搜索，群聊与历史置灰禁用并展示对应提示（`'群聊列表不支持搜索'` / `'历史记录暂不支持搜索'`），彻底消除切换 Tab 时的 TabBar 跳动；同步清理 `_historyTab == 3` 的死分支。
- 顶部“新建对话”按钮在单聊/历史创建单聊，在 BOT 创建 BOT，在群聊展示明确禁用的提示态或仅在可新建 Tab 保持一致语义（保持 `new-conversation-button` 位置和既有测试兼容，群聊 Tab 下仍点击创建普通对话时需文案明确或保持原有单聊新建能力，这里在群聊 Tab 将按钮文案明确为 `'新建单聊'` 避免误解为新建群聊，单聊/BOT/历史保留 `'新建对话'`）。
- `_PersonActivityDrawer` 统一使用全屏宽度 `MediaQuery.sizeOf(context).width`；`WorkspaceDrawer` 补齐右上角关闭按钮（`Icons.close_rounded`）。
- `PersonScreen` AppBar 补齐 `titleSpacing: 0`、统一 16px `w600` 标题样式与 BOT 图标、使用 `Icons.refresh_rounded`、补齐尾部 `SizedBox(width: 6)`；空状态改为与 `GroupChatScreen` 一致的居中覆盖层，不再受 `reverse: true` 影响停靠左下角；主错误条改用 `ErrorNotice` / 错误色样式。
- `GroupChatScreen` 预计算 `indices` Map 供 `findChildIndexCallback` 复用。

### 4. 二级页面排版规范与国际化补齐
- `PersonFlowForm` 新增阶段分组使用 `math.min(stages.last.group + 1, 12)`，表单和详情/确认弹窗统一使用 1-based 分组展示（底层仍提交 0-based `group_position`）。
- `SessionTasksScreen`、`MessageSelectionScreen`、`PersonFlowScreen`、`PersonTaskScreen`、`PersonFlowForm` 补齐 `SafeArea`、统一外边距与组件间距、错误文本使用 `colorScheme.error`、刷新/删除按钮补齐 `tooltip` 与圆角图标；任务时间戳格式化为 `YYYY-MM-DD HH:mm`；`PersonTaskScreen` 所有状态经 `personStateLabel` 翻译。
- 补全 `ChatComposer` 群聊占位符的 `context.tr(...)`，统一 BOT 分页按钮为 `'加载更早消息'`，并补全 `lib/l10n_catalog.dart` 全部缺失英文映射。
