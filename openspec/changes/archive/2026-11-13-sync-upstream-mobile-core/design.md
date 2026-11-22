## Context

动机与范围见 [proposal.md](proposal.md)。分析日期为 2026-11-13，客户端基于 `c8c6c35`；工作区另有结构化问答相关未提交改动，本变更不负责改写或清理这些改动。

已核对的实现事实：

| 位置 | 当前行为 | 设计影响 |
| --- | --- | --- |
| `lib/data/agent_catalog.dart` | 八项 supportedIds、仅简单 ID、名字图标静态映射 | 描述与路由需统一规范化，不能只放宽正则 |
| `lib/state/app_controller.dart` | availability 获取安装状态，Coding Agent 固定 scoped | 模式必须进入会话状态与发送路径 |
| `lib/data/models.dart` | Conversation 不读取 agent_mode/api_mode；ModelChoice 只有 Provider 分组数据 | 增加模式与原生模型语义，不能把 native ID 当 Provider 模型 |
| `lib/data/app_storage.dart` | 选择偏好按 scope 保存，未按 Agent 和模式区分 | 版本化偏好键并迁移旧选择 |
| `lib/data/chat_transport.dart` | 独立 WebSocket、无 ACK 抽象、离线不发送操作 | 观察连接单独抽象，保留聊天传输的防重放约束 |
| `lib/state/app_controller.dart`、`conversation_state.dart` | 本地维护运行状态、草稿和阅读偏移；前台 resume | 列表状态与会话正文恢复分离，保护已有状态 |
| `scripts/studio-contract.*`、CI | 硬编码旧 SHA、依赖旧上游测试路径 | 建立矩阵和针对各基线的启动配置 |

核对上游的关键协议（均为源码观察，不代表已经联调通过）：

- v0.8.21 的 `config/agents.json` 提供 16 个 Agent 的元数据，availability 提供安装状态；`GET /api/coding-agents/models?agent=...&refresh=...` 返回 native 模型及独立状态。
- v0.8.21 会话使用 `agent_mode`、`model`、`provider`、`api_mode`、`reasoning_effort`；发送使用 `mode`，Global 模型选择允许空 model 表示原生默认。
- v0.8.21 `/chat-run` 握手 `query.session_state='1'` 启用 `sessions.state.snapshot/updated`、`sessions.state.request` 和带 ACK 的 `sessions.read`。
- 状态字段为 sessionId/profile/working/backgroundPending/lastMessageId/readMessageId/lastAttentionId/readAttentionId/unread；没有全局 revision 或失败原因。不得自行假定存在这些字段。
- `app.events.subscribe` 支持 `schema_version:1` 和 `include_session_removals:true`，通过 `app.event` 发出 `chat.session.removed`。对外 envelope 不包含删除/归档 reason，因此事件只能触发重新核实。
- `GET /api/studio/agents` 及 `/:id/models` 是稳定版之后的增强；描述含 modes/surfaces/actions/status，并不直接等同于 context/compact 能力。
- v0.8.21 已无 CI 当前引用的 `tests/server/app-connections-auth.test.ts`、`user-auth.test.ts`；不能在新版运行不存在的测试，也不能将无测试执行视为通过。

## Goals / Non-Goals

**Goals:**

- 第一批形成可独立发布的核心聊天增强：发现、选择、准确续聊和跨设备对账。
- 将任务中心、消息整理、BOT 对话及完整协作纳入同一变更的后续实施阶段；核心阶段可以单独发布，但不代表整个变更完成。
- 以 v0.8.21 验收，旧基线继续覆盖原有聊天；插件增强使用独立固定预览提交验证。
- 新能力按实际资源边界隔离：普通聊天使用服务器/账号/Profile，Person 使用服务器/账号/BOT 所有权并核验执行资源权限；所有请求过滤过期世代，维持草稿、分页和流式恢复约束。

**Non-Goals:**

- 不实现 BOT 创建/配置编辑、长期记忆编辑、定时调度、后台系统通知和插件安装界面。首版使用已有 BOT，提供协作表单而不建设工作流画布；不新增后台任务高级配置或队列插队/移除编辑器。
- 不增加群聊 Agent 编排/配置编辑，不改变工作流和 global_agent 来源会话的原有限制。`source:global_agent` 与 Coding Agent 的 `agent_mode:global` 是不同概念。
- 不复制上游 UI、品牌素材或服务端运行时；仅依据协议独立实现。第一批不接入外部网站 Agent JSON 下载链。

