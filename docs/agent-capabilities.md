# Agent 能力管理

移动端的「服务管理 → Agent → 对应 Agent → 能力管理」对应 Hermes Studio Web 左侧的 Agent 管理入口，使用当前服务器地址、登录身份和 Profile 直接访问服务端接口，不保存一份手机端副本。只有 `super_admin` 可以打开入口，服务端仍负责最终鉴权。

## 入口与交互

- 在「服务管理 → Agent」中选择 Hermes Runtime 或 Ekko Agent；运行参数、运行时版本和能力管理统一放在对应 Agent 内，不再并列重复入口。
- 能力管理继承所选 Agent，不再二次切换；Coding Agent 的安装、更新和配置入口保留。
- 能力列表和每项详情均为全屏原生页面；刷新只刷新当前能力，不重载整个管理页面。
- JSON、Markdown 和长文本使用全屏编辑器；危险操作需要二次确认。
- 所有成功写操作完成后重新拉取当前能力数据，保证与 Web 端和其他设备同步。

## Hermes Runtime

| 能力 | 移动端支持 | 服务端接口 |
| --- | --- | --- |
| 任务 | 列表、创建、编辑、暂停、恢复、立即执行、删除 | `/api/hermes/jobs` |
| 频道 | Telegram、Discord、Slack、WhatsApp、Matrix、微信、企业微信、飞书、钉钉、QQBot 原生表单、凭据更新与清除、微信扫码登录 | `/api/hermes/config`、`/api/hermes/config/credentials`、`/api/hermes/weixin/*` |
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
- 频道使用全屏原生表单，不要求用户填写 JSON。微信扫码沿用 Web 的外部扫码页面和服务端轮询流程；离开页面后停止轮询，扫码结果只保存到发起操作的 Profile。
- 当前移动端不执行 Agent CLI，不在手机安装运行时；这些操作仍由服务端管理。

## 频道数据与保存规则

对照本地 `D:\code\hermes-studio` 的 `b6293a11`：

- Web：`packages/client/src/components/hermes/settings/PlatformSettings.vue`、`PlatformCard.vue`、`stores/hermes/settings.ts`。
- 服务端：`packages/server/src/modules/hermes/controllers/config.ts`、`controllers/weixin.ts`。
- 行为配置读取顶层 `telegram` / `discord` 等分区；连接参数、凭据和访问控制读取 `platforms.<platform>`；`platformCredentialStatus` 仅用于判断能否清除凭据，不等于频道已连通。
- “已配置”遵循 Web 的判定逻辑。Matrix 必须具有 Homeserver，以及 Token 或用户 ID + 密码；不能因存在行为参数或代理就显示已配置。
- 密钥不在表单中回显；普通参数（代理、Homeserver、App ID、访问控制等）正常显示。密钥留空保持原值，清除单项需明确确认后保存；清除全部凭据使用专用 DELETE 接口，不清空整个平台配置。
- 保存仅提交改动字段，保留未知字段和其他设备修改的无关配置。只有行为发生变化时请求 Gateway 重启；同时修改凭据时由凭据接口触发重启，避免重复重启。是否实际自动重启仍由服务器策略控制。
- 保存失败保留输入；行为已保存但凭据失败时明确提示，重试不重复提交成功部分。清除后的自动重启禁用/失败警告不会被“保存成功”掩盖。
- WhatsApp 的 `enabled`、钉钉/QQBot 的访问控制写入 credentials 接口；QQBot 的 Markdown 开关写入行为分区的 `extra.markdown_support`。
- 刷新平台表单只更新本页数据；未保存修改离开/刷新时需确认。操作绑定初始 Profile 和登录身份，异步期间身份变化不能将凭据写到其他 Profile。

回归测试：`test/hermes_channels_test.dart` 包含字段映射、Web 状态判定、保存顺序、失败重试、清除警告、扫码轮询、Profile 隔离及中英文/深浅色/小屏大字体布局测试。使用模拟服务响应，不代表真实第三方 Bot 已验证连通。
