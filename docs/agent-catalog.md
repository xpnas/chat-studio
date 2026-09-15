# 动态 Agent 目录与移动端选择

## 问题定位

旧的新建会话入口固定列出三个引擎，仅额外查询 Codex 是否安装；历史会话中其他 Agent 又会被映射为 Hermes。因此不仅缺少服务端 Agent 选项，简单增加 UI 选项也不足以正确聊天。

本次分析固定上游 `hermes-studio v1.0.3`、提交 `b44c74318fe5a0a1f3aed29d5095393964fc3d62`，直接核对以下源码（路径相对上游根目录）：

| 文件 | 协议依据 |
| --- | --- |
| `packages/client/src/api/agent-status.ts` | 前端可用性快照接口 |
| `packages/client/src/views/hermes/AgentManagerView.vue` | Agent 名称和图标对应关系 |
| `packages/server/src/modules/studio/routes/agent-status.ts` | 普通登录用户可访问 availability；完整 status 为管理员接口 |
| `packages/server/src/modules/studio/controllers/agent-status.ts` | 可用性响应 |
| `packages/server/src/modules/studio/public/agent-status-registry.ts` | 已安装状态与来源 |
| `packages/server/src/modules/studio/sockets/chat-run.ts` | run 参数接收 |
| `packages/server/src/modules/studio/services/chat-run/handle-coding-agent-run.ts` | 外部 CLI 分派；未知 ID 会落入 Claude 分支，不能任意透传 |

## 数据来源

每次登录/切换服务器或 Profile、新建对话、新对话页回到前台、打开选择面板或手动刷新时，读取当前服务器的：

```http
GET /api/agents/availability
Authorization: Bearer <当前服务器设备 token>
```

响应示例：

```json
{
  "revision": 1,
  "updatedAt": "2026-09-16T00:00:00.000Z",
  "agents": [
    {"id": "hermes", "installed": false, "source": "not-installed"},
    {"id": "codex", "installed": true, "source": "user-cli"}
  ]
}
```

**列表和安装状态来自服务端，不再固定三项。** 此版本接口不返回名称/图标，客户端保留与上游 Agent 管理页一致的展示及路由映射，这不等于把安装列表写死。图标按管理页文件名从当前服务器 `/coding-agents/` 加载；不依赖外部图床、不携带鉴权头、不跟随重定向。按 API 客户端缓存请求，限制大小/超时，失败显示本地标识或缩写；刷新目录后可重试失败图标。

## 交互与隔离

- 首页入口采用圆角按钮，显示当前 Agent 图标、名称、展开箭头。
- 点击展开适合单手操作的底部选择面板：图标 + 名称、当前项淡色高亮和勾选并置顶，其余按名称排序。
- 仅展示 `installed: true` 的项目。空列表、首次加载、加载失败分别提示，提供刷新/重试；不伪造默认可用项。
- 已有成功目录时，后台刷新不无故阻断立即发起对话；首次无目录或刷新失败时禁止新建发送。安装状态存在短暂缓存窗口，最终能否执行仍由服务端确认。
- 已安装但协议尚不支持的未知 Agent 显示为禁用并说明原因，避免被上游错误分派到 Claude。
- 新建页原选项卸载后提示并回退到可用项；已有历史会话始终保留原 Agent，不因目录刷新改换后端。
- 请求序号、登录 epoch、API 实例和 Profile 校验阻止旧服务器/旧请求结果覆盖新状态；选择面板还检查导航版本，避免切换会话后误操作新草稿。
- 语音配置重新检测不附带 Agent 列表刷新，避免无关接口失败影响录音。

## 会话路由

| Agent | 新建/续聊参数 |
| --- | --- |
| Hermes | 原 Hermes 路由，不携带 coding-agent 参数 |
| 内置 Agent | 保留上游真实 ID 与 `source: coding_agent` |
| Claude / Codex / Pi / Grok / OpenCode | 规范 ID、`source: coding_agent`、`mode: scoped` |

历史 `claude` 统一为路由 ID `claude-code`。工作流、群聊、全局 Agent 会话仍只读；客户端不安装或执行任何 CLI。生产代码内上游旧品牌字面值仍集中在 `studio_protocol.dart`，没有重新散落到应用身份/路径中。

## 验证与边界

- `test/agent_catalog_test.dart`：14 项，包括严格解析、普通用户接口、安装过滤、刷新、错误/空目录、跨服务器迟到结果隔离、历史 Agent 不变、四种新增外部 Agent 的新建/历史 scoped 参数、图标请求缓存/无鉴权/重定向禁止、选择列表与 320px/1.8 倍字体布局。
- `test/live_contract_test.dart`：真实隔离 Studio 的 availability 与移动端可选目录一致，刷新后仍一致。没有伪造本机已安装外部 CLI。
- 隔离环境没有 Hermes runtime，命令契约通过真实 REST 创建既有 Hermes 会话来验证服务端 slash 命令；不会为了测试把未安装 Hermes 塞回新建列表。
- `test/preview_test.dart`：新增 Agent 面板预览，截图使用确定性数据而非生产账号。

已安装不意味着授权、模型凭据或 CLI 登录必然就绪；本次未实际执行 Claude/Codex/Pi/Grok/OpenCode CLI 或 Hermes Python runtime。完整回归与打包结果见 [测试记录](testing.md)。