## Decisions

### 1. 固定兼容矩阵，按接口能力而非版本号选择路径

| 档位 | 固定 commit | 必须验证 |
| --- | --- | --- |
| legacy | `b44c74318fe5a0a1f3aed29d5095393964fc3d62` | 已有登录、Profile、聊天、群聊、恢复、附件、任务计划；新接口缺失可回退 |
| stable | `312425cca7d707a115d230f0252e9d55786ec57e` | v0.8.21 核心能力、原生目录、会话模式、状态同步、任务中心、消息删除及完整 BOT 协作 |
| preview-agents | `302cf39b7cc77410430694eebfb79dc8aff11b97` | 统一 Agent 描述、插件 ID 和插件模型/聊天路由 |

新增一个受版本控制的兼容清单，供两个 runner 与 CI 读取；校验检出的真实 commit，拒绝未登记版本。旧基线名称按 SHA 识别，不依据历史版本号大小推断新旧。CI 使用新仓库名，现有 wire 值保留。

在 `lib/data` 增加协议能力适配层。能力状态区分 unknown/supported/unsupported/unavailable；只有已确认的缺失路由或显式 unsupported 才选择旧实现。401/403 维持现有身份/权限流程；500、超时、非 JSON 不缓存为不支持。普通能力缓存按服务器、账号、Profile 隔离；Person 按账号与资源权限隔离，不以普通 Profile 选择器过滤 BOT。新登录和显式刷新可重探测；Socket 能力由成功快照/ACK 确认，超时仅令当前连接降级并可重试。任务、消息编辑、BOT、统一时间线分别探测，某个资源 404 不直接认定整个接口不存在；不以写入请求探测能力。

替代方案：直接要求最新版或按版本字符串分支。前者破坏旧服务端，后者无法覆盖定制部署和主分支能力差异。

### 2. 两条发现路径归一为一个 Agent 描述

- Ekko/Hermes 始终从 availability 获取可用性，结合固定协议元数据规范化；统一描述接口只为 Coding Agent 与插件提供权威目录，不得覆盖这两个核心入口的安装状态。Coding Agent 优先读取统一描述接口，仅在该接口明确缺失时使用 availability 与固定协议元数据回退。元数据不表示已安装。
- 合法空统一目录意味着没有可选 Coding Agent/插件，不触发 Coding availability 回退；仍按 availability 呈现 Ekko/Hermes。availability 缺少核心记录时不推断已安装，任一必需读取返回鉴权、权限、格式或临时错误时显示错误并保留旧可见缓存；合并前后均校验连接身份与请求世代。
- 旧路径覆盖已核对的 16 个 Agent；未知 ID 显示通用图标与不可用原因，不猜测请求格式。新路径仅允许 schema 合法、支持 chat surface、含已理解模式且已安装的描述参与选择。
- `plugin:<plugin-id>/<agent-id>` 是独立身份类型，按上游组件约束解析，并在 REST 中整体编码为一个 path segment；不直接放宽任意斜杠路径。
- actions 只决定管理入口；context/compact 等命令能力使用已验证的额外元数据，没有声明就不启用。插件自定义设置页不在本期承诺内。
- 图标失败回退通用图标；新增资源加载不得把登录凭据附给外部地址，继承现有大小限制和重试约束，不拷贝上游品牌素材。
- Agent 在会话期间失效，保留历史身份并停止新发送，显示可恢复的原因；不把既有会话改成其他 Agent。

替代方案：只扩展八项白名单或完全信任任意服务端 ID。前者继续阻碍扩展，后者不能保证客户端理解路由和模式。

### 3. 模式、模型和偏好作为完整选择处理

新增模式值与 native 模型目录类型，并扩展 Conversation/ConversationState/ModelChoice 或等价数据结构。明确分开 scoped 的 provider/model/apiMode 与 global 的 nativeModel/nativeReasoning/default 语义。本节选择器用于普通 Agent 会话；BOT 显示服务端配置并沿用 Person 执行路径，不用普通模型选择器修改其配置。

