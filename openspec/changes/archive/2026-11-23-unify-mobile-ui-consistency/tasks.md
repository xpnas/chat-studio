## 1. 修复 P0 级交互与崩溃缺陷

- [x] 1.1 新增共享交互卡片 `lib/ui/widgets/chat_interaction_card.dart`，替换单聊、群聊与 BOT 各自维护的审批/澄清卡片：统一解析 `questions` / `question` 且解析成功后不打印原始 JSON；审批统一读取 `description` / `command` 并使用本地化按钮（拒绝 / 仅允许本次 / 条件永久允许确认弹窗）；自由回答提交后清空输入并补齐图标与 `tooltip`。
- [x] 1.2 修复 `PersonFlowForm` 新增阶段分组越界崩溃（限制最大分组索引为 `12`），统一协作表单、确认弹窗与详情页的 1-based 分组序号展示并补齐移除阶段按钮 `tooltip`。

## 2. 统一三端聊天核心交互（P1）

- [x] 2.1 修复 `ChatComposer` 折叠判断，补齐群聊与 BOT 待处理交互时的防折叠逻辑，并统一运行中次级停止按钮的 `canContinue` 校验。
- [x] 2.2 完善 `ChatComposer` 与 `ModelSheet` 模型选择体验：单聊已有会话禁用模式 `ChoiceChip` 且单模式 Agent 不展示多余提示；打开单聊弹窗后运行态变化时展示提示并禁用选择；已选可覆盖协议的模型展示轻提示；对 BOT 改模型报错经 `context.tr(...)` 翻译。
- [x] 2.3 统一 `ConversationDrawer` 与 `HistoryBrowser`：重开抽屉回显 `c.search`；四 Tab 保留稳定搜索栏高度并在群聊/历史置灰提示，消除 TabBar 跳动；群聊 Tab 明确按钮语义为新建单聊；清理 `_historyTab == 3` 死分支并统一 `HistoryBrowser` 标题样式与间距。

## 3. 收敛导航、二级页面视觉规范与国际化（P2）

- [x] 3.1 统一三端 AppBar、抽屉与空态/错误条：`_PersonActivityDrawer` 使用全宽、`WorkspaceDrawer` 补齐关闭按钮；`PersonScreen` 统一 AppBar 标题/间距/圆角刷新图标、空态居中覆盖与 `ErrorNotice` 错误样式；`GroupChatScreen` 预计算 `findChildIndexCallback` 索引 Map。
- [x] 3.2 统一 `SessionTasksScreen`、`MessageSelectionScreen`、`PersonFlowScreen`、`PersonTaskScreen` 与 `PersonFlowForm` 的基础排版（`SafeArea`、边距、表单间距、错误色、刷新按钮 `tooltip` 与圆角图标、任务时间格式化与 `PersonTaskScreen` 状态本地化）。
- [x] 3.3 补全国际化覆盖：为 `ChatComposer` 群聊占位符加上 `context.tr(...)`，统一 BOT 分页按钮为 `'加载更早消息'`，并在 `lib/l10n_catalog.dart` 补全全部缺失词条。

## 4. 回归与专项一致性测试

- [x] 4.1 更新已有断言并新增 `test/ui_consistency_audit_test.dart`，覆盖 P0/P1/P2 全部修复项与英文模式本地化校验。
- [x] 4.2 运行全量 `flutter test` 与 `flutter analyze`，确保全部通过且零静态分析问题，更新任务完成状态。
