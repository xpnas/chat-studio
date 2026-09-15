# Agent 任务计划：协议分析与移动端实现

## 结论与支持范围

可以实现，且不需要修改服务端。Chat Studio 直接消费 Hermes Studio v1.0.3 已有的结构化计划：展示完成数量、当前步骤、逐项状态和结束/中断/失败提示。

分析基于本地上游源码 `b44c74318fe5a0a1f3aed29d5095393964fc3d62`，并用 CodeGraph 查看客户端消息模型、时间线和渲染依赖。内置 Agent 的 `update_plan` → 持久化 → `plan.updated` 已通过实际运行验证。

**不是所有回复都会有计划。** 简单问答或 Agent 没有调用计划工具时不显示卡片。Hermes / Codex / 其他 Agent 只有在服务端输出同一结构化契约时才显示；本次没有增加服务端 Agent 桥接能力，也没有把自然语言清单、思考内容或工具参数猜测为真实计划进度。

## 上游依据

以下路径相对上游仓库根目录：

| 文件 | 确认内容 |
| --- | --- |
| `packages/ekko-agent/src/tools/plan.ts` | `update_plan` 每次提交完整步骤列表，持久化成功后发出计划；结束时增加 revision，将仍在进行的步骤改回 pending，不自动完成 |
| `packages/server/src/modules/studio/contracts/task-plan.ts` | 快照字段及步骤/执行状态枚举 |
| `packages/server/src/modules/studio/repositories/task-plan-store.ts` | 按会话和计划 ID 保存，仅接受更高 revision；按历史页关联 run 取计划，首页附加最近计划；服务重启中断遗留运行计划 |
| `packages/server/src/modules/studio/services/chat-run/handle-ekko-agent-run.ts` | 内置 Agent 事件转为扁平的 `plan.updated` 快照 |
| `packages/server/src/modules/studio/controllers/sessions.ts` | 历史 messages 响应包含顶层 `taskPlans` |
| `packages/server/src/modules/studio/services/chat-run/resume-payload.ts` | 恢复快照携带计划；计划不依赖短期事件缓冲完整保留 |
| `packages/client/src/utils/task-plan.ts` | Web 端按计划标识与 revision 去重、按 run / 时间定位 |
| `packages/client/src/components/hermes/chat/TaskPlanCard.vue` | Web 端步骤及执行状态显示参考 |

主要载荷示例：

```json
{
  "session_id": "session-1",
  "run_id": "run-1",
  "plan_id": "plan-1",
  "revision": 2,
  "execution_state": "running",
  "created_at": 1789516800000,
  "updated_at": 1789516801000,
  "explanation": "先验证协议，再完成界面。",
  "plan": [
    {"id": "inspect", "step": "分析协议", "status": "completed"},
    {"id": "build", "step": "实现移动端", "status": "in_progress"},
    {"id": "verify", "step": "运行回归测试", "status": "pending"}
  ]
}
```

`plan.updated` 的 data 直接是该对象，不再包一层 plan；历史和恢复响应的 `taskPlans` 是该对象数组。执行状态为 `running / ended / interrupted / failed`，步骤状态为 `pending / in_progress / completed`。

## 客户端设计

- `lib/data/task_plan.dart`：不可变计划数据、严格字段校验，拒绝非法版本、重复步骤 ID、未知状态和越界列表/文本。只读取已确认快照，不读取工具参数作为状态来源。
- `lib/state/chat_timeline.dart`：计划独立于原始消息存储，以 `session_id + plan_id` 为键，仅合入更高 revision，并校验所属 run。会话重新绑定清除旧计划，服务器/Profile 切换沿用已有隔离机制。
- `lib/data/studio_api.dart` / `lib/state/app_controller.dart`：历史分页合入顶层计划元数据。**分页 offset 仍只计算原始消息条数**，卡片不会导致跳页或重复历史。
- 恢复时合并已有计划、服务端快照与保留事件中的计划版本；即使计划事件位于最新 `run.started` 之前也处理。计划更新不进入文字 delta 拼接，不改变已有后台重复正文修复。
- 最终计划事件可以晚于 `run.completed`；不会因普通文字的旧 run 过滤而丢掉。提前收到终态时只停止进行中状态，保留服务端 revision 和已完成步骤，等待正式最终快照。
- 显示时生成独立计划行，优先插在所属 run 的第一条非用户/非命令消息前，缺少 run 标记时按创建时间定位。原始消息的秒级时间统一换算为毫秒，与计划时间比较。
- `lib/ui/widgets/task_plan_card.dart`：默认折叠，淡圆角背景、细进度条、完成数量、当前步骤；点击展开查看全部步骤和说明。展开选择通过稳定 PageStorageKey 在实时更新间保持。
- 不加 AI 头像、不重复正文、不展开工具日志；小字号与紧凑间距保持辅助信息层级。进度为已完成步骤占比，不是时间估算，也不承诺准确剩余耗时。

## 验证

16 项单元/Widget 回归及 1 项新增真实服务联调；全量结果见 [测试记录](testing.md)。真实联调顺序：

1. 本地模型 Provider 发出真实 `update_plan` 工具调用，服务端提交初始计划。
2. App 收到部分完成的计划后后台断开实际 Socket.IO 连接。
3. 服务端继续调用计划工具并完成运行。
4. 前台恢复只同步一次最终卡片，版本增加，正文不重复，不重发用户输入。
5. REST 重读计划，第二个客户端登录打开历史，再连续两次断开/恢复验证去重。

模型 Provider 只对 `TASK_PLAN_CONTRACT` 夹具输入返回计划工具调用；不需要真实模型密钥，不更改上游仓库，不使用生产服务器。它验证协议与状态恢复，不代替真机网络、帧率及 iOS 编译验收。

预览：`docs/screenshots/task-plan*.png`，由真实 Flutter 组件生成，非真机截图。