- 现有会话从服务端元数据恢复 Agent、agent_mode、model、provider、api_mode、reasoning_effort；已保存选择优先于新建偏好，不因目录缺项而改写。
- 对旧数据，只有可证明属于历史 scoped 路径的会话才使用 scoped 默认。未知模式或不支持的来源保持可读并说明不能续聊，不向服务端发送猜测值。
- 新建会话可选择 Agent 支持的模式；已有会话模式保持只读，变更模式创建新会话，避免原生会话上下文切换。模型/思考强度更新仍遵循服务端现有接口和运行中锁定。
- Global 模型目录来自 native discovery 或统一 Agent models 接口；保留原始 ID、alias、provider 前缀及默认空选择。发送 Global 请求不混入 scoped Provider/API 模式。
- Scoped 保留固定 apiMode，处理服务端提供的每模型 api_mode_by_model；自动模式跟随服务端解析结果。仅在服务端契约允许的协议集合内提供覆盖选择。
- 原生 reasoningEfforts 来自所选模型；无声明时不编造选项。既有不可发现模型仍显示保存的 ID；刷新失败保留可见缓存，并说明其尚未重新验证。没有可用目录时仍允许服务端支持的原生默认启动。
- 新建偏好键增加 Agent 和 mode；迁移旧偏好到其明确的 Agent/scoped 槽位。切换模式、服务器、账号、Profile 时不串用模型或凭据，模型响应采用请求世代过滤。

替代方案：继续复用 Provider 下拉框与全局单份偏好，无法表达 native 默认、原生别名和不同思考强度，容易在续聊中改变模型。

### 4. 独立的轻量会话观察连接

新增 `SessionSyncTransport`（建议 `lib/data/session_sync_transport.dart`）与状态归并模块，使用独立 Socket.IO Manager/forceNew 连接 `/chat-run`，握手携带 token、profile、session_state=1。不为所有会话发送 resume，不订阅所有正文，也不经该连接执行 run/abort/approval。

- 监听 snapshots/updates，首个快照为该连接的基准；同连接按有序传输处理，旧连接回调/ACK 由世代拒绝。上游无 revision，因此不能以虚构 revision 或跨连接本地时间比较覆盖顺序。
- 列表 running/unread 以观察协议为准。观察状态只有 working 布尔值，不能据此编造 success/failure；活动会话终态、审批内容和正文仍由会话流及 resume 提供。
- 前台和重连请求一次合并的列表状态及必要的当前会话恢复。短期未知状态显示“同步中”，不凭断连判定完成；停止观察失败时保留正常聊天路径。
- `sessions.read` 只在前台、用户已到达当前最新已完成内容、无未显示 attention 项时发送。messageId 与 attentionId 来自已展示的服务端游标，ACK 失败保留未读；刷新、后台到达、阅读旧历史不自动标记已读。
- 阶段 A 仅投影到已支持的普通会话。阶段 C 对已确认账号所有权的 BOT 主会话接入状态和可验证的阅读游标，不用普通 Profile 过滤误删 BOT；私有 worker 不成为普通列表入口，不自动上报已读。状态观察不足以证明可见内容已读时，保留未读，等待正文/交互提供对应游标。

替代方案：每个会话开正文连接或不断轮询历史，增加移动端耗电并混淆阅读与通知状态；直接把 observer 快照灌入聊天 timeline 会破坏已有流式恢复。

### 5. 远端变更采用失效通知与定向核实

观察连接额外以明确的类型过滤订阅 `app.events.subscribe`，启用 `include_session_removals:true`，成功后处理 `app.event` 中的移除事件并按 id 去重。该事件不作为系统推送，也不能在没有 reason 时直接当作删除。

收到移除事件后刷新列表并定向读取已有会话详情：归档仅改变列表归属；确认删除才移除正文/活动缓存；403 作为权限变化处理。未发送草稿进入当前 scope 的可恢复本地草稿状态，不继续绑定到已删除/不可访问会话。历史清空通过会话恢复的权威消息状态核实；缺少专用事件时在重新聚焦/返回前台进行对账，不承诺后台瞬时清空同步。

列表分页、筛选缺项或 observer 空快照均不能证明会话删除；中断时先失效，恢复后查询已缓存会话中的必要项，禁止对整个历史无限扇出。

