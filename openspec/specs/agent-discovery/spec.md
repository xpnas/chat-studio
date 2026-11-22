# agent-discovery Specification

## Purpose

让手机端根据连接服务端提供的身份、安装状态与受支持能力选择 Agent，减少固定白名单造成的功能缺口，同时保证未知身份、失效安装和不同服务器的目录不会造成错误路由或隐式替换。

## Requirements

### Requirement: Agent 选择由服务端状态和已理解的协议共同决定
客户端 SHALL 仅允许选择服务端报告可用且客户端理解其聊天路由和模式的 Agent；静态元数据不得被解释为已安装或已获得调用权限。

#### Scenario: 稳定版存在新增 Coding Agent
- **WHEN** 稳定版报告 Qwen、Kimi、CodeBuddy、Copilot、Cursor、Qoder、Antigravity 或 ZCode 已安装，且对应协议元数据有效
- **THEN** 客户端按受支持模式提供选择，不受原八项白名单限制

#### Scenario: 未安装或协议未知
- **WHEN** 服务端记录未安装，或只有未知 ID 而没有客户端可理解的路由契约
- **THEN** 客户端不给出可发送选项，并展示明确的不可用原因

#### Scenario: 统一目录不包含核心 Agent
- **WHEN** 统一接口返回 Coding Agent/插件描述但不包含 Ekko/Hermes
- **THEN** 客户端从 availability 读取 Ekko/Hermes 状态，与统一 Coding 目录合并；统一描述和静态元数据均不覆盖核心安装状态

#### Scenario: 合法空 Coding 目录
- **WHEN** 统一接口成功返回空目录，而 availability 同时包含核心和 Coding 记录
- **THEN** 客户端只从 availability 保留 Ekko/Hermes，不从 availability 补入 Coding Agent，也不猜测缺失核心记录已安装

### Requirement: 统一描述支持合法插件身份
在插件增强已完成固定预览基线验证且服务端支持统一描述时，客户端 SHALL 接受其合法插件身份、安装状态、chat surface 和已理解模式，并在 API 路由中保留完整身份。

#### Scenario: 合法 OMP 插件 Agent
- **WHEN** 服务端返回可用的 `plugin:omp/omp`，声明 chat surface 和受支持模式
- **THEN** 用户可选择该 Agent，实际聊天请求保留完整插件 ID，不转换为 Pi 或其他内置 Agent

#### Scenario: 无聊天能力或非法身份
- **WHEN** 描述不包含 chat surface，或 ID 包含不符合身份契约的路径结构
- **THEN** 客户端不将其作为聊天选项，也不构造未经验证的请求路径

### Requirement: 能力决定交互控件
客户端 SHALL 仅显示或启用当前 Agent 明确支持的模式和命令能力；管理入口声明不得推导为上下文查询、压缩或其他运行能力。

#### Scenario: 仅支持 Global 的 Agent
- **WHEN** 用户选择仅声明 global 的 Agent
- **THEN** 客户端选择 global 并不提供 scoped 启动选项

#### Scenario: 未声明压缩能力
- **WHEN** Agent 描述只有设置入口而没有已验证的压缩能力
- **THEN** 客户端不因存在设置入口而启用压缩操作

### Requirement: 目录刷新不得改写既有会话身份
客户端 SHALL 保留已存在会话的 Agent 标识与历史内容；目录变更仅影响可执行操作和新建会话选项。

#### Scenario: 当前 Agent 被移除
- **WHEN** 目录刷新发现当前会话 Agent 已卸载或插件被禁用
- **THEN** 历史仍可阅读，继续发送被禁用并显示原因，不自动切换到其他 Agent

#### Scenario: 新建会话原偏好失效
- **WHEN** 新建会话保存的 Agent 不再可用且仍有其他可选项
- **THEN** 客户端明确展示新的候选选择，不把它写入任何已有会话

### Requirement: 展示资源失败可降级
客户端 SHALL 在 Agent 名称或图标缺失、图标加载失败时保留可识别的 ID 和通用图标；外部展示资源不得接收 Studio 登录凭据。

#### Scenario: 图标地址无效
- **WHEN** 一个有效可用 Agent 的图标无法加载
- **THEN** 该 Agent 仍可按其能力选择和聊天，并使用通用图标
