# 进行中聊天恢复重复/闪动修复

## 症状

切换聊天或重启后，正在运行中的最后一个助手气泡偶发出现同一段内容重复，且因历史页先渲染、恢复快照再渲染而突变闪动。

## 根因

服务端恢复同时返回：

1. 数据库消息快照（可能含当前 assistant 前缀，且其后还带 tool row）；
2. 当前 run 的事件回放（`run.started`、`message.delta`、`reasoning.delta`）；
3. 运行中的助手原本在 App 本地已有一份流式缓存。

旧实现只看消息数组最后一行，只有“最后一行是 assistant 且标记未完成”时才跳过回放。最后一行是 tool 或消息缺少标记时，会把快照已有文本和事件增量重复接在一起；同时历史请求和 resume 可能交替落地。

## 修复策略

- `ChatMessage` 保存 `runMarker`、`finishReason`、是否显式收到 finish reason。
- 恢复采用单次原子重建：先识别本次 active run，定位该 run 的所有未完成 assistant，不依赖“最后一行必须是 assistant”。tool 行仅合并 tool 状态，不生成第二个 assistant。
- 从干净 reducer 重放当前 run 事件，再与持久快照按“前缀/重叠”合并；只在确实属于同一 run 时合并，禁止对跨轮次相同文本做全局去重。重复的自然语言词语仍原样保留。
- 复用切换前正在显示的 `stream:` assistant 身份和已显示较长内容，避免 key 变化触发气泡闪烁/滚动跳变。
- 有 metadata 时用 `runMarker` 精确匹配；老服务缺 metadata 时，仅当回放内容以快照文本为前缀才做保守识别，否则不擅自拼接。
- 切换/恢复时作废未完成的历史请求，正在进行的会话不先加载一份竞争历史页；历史请求落地前校验 epoch、requestId、revision、API 实例。
- 流式增量仍按 runId 过滤，完成后的迟到事件继续丢弃。

## 验证

新增 5 项恢复测试：截图同类“assistant + tool + replay”、重复 resume 保持 renderKey、无 marker 保守合并、重复词不误去重、无 replay 时继续接收当前 run 增量。完整本地测试通过，静态分析通过。

仍需真实 Android 真机进行：切换 Wi-Fi/后台、杀进程重启、超长回复、工具调用中恢复和弱网下帧率观察。服务端恢复 payload 的具体 metadata 会随版本变化，升级 Studio 后应复跑恢复契约测试。