普通会话在阅读旧页时合并 live 状态而不替换阅读窗口；新内容显示待查看提示，返回底部显式加载最新页。沿用现有草稿和 scrollOffset，在 Web 清空后明确重置失效的页窗口。

替代方案：全量重建 AppController 或以列表缺失清空缓存，会丢失草稿、误删分页之外的会话并让阅读位置跳动。

### 6. 在客户端建立真实协议验收，不依赖已删除的上游测试

复用 `test/live_contract_test.dart` 和 mock-provider，针对 legacy/stable 分别配置隔离启动与认证 bootstrap；支持两条 runner。保留实际 SHA 校验、隔离数据库/工作区、端口检查和子进程清理。CI 不再对所有版本运行同一组已不存在的上游文件，第一批验收由客户端维护的协议测试承担。

基础真实联调覆盖身份、Profile、发送/恢复/停止、分页、媒体与群聊。用两个独立客户端连接同一隔离服务端验证状态、已读和移除。native CLI/OMP 缺失时，真实测试报告能力不可用；用协议固定样例与可控测试适配器验证路由，不宣称所有外部 Agent 已端到端执行。

preview-agents 使用固定提交及最小受控插件验证描述和会话路由。该验证属于本期增强的发布门槛；如果不能完成，应保持插件增强关闭并记录原因，不能用 stable 成功代替。

### 7. 跨轮任务与单次运行计划分开建模

增加会话任务模型、API 和状态容器，复用既有会话导航与分页定位；任务中心作为独立入口，会话内另提供当前目标入口。普通任务使用 `GET /api/studio/session-tasks` 和 `GET /api/studio/sessions/:id/tasks`，支持 search/status/order/offset/limit 以及当前或全部授权 Profile。列表保存来源会话、Profile、source_message_id、evidence_message_id 与 updated_at；禁止从单次 task plan 推导跨轮目标。

人工状态操作使用 `PATCH /api/studio/sessions/:id/tasks/:taskId/status`，仅提交 status 和 **expected_updated_at**，不是列表 revision；成功使用返回快照。409 刷新后由用户重新选择，401/403 进入原身份流程。不要调用面向 Agent 的 `/session-tasks/list|update`，它们需要运行上下文，不能拿客户端身份模拟。

来源/证据定位采用有界逐页查找并保留返回任务中心的筛选状态，取消或目标不可见时明确反馈，不无限扫描或以相邻消息替代。视图聚焦、前台恢复和删除成功刷新任务；无需为了实时刷新订阅所有会话正文。Person 后台任务有独立 execution/revision/queue 语义，通过 BOT 任务入口呈现，不与普通目标状态操作混用。

### 8. 消息删除以服务端分组及版本为准

单聊使用 `GET /api/studio/sessions/:id/message-selection` 和 `POST /api/studio/sessions/:id/messages/batch-delete`；群聊使用 `/api/studio/group-chat/rooms/:roomId/message-selection`、`/messages/delete`。单聊 ID/historyRevision 是数值，群聊 ID 和 historyRevision 是字符串（版本为不透明摘要），分别建类型，不共用整数转换。

单聊服务端目前限制 source 为 cli/api_server/desktop/builtin_agent 且 Agent 为 Hermes 或内置 Ekko；不能对所有 Coding Agent 一律启用。BOT 页首版不提供消息多选删除，避免在消息/flow 混合历史上复用普通选择器。进入选择模式先获取全量身份分组；run 可能包含跨页或不可见消息，确认展示分组数、记录数及影响范围。禁止选中 compressed/summarized/unknown-boundary 组；运行、队列、压缩或交接中的拒绝以服务器为准。

删除提交 `{messageIds, historyRevision}`，先显示用户确认。409 使旧选择失效并重新加载，不自动带新版本重试。提交后断线只读对账；不自动重放删除。成功后刷新消息、task plans、任务与结果引用，保留草稿并选择有效阅读锚点。

上游明确会删除 source_message_id 命中的跨轮任务，并将 evidence_message_id 命中的任务重置为 open、清空完成证据；这是必须呈现的联动，不将任务证据一概称为受保护记录。客户端不自行维护第二套删除级联规则，使用服务端快照对账。

### 9. BOT 是账号拥有的会话类型

