## Why

当前客户端的协议测试仍锁定 2026-09-10 的上游提交，Agent 选择受八项白名单限制，Coding Agent 请求固定使用 scoped 模式，跨设备状态、跨轮任务和 BOT 协作尚未形成完整移动端体验。升级到 Ekko Studio v0.8.21 后，用户需要在手机上接续 Web 会话、管理任务与消息，并使用已配置 BOT 完成协作、处理人工交互及回看完整结果。

## What Changes

- 建立旧基线与 v0.8.21 的固定提交兼容测试矩阵；新增接口按能力探测，明确区分接口不支持、鉴权失败和暂时不可用。
- 将 Agent 选择改为服务端描述与安装状态驱动；稳定版通过受版本控制的协议元数据兼容现有 availability 接口，新版支持统一 Agent 描述和合法插件 Agent ID。
- 增加 scoped/global 模式、原生模型目录和模型对应的思考强度；会话恢复与发送保留原 Agent、模式、模型、Provider 和 API 模式。
- 接入统一会话运行状态、未读状态和已读回执；同步远端删除/归档，恢复时保护草稿、历史阅读位置和现有防重复发送行为。
- 增加会话及跨会话任务中心：筛选、完成/重开/关闭、请求与证据定位，和单次运行中的 task plan 明确区分。
- 增加受服务端分组与历史版本约束的单聊/群聊消息多选删除，刷新关联任务和阅读窗口。
- 接入已配置 BOT 的列表、对话、任务进展、审批/澄清、结果附件和追问；模型与执行资源沿用服务端 BOT 配置。
- 支持选择既有 BOT 发起顺序/并行协作、有限轮次、停止/恢复，并提供阶段结果、执行详情、统一消息/协作卡片分页及版本化缓存恢复。
- 分三阶段实施到 BOT 协作完整验收；后台系统通知、BOT 配置编辑、调度管理与工作流画布保留为后续独立变更。

本变更保持旧服务端的核心聊天可用；不要求用户升级到尚未发布的主分支才能使用第一批功能。

用户于 2026-11-13 批准本次最终验收使用本地受控模型驱动真实 Studio 闭环，并明确记录真实模型未验证；移动平台仅要求本地 Android 验收，iOS 免测且不宣称通过。

## Capabilities

### New Capabilities

- `studio-compatibility`: 固定上游兼容矩阵、能力协商、失败语义与回归验收。
- `agent-discovery`: Agent 身份、可用性、模式和能力的规范化与选择。
- `agent-model-selection`: 会话启动模式、原生/Provider 模型选择、偏好隔离和准确续聊。
- `cross-device-session-sync`: 会话状态快照、增量更新、已读回执、远端移除及阅读状态保护。
- `session-task-tracking`: 跨轮任务列表、状态管理、来源与证据定位及远端变更刷新。
- `message-selection`: 单聊/群聊消息分组选择、保护边界、版本冲突和删除后联动。
- `bot-conversations`: 既有 BOT 的身份、聊天、持久交互、后台任务结果与追问。
- `bot-collaboration-history`: 多 BOT 协作发起与控制、阶段详情、统一时间线和缓存恢复。

### Modified Capabilities

无。当前 `openspec/specs` 尚无能力规格；上述规格记录本次新增和增强后的行为，不表示项目此前没有相关实现。

## Impact

- Flutter 数据与状态：`lib/data/agent_catalog.dart`、`models.dart`、`studio_api.dart`、`chat_transport.dart`、`app_storage.dart`、`lib/state/app_controller.dart`、`conversation_state.dart`、`chat_timeline.dart`。
- 界面：Agent/模型选择器、聊天输入栏、会话抽屉和状态标记、任务中心、单聊/群聊选择模式、BOT 列表、协作发起表单和详情，以及中英文文案；不增加群聊 Agent 配置编辑。
- 新增领域适配：会话任务、消息选择、Person 主会话/后台任务/协作模型与接口、统一时间线及有界原子缓存；BOT 使用账号所有权和服务端资源权限，不直接复用普通会话的 Profile 过滤。
- 验证：现有 Agent、模型、恢复、多会话、协议和真实服务端测试；`scripts/studio-contract.*`、`.github/workflows/studio-contract.yml` 与隔离 mock-provider 启动链。
- 正式兼容目标：旧提交 `b44c74318fe5a0a1f3aed29d5095393964fc3d62`，稳定版 v0.8.21 对应提交 `312425cca7d707a115d230f0252e9d55786ec57e`。插件描述增强另以观察到的主分支提交 `302cf39b7cc77410430694eebfb79dc8aff11b97` 验证，不能替代稳定版验收。
- 文档更新：兼容版本、Agent 支持、模式选择、任务管理、消息删除影响和 BOT 协作说明；不修改上游服务端，不引入模型密钥本地保存，不实现插件安装中心或平台推送。
