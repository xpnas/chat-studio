# 后台断网恢复修复与截图更新

日期：2026-09-15。应用版本：`1.0.16+17`。

## 复现与根因

用户报告的路径为「后台网络中断 → 前台重连 → 显示同步 → 最新 AI 回复部分重复」。旧联调仅调用 `onBackground` / `onForeground`，socket 一直保持连接，没有验证真正断线后服务端快照与客户端缓存的合并。

核对固定上游 Studio v1.0.3（`b44c74318fe5a0a1f3aed29d5095393964fc3d62`）发现两类问题：

1. `handle-bridge-run.ts` / `bridge-message.ts` 将桥接会话的历史消息存为 `cli_run_*` 或 `cli_resume_*`，而 socket 事件的 `run_id` 为 runtime ID。此前客户端把快照和回放识别为两个助手消息，显示层合并相邻 AI 消息时再次拼入同一正文。同一 run 还可能包含已标记 `stop` 的 interim 段落、工具消息和后续段落，不能只看最后一条消息。
2. 上游事件日志保留尾部 200 条。旧合并顺序先拼「短快照 + 截断尾部」，再与更长的本地前缀合并，会产生无法重叠的中间结果。例如 `步骤一。`、本地 `步骤一。步骤二。步骤三。` 和回放 `步骤三。步骤四。`，可能被拼成重复段落。

新增测试先确认原实现失败，再修复，不删除或放宽既有回归断言。

## 修复

- 在最近用户轮次内解析 bridge marker 与 runtime ID 的对应，合并同 marker 的助手/工具步骤，保留当前流式气泡的 renderKey。
- 以累计 `message.delta.output`、已验证同 runtime 的本地前缀，或同用户 run 下匹配的工具调用 ID 为证据；不能拿任意历史文本做全局去重。
- 桥接累计 output 按完整文本替换，不再将已回放 delta 再追加；普通无 output 的增量事件仍严格追加，正常的重复词语保留。
- 兼容 bridge `message.interim.output` 修订，以及 `reasoning.delta` / `thinking.delta` 的 `text` 字段；同样采用批量通知，不唤醒非当前会话的 UI。
- 快照和本地缓存先作为同一 run 的前缀进行协调，再与截断的回放尾部做重叠合并；正文和思考采用相同顺序。
- 工具执行较久、保留的事件已经没有正文时，仍可以本地前缀/匹配工具 ID 恢复，而不是另起一个空助手气泡等待下一次累计输出。
- 完整事件顺序仍用于重建审批、澄清和工具状态；不引入按事件文本值过滤的去重逻辑，不重发用户消息。

## 验证

| 项目 | 结果 |
| --- | --- |
| `test/disconnected_resume_test.dart` | 新增 **13 项**回归，覆盖 bridge 完整/截断/仅工具回放、冷恢复、多工具步骤、旧 run 隔离、重复同步、累计 output、interim 与三方合并 |
| `flutter test` | **202 项通过、8 项环境相关跳过** |
| `flutter analyze --fatal-infos` | 无问题 |
| CI 同口径 `dart format` 检查 | 57 个文件，0 个待格式化 |
| 隔离真实 Studio HTTP / Socket.IO | **7 项通过**，Windows runner 启停真实 Node 服务 |
| Flutter 截图预览测试 | **1 项通过**，重新生成 12 张 PNG，并人工查看图像 |

实际断网测试使用真实 `SocketChatTransport`，生成 500 字符的确定性回复，超过上游 200 事件保留窗口后，连续 3 次关闭 socket、后台等待 250ms、前台创建新连接并等待 `resumed`。断开期间确认正文没有收到新事件；每次恢复后检查没有后退、没有重复、气泡身份不变；逐个 `resumed` / `message.delta` 检查正文始终是预期结果的唯一前缀，避免最终 `run.completed.output` 覆盖中间错误。确认 `run` 只发送一次。

复现：`scripts/studio-contract.ps1`（Windows）或 `scripts/studio-contract.sh`（Linux）。详见 [测试说明](testing.md)。

## README 与截图

- 删除根 README 的版本迭代/更新历史段落，将仍适用的队列、审批、命令和音频附件能力放回功能说明。
- 替换旧的带版本号安装包说明，改用稳定构建输出路径。
- 按当前代码重新生成截图，统一模型测试数据；标题和引擎选择继承主题字体，避免字体预览的缺字方块。
- 深色历史列表等主题和嵌套文字动画完成后再截图，避免旧图呈现浅色或黑色文字。
- 添加 [截图说明](screenshots/README.md)，记录尺寸、场景、本地字体生成步骤和验证边界。

## Android 包

- `ai.ekkolearn.ekko_app`，versionName `1.0.16`，versionCode `17`；minSdk 24，targetSdk 36。
- Release APK / AAB 由本地 Flutter 构建，使用原有本地签名身份，非 debug key。
- APK：`dist/ekko-mobile-1.0.16-android-release.apk`；原始输出在 `build/app/outputs/flutter-apk/app-release.apk`。
- AAB：`dist/ekko-mobile-1.0.16-android-release.aab`；原始输出在 `build/app/outputs/bundle/release/app-release.aab`。
- SHA-256 清单：`dist/ekko-mobile-1.0.16-SHA256SUMS.txt`。二进制、私钥与本地诊断日志均不提交 Git。

签名和结构校验：APK `apksigner verify` 的 v2 验证通过；证书 SHA-256 为 `51b8f4a1a78f7cb5689601fc762606790c2006b4001658baf5c1480dfc64ff28`。AAB `bundletool validate` 和 `jarsigner -verify` 退出码均为 0；JAR 校验仍提示自签名证书、没有时间戳及 ZIP 流读取差异，不把这些警告描述为不存在，也未声称 Play Console 审核通过。

## 验证边界

这是 Windows 上的真实服务/真实 WebSocket 断连联调，加客户端确定性回归；不是 Android 真机切后台、弱网、Doze、操作系统杀进程或帧率验收。桥接路径由固定源码契约夹具覆盖，没有启动真实 Codex CLI 或 Hermes Python runtime。所有模型/语音为隔离本地夹具，不使用生产会话、外网收费模型或生产密钥。

iOS 未在本机编译；未推送远端，也未运行 GitHub Actions。新 APK 仍应在出现问题的手机上覆盖安装，按原稳定复现步骤复测。