新增 Person/BOT 数据与 API 适配、独立列表及会话控制器边界，尽量复用现有消息渲染、附件和结构化交互组件。先按可信会话元数据及 Person 身份判定，再进入普通 Agent 路由，避免 `agent:ekko-agent` 把 BOT 误认为普通聊天。`person-main-*` 主会话与私有 `person-task-*` 执行不共享普通会话入口。

`GET /api/studio/person/conversations` 支持 search/offset，返回 next_offset；`GET /api/studio/person?session_id=...` 提供会话配置、任务、交互与活动概况。均使用账号身份，资源 Profile/模型沿用服务端配置并接受 ACL 校验；切换普通 Profile 不重建或改写 BOT。无 BOT 时提示先在 Studio 配置，本期不调用创建或设置写接口。注销、服务器/账号变化清理活动引用；存储使用服务器/账号/BOT/投影版本，旧回包通过世代过滤。

主会话 run/abort 使用经 stable 验证的原 BOT session_id 和 Person 分支，app.resume 用于投影恢复；不要套用普通新建模型偏好。`person.updated` 合并刷新当前 BOT 的活动任务/协作及必要详情，使用合并请求，不每次全量重新加载历史。主会话运行、backgroundPending、任务执行和 flow 状态分别呈现；主会话 abort 不等同于终止全部后台工作。

持久问题可由 approval/clarify 事件携带 `person-interaction:<id>:<revision>`，也可从 Person snapshot 获取。两种呈现归一去重，每次动作只走一个对应提交路径：聊天协议保留原交互 ID，REST `/interactions/:id/answer` 使用 expected_revision/answer。durable 不创建本地倒计时，allow_permanent=false 不提供永久授权。处理另一端已回答/过期和重新恢复，不能因恢复自动回答。适配时保留工作区现有结构化问答改动。

任务详情通过 `/person/tasks/:id/chat`、`/executions` 和必要的 execution events 获取当前/历史执行、验收结果及待处理输入。追问使用 `POST /person/tasks/:id/chat`，停止任务用 `/person/tasks/apply`；按各请求实际字段传递版本、execution ID 和 idempotency_key，并以固定契约样例约束。后台执行可在专用详情读取授权结果，不能提升为普通列表会话。附件复用认证下载/预览，不把凭据附给外部地址。首版显示队列状态，不新增插队/移除控件。

### 10. 发起和控制多 BOT 协作

在 BOT 详情提供轻量协作表单，以既有 BOT 为角色：标题、总目标、1–13 个阶段、阶段目标和 return_expectation，按从 0 连续编号的 group 表达顺序/并行。每组同一 BOT 只能出现一次；校验禁止单角色自交接及重复轮次边界自交接。首版新建仅允许 1–1000 有限 rounds（默认 1），已有 rounds=0 协作仍能展示与停止；不新建无限循环，不提供画布编辑或运行中改路由。

创建调用 `POST /api/studio/person/flows/apply` 的 action=create，携带发起 session_id、stages 和 idempotency_key；提交前展示路线与轮次供用户确认。每次明确操作生成幂等键，未知结果先用 flows/query 对账，不能在重连中自动创建第二条协作。若用户明确重试同一次未知操作，沿用原 key 和负载；改变负载视为新操作，须先解除旧操作结果不明状态。

控制仅使用 stop/resume，携带 flow_id、expected_revision 和 idempotency_key。complete 需要分配给 Agent 的 live turn，不向移动用户暴露。409 刷新再由用户决策；停止处理中仍有 worker、failed 且其他分支未结束、completed 等状态遵守服务端限制。显示 group/round、阶段交付、确认中和错误，不把 Agent 已回复等同于阶段已经验收完成。

### 11. BOT 历史使用统一投影、游标及原子缓存

主时间线以 `person-display-v1` 的 messages 与 personFlows.timeline 为准。通过 `app.resume {session_id,id,timeline:true}` 获取最新页，HTTP 会话分页路径携带 `timeline=true&before=<opaque>&limit=150` 加载旧页。以 timeline.items 的顺序与 `(kind,id)` 合并消息和 flow 卡片；limit 计算两类引用，空 messages 不能判定结束，messageTotal 不能作为统一时间线总数。活动 flows 与终态 cards/card_updates 分开归并，flow revision 防止旧状态覆盖新状态，但不能替代 history_revision。

