# mobile-ui-consistency Specification

## Purpose

确保单聊、群聊、BOT 对话及新增二级页面在审批/澄清交互、输入栏折叠、模型选择、抽屉导航、页面布局和双语本地化方面保持一致且无缺陷的移动端体验。

## Requirements

### Requirement: 三端审批与澄清交互保持一致且不暴露协议原始载荷
单聊、群聊与 BOT 对话 SHALL 复用统一的审批与澄清交互组件；结构化问答解析成功后 SHALL 不再展示原始 JSON 字符串；审批交互 SHALL 展示描述与命令并使用本地化按钮，且遵守服务端 `allow_permanent` 限制。

#### Scenario: BOT 收到结构化澄清问题
- **WHEN** BOT 交互事件在 `questions` 或 `question` 中提供结构化问题集合
- **THEN** 界面渲染 `StructuredInteractionCard`，且不显示原始 JSON 字符串

#### Scenario: 群聊收到审批请求
- **WHEN** 群聊收到包含 `description`、`command` 与 `choices` 的 `approval.requested` 事件
- **THEN** 界面展示审批描述与命令，并渲染本地化按钮（拒绝 / 仅允许本次），而非原始 `'once'`/`'deny'` 文本

#### Scenario: 自由回答提交后重置输入
- **WHEN** 用户在任意聊天类型的自由澄清卡片中提交文本
- **THEN** 回答按该会话对应通道提交且输入框自动清空

### Requirement: 三端输入栏折叠、停止与模型选择交互一致
当单聊、群聊或 BOT 存在待处理审批/澄清时，底部输入栏 SHALL 保持展开不折叠；模型选择弹窗 SHALL 对不可修改的模式和运行中状态提供一致的禁用与提示反馈，且错误提示 SHALL 支持完整中英文翻译。

#### Scenario: 群聊或 BOT 存在待处理交互时向上浏览历史
- **WHEN** 群聊或 BOT 存在未处理交互且用户向上滚动消息列表
- **THEN** 底部输入栏保持展开，不进入折叠态

#### Scenario: 单聊已有会话打开模型选择器
- **WHEN** 单聊已有 `sessionId` 且用户打开模型选择弹窗
- **THEN** 模式切换 `ChoiceChip` 处于禁用态；仅支持单一模式的 Agent 不展示“模式不可修改”提示

#### Scenario: 英文模式下 BOT 模型保存失败
- **WHEN** 英文界面中修改 BOT 模型返回 409/403/500 错误
- **THEN** 输入栏内联错误显示对应的英文提示，不混入未翻译中文

### Requirement: 抽屉导航、二级页面排版与双语覆盖一致
会话抽屉在四 Tab 切换时顶部搜索栏高度 SHALL 保持稳定且重开抽屉时回显已生效的搜索词；协作表单新增阶段 SHALL 不越界崩溃；所有抽屉与新增二级页面 SHALL 遵循一致的宽度、安全区、边距、错误着色与完整中英文翻译。

#### Scenario: 协作表单最后阶段选择分组 12 后继续添加阶段
- **WHEN** 用户在 `PersonFlowForm` 将最后阶段分组设为最大允许值后点击“添加阶段”
- **THEN** 新阶段分组被限制在合法范围内，页面正常渲染且无断言异常

#### Scenario: 重开会话抽屉与切换 Tab
- **WHEN** 用户在单聊输入搜索词后关闭并重新打开抽屉，或在单聊/群聊/BOT/历史间切换 Tab
- **THEN** 搜索框回显当前单聊搜索词，且 `TabBar` 垂直位置不发生跳动

#### Scenario: 英文界面查看各新增页面与聊天控件
- **WHEN** 应用语言切换为英文并打开群聊输入栏、BOT 对话、任务中心、消息选择与抽屉
- **THEN** 所有新增静态 UI 文案均命中 `l10n_catalog.dart` 英文映射，无裸露中文
