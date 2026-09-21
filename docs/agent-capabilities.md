# Agent 能力管理

移动端的「管理 → Agent 能力」对应 Hermes Studio Web 左侧的 Agent 管理入口，使用当前服务器地址、登录身份和 Profile 直接访问服务端接口，不保存一份手机端副本。只有 `super_admin` 可以打开入口，服务端仍负责最终鉴权。

## 入口与交互

- 在「管理 → Agent」中打开「Agent 能力管理」。
- 顶部使用 Hermes / Ekko 分段切换；Agent 图标使用服务端静态资源，加载失败才回退到本地占位图标。
- 能力列表和每项详情均为全屏原生页面；刷新只刷新当前能力，不重载整个管理页面。
- JSON、Markdown 和长文本使用全屏编辑器；危险操作需要二次确认。
- 所有成功写操作完成后重新拉取当前能力数据，保证与 Web 端和其他设备同步。

## Hermes Runtime

| 能力 | 移动端支持 | 服务端接口 |
| --- | --- | --- |
| 任务 | 列表、创建、编辑、暂停、恢复、立即执行、删除 | `/api/hermes/jobs` |
| 频道 | Telegram、Discord、Slack、WhatsApp、Matrix、微信、企业微信、飞书、钉钉、QQBot 配置查看和 JSON 编辑 | `/api/hermes/config` |
| 技能 | 分类列表、启停、置顶、查看/编辑本地技能、删除本地技能 | `/api/hermes/skills` |
| 插件 | 状态查看、启用/停用；Provider-managed 插件只读 | `/api/hermes/plugins` |
| MCP | 增加、编辑、删除、连接测试；显示 transport、工具数和连接状态 | `/api/hermes/mcp/servers` |
| 记忆 | `Memory.md`、`USER.md`、`SOUL.md` 三块内容编辑 | `/api/hermes/memory` |

Hermes 技能的内置、Hub、外部目录资源遵守服务端只读规则；移动端不会绕过服务端限制。任务创建目前使用 Web 兼容的名称、schedule、prompt 字段，复杂投递目标和高级字段仍可在 Web 端编辑。

## Ekko Agent

| 能力 | 移动端支持 |
| --- | --- |
| 技能 | 列表、启停、详情编辑、新建、删除（内置技能不可删除） |
| MCP | 增加、编辑、删除、连接测试 |
| 记忆 | 列表、编辑标题/内容/标签、按 revision 并发保护删除 |

Ekko 技能、MCP 和记忆接口均使用 `/api/ekko/*`，编辑发生在服务端 Profile，不会操作手机文件。

## 协议与兼容性

- App 使用 `X-Hermes-Profile` 发送当前 Profile，保留 Hermes/Ekko 的原始接口字段和响应结构。
- MCP 配置采用 Web 端相同的 JSON 对象；保存前进行 JSON 对象校验。
- 记忆更新使用服务端返回的 revision；发生并发修改时保留错误提示并要求刷新后重试。
- 频道页面是通用配置编辑器，适合移动端安全地覆盖 Web 已支持的平台；平台的 QR 登录、收件人发现和复杂引导仍在 Web 端完成。
- 当前移动端不执行 Agent CLI，不在手机安装运行时；这些操作仍由服务端管理。