详情使用 `/person/flows/:id/messages?before_id=...&limit=...`，独立使用 next_before_id/has_more/history_key，显示 BOT、阶段和轮次。隐藏行仍可能推进原始游标，必须支持可见空页继续读取。详情结果与主时间线均遵守投影，不展开内部工具/思考或通过原始会话 API 反推被隐藏记录。

引入有版本、有界、原子写入的专用 BOT 历史缓存；当前 AppStorage 无正文持久缓存，不将新结构塞入旧选择偏好。保存服务端 id、projection、messages、cards、timeline.items、before/has_more/history_revision 为一致快照；主时间线保留最多 300 个引用，按页淘汰并保留重载游标；详情也按页有界淘汰。最新完整页与旧阅读窗口分别管理，不能把多页合并结果冒充服务端最新页 cache id 对应内容。

`app.resumed.messagesCached=true` 时用同 id 的完整本地页，并总是应用实时 run/events/queue/background 状态；命中而本地缺页或坏数据时以空 id 请求完整页。projection 改变使旧 Person 缓存失效，不回退到原始消息路径。跨账号不可复用缓存；本地首次升级无缓存应完整读取，不需要复制旧原始正文。

timeline.reset、history_revision 改变、history_cleared_at 或详情 history_key 改变使对应旧窗口和游标失效；保留草稿，禁止迟到回包复活旧卡片。阅读旧页时仅合并活动状态并提示新内容，返回最新时更新窗口。已读以实际可见内容对应的 message/attention 游标为依据，不能用 flow ID、timeline cursor 或原始 messageTotal 推导。

替代方案：只加 BOT 入口和普通消息列表，会丢失协作卡片、误判翻页结束和缓存命中；仅在完成后读取 flow 详情也无法处理跨设备旧窗口与清空。故 BOT 对话与此完整历史必须共同过阶段 C 验收。

## Risks / Trade-offs

本次验收范围经用户于 2026-11-13 明确调整：Android 在本地模拟器验收，iOS 免测且保持未验收标记；BOT 使用本地受控模型驱动固定 stable 的真实工具、任务、协作和存储闭环，真实模型明确记录为未验证。此决定不允许仅协议 mock 替代真实 Studio 执行，也不构成外部模型质量或 iOS 兼容性声明。

- 服务端描述结构仍在演进 → 固定样例和 schema 校验、可观测失败、旧接口回退，仅声明实测版本。
- native discovery 依赖服务端已装 CLI 和凭据 → 区分 ready/empty/not_installed/auth_required/unsupported/timeout/error，避免将所有异常解释为未登录。
- 增加一条观察连接 → 不加载正文，注销/换 scope 时释放；后台不承诺常驻保活，重新前台再对账。
- 偏好迁移与目录异步回包可能改变模型 → 按 Agent/mode 隔离，保存值不被自动替换，测试竞态。
- 现有任务计划/结构化问答与状态变化相邻 → 保留既有交互实现，回归恢复、失效审批与队列；不覆盖用户未提交工作。
- BOT 投影与旧原始分页路径不同 → 独立类型化 timeline/cursor/cache，覆盖卡片空页、命中缺页、清空及跨账号场景后再开放完整 BOT。
- 同名任务概念与版本字段不同 → 普通目标用 expected_updated_at，Person 任务/协作按各自 revision/execution，消息删除用 historyRevision，避免统一成虚构版本字段。
- 协作控制会与其他设备/后台 worker 并发 → 保留版本和幂等键，冲突刷新、不自动重放；以服务端实际状态解释停止/恢复。

## Migration Plan

