## Purpose

定义手机端在 Studio Provider 模式和原生 CLI 模式中的模型选择与续聊行为，让用户从其他设备打开会话时保持原有执行配置，并防止模式切换、目录刷新和偏好迁移悄悄改变所用模型。

本能力的选择和配置编辑适用于普通 Agent 会话；BOT 使用服务端保存的 Person 配置，普通新建偏好不得覆盖 BOT 的模型、工作区或执行资源。

## ADDED Requirements

### Requirement: 新会话选择有效模式
客户端 SHALL 为新会话提供当前 Agent 支持的 scoped/global 模式，并在运行请求中提交对应模式；已有会话 SHALL 保持服务端记录的模式，切换模式需创建新会话。

#### Scenario: 新建 Global 会话
- **WHEN** 用户为支持 global 的 Agent 选择原生模式并发送消息
- **THEN** 请求使用 global，且不混入其他 scoped 选择的 Provider 或 API 模式

#### Scenario: 既有会话切换模式
- **WHEN** 用户尝试改变已有会话启动模式
- **THEN** 界面提示通过新建会话使用另一模式，不就地转换当前运行上下文

### Requirement: 原生模型与 Provider 模型分别呈现
客户端 SHALL 在 scoped 模式使用 Studio Provider 目录，在 global 模式使用该 Agent 的原生目录；原生模型 ID、别名和前缀 SHALL 原样保留，显示名称不得替代执行值。

#### Scenario: 原生模型别名有解析后的名称
- **WHEN** 目录将原生 ID `opus` 显示为某个具体模型名称
- **THEN** 选择时显示该名称，但运行请求仍提交 `opus`

#### Scenario: 使用原生默认模型
- **WHEN** 用户选择 Agent 默认模型或目录暂时不可用但服务端允许原生默认启动
- **THEN** 客户端提交原生默认的空模型语义，不填入先前的 Provider 模型

### Requirement: 模型发现失败保持可解释性
客户端 SHALL 区分原生目录的 ready、empty、not_installed、auth_required、unsupported、timeout、error 状态；失败刷新 SHALL 不清空已显示的有效缓存或改写已保存选择。

#### Scenario: 单个 Agent 发现超时
- **WHEN** 某个 Agent 的模型发现返回 timeout
- **THEN** 界面说明发现超时并提供重试，不声称账号已退出，不影响其他 Agent 的目录

#### Scenario: 保存模型已不在新目录
- **WHEN** 用户打开的会话模型没有出现在最新目录中
- **THEN** 显示原始保存值与未重新验证状态，不自动换成目录第一项；实际执行仍由服务端决定是否接受

### Requirement: 会话恢复完整执行配置
客户端 SHALL 从服务端恢复 Agent、启动模式、模型、Provider、API 模式和思考强度，并以会话保存值优先于新建偏好；未知模式 SHALL 明确限制续聊，不能猜测转换。

#### Scenario: 从 Web 接续原生会话
- **WHEN** Web 创建的会话保存了 global 模式、原生模型和思考强度
- **THEN** 手机上打开并续聊时保留这三项配置，不发送 scoped 模式

#### Scenario: 老会话没有模式字段
- **WHEN** 服务端未提供模式字段且记录符合已验证的历史 scoped 路由
- **THEN** 客户端按兼容规则恢复 scoped；不符合已知路由的记录显示不可续聊原因

### Requirement: 模型协议与思考强度跟随实际选择
客户端 SHALL 保留显式选定的 API 协议，使用服务端给出的每模型协议与思考强度能力；变更模型后无效的选项 SHALL 明确重置或要求重新选择，不得继续发送不受支持值。

#### Scenario: 同 Provider 下模型协议不同
- **WHEN** 服务端为两个模型提供不同的每模型 API 模式，用户从一个切换到另一个
- **THEN** 客户端依据新模型及显式覆盖规则展示和提交协议，不只沿用 Provider 分组默认值

#### Scenario: 原生模型没有思考强度声明
- **WHEN** 原生模型目录未给出该模型的 reasoningEfforts
- **THEN** 客户端不为新选择编造可用强度；已有会话保存值继续作为原配置展示，不能静默改写

### Requirement: 偏好按身份 Agent 与模式隔离
客户端 SHALL 分别记忆服务器、账号、Profile、Agent 和模式对应的新建选择；旧偏好 SHALL 只迁移至能够明确对应的槽位，且不存储模型密钥或原生凭据。

#### Scenario: 在 Scoped 和 Global 间切换
- **WHEN** 用户分别配置两个模式的模型后反复切换
- **THEN** 每个模式恢复自己的选择，不将原生模型填入 Provider 下拉框

#### Scenario: 旧偏好迁移重复执行
- **WHEN** 应用升级后的迁移被再次执行
- **THEN** 已保存的新偏好不被旧数据覆盖，且不同账号和 Profile 的选择不串用

### Requirement: 配置修改服从执行状态和权限
客户端 SHALL 保留运行中配置锁定和服务端权限控制；配置保存失败时 SHALL 继续展示实际生效值并提供错误反馈。

#### Scenario: 模型修改被服务端拒绝
- **WHEN** 用户修改模型但服务端返回权限错误或运行状态冲突
- **THEN** 当前会话继续显示原生效模型，不把失败请求当作已保存结果