1. 阶段 A（tasks 1–6）：固定兼容清单和双基线启动链 → Agent/模型恢复 → 状态观察/远端失效 → 核心验收。旧偏好迁移幂等并保留原键；通过后核心可单独发布。
2. 阶段 B（tasks 7–8）：任务中心和消息选择依赖 A 的身份、历史和错误语义，两者基础适配可以分别推进；删除后的任务联动必须一起验收。完成双端冲突、摘要保护及关联任务测试后才启用删除。
3. 阶段 C（tasks 9–10）：先完成 BOT 身份/API/恢复类型及协作时间线数据，再联通对话、持久交互、任务追问和协作表单；最后完成缓存和跨设备历史。复用阶段 B 的任务定位，保持 Person 执行操作独立。完整 BOT 功能在 tasks 9 与 10 全部通过前保持关闭。
4. 最终验收（tasks 11）：stable 双客户端完整协作，legacy 缺能力降级，preview 独立插件验证，加上 Android/iOS 中英文和全项目回归。缺 CLI/模型等环境条件时明确未验收，不勾选对应任务；不得用 mock 结果冒充真实协作成功。
5. 更新发布和操作说明；所有阶段完成后才归档本变更。必要时逐项关闭新入口或回退客户端；不修改上游数据库，已创建任务/协作留在服务端继续可由 Studio 管理，客户端回退不自动停止或删除它们。

### 规格与实施任务对应

| 能力 | 主要任务 | 共同验收 |
| --- | --- | --- |
| studio-compatibility | 1、6 | 11.1–11.6 |
| agent-discovery | 2 | 6.1、6.4、11.3–11.5 |
| agent-model-selection | 3 | 6.1、6.3、11.3–11.5 |
| cross-device-session-sync | 4–5、9.7 | 6.2、10.10、11.2 |
| session-task-tracking | 7 | 8.4–8.5、11.3、11.5 |
| message-selection | 8 | 7.5、11.3、11.5 |
| bot-conversations | 9 | 10.10、11.1–11.2、11.5 |
| bot-collaboration-history | 10 | 11.1–11.2、11.5 |

## Follow-up Roadmap

当前变更已经细化到完整 BOT 协作；下列能力仍作为后续独立变更，不计入当前 tasks 完成条件。

| 顺序 / 建议变更名 | 依赖 | 最小范围 | 验收结果 / 暂不包含 |
| --- | --- | --- | --- |
| D `add-mobile-background-notifications` | 本期事件去重、BOT 身份及精确跳转 | 完成/失败/待审批/待回答通知 | 先验证第三方客户端设备注册/推送，再分别验收 Android/iOS；不以持续 WebSocket 替代系统推送 |
| E `manage-mobile-bot-settings` | 本期 BOT 与执行资源边界 | BOT 创建/配置、记忆、调度与高级任务策略 | 独立定义权限和编辑冲突；不挤入聊天与协作首版 |
| F 高级工作流与插件管理 | 已验证的 BOT/Agent 基础能力 | 工作流画布、模板与完整插件安装管理 | 另行评估移动端收益，不复制桌面管理界面 |

完整插件安装中心、工作流画布、桌面浏览器控制、高级 DSH 安装维护与主题动效继续后置。插件 Agent 的基本发现/选择属于本期能力探测增强，不等同于插件管理中心。

## Evidence

- 客户端：上表列出的数据/状态文件及 `test/agent_catalog_test.dart`、`foreground_resume_test.dart`、`live_contract_test.dart`。
- 上游 stable：[原生模型协议](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/docs/coding-agent-models.md)、[会话状态实现](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/services/session-state.ts)、[App 事件协议实现](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/services/webhooks/app-events.ts)。
- 上游 preview：[Agent registry](https://github.com/EKKOLearnAI/ekko-studio/blob/302cf39b7cc77410430694eebfb79dc8aff11b97/packages/server/src/modules/studio/services/agents/registry.ts)。
- 上游 stable 任务与删除：[人工任务状态前提](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/services/session-tasks.ts)、[单聊分组与任务级联](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/repositories/session-message-deletion.ts)、[群聊保护边界与版本](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/repositories/group-message-deletion.ts)。
- 上游 stable BOT：[账号会话](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/services/person/conversations.ts)、[持久交互](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/services/person/chat-interactions.ts)、[任务追问](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/services/person/task-chat.ts)。
- 上游 stable 协作与历史：[创建及控制限制](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/services/person/stage-flows.ts)、[统一时间线](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/repositories/person-timeline.ts)、[详情分页](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/services/person/flow-conversation.ts)、[App 条件恢复](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/packages/server/src/modules/studio/services/chat-run/resume-payload.ts)、[展示投影协议](https://github.com/EKKOLearnAI/ekko-studio/blob/312425cca7d707a115d230f0252e9d55786ec57e/docs/person-display.md)。
