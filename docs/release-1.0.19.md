# Chat Studio 1.0.19（20）

## 本次交付

### 动态 Agent 选择

- 修复新建对话固定三个选项、只检查 Codex 安装状态的问题，改为普通登录用户可访问的 `/api/agents/availability`。
- 图标 + 名称的圆角入口和底部选择面板：当前项置顶、高亮与勾选、仅显示已安装项、刷新/失败重试/空状态。
- 名称及静态图标文件与固定上游 Agent 管理页一致；图标按当前服务器客户端缓存，不携带 token、不跟随重定向，失败使用本地标识/缩写并可刷新重试。
- 补齐 Claude、Pi、Grok、OpenCode 的新建与历史续聊路由；外部 CLI 使用 scoped 模式。历史 Claude 别名规范化；未知协议不错误分派给其他 Agent，工作流/群聊/全局 Agent 保持只读。
- 登录、新建、前台恢复、选择面板打开时刷新；服务器/Profile/导航与迟到请求隔离，现有会话 Agent 不被安装列表覆盖。

详见 [协议分析](agent-catalog.md)。已安装仅代表服务端检测到安装，不保证 CLI 登录、模型凭据及运行环境已经就绪。

### Agent 任务计划

- 接入真实 `plan.updated` 及历史/恢复的 `taskPlans`，采用服务端 revision 去重，不从工具参数或自然语言推断状态。
- 淡色紧凑卡片默认折叠，显示当前步骤、完成数量和细进度条；展开查看完整步骤、完成情况和说明，不增加重复头像或抢正文视觉层级。
- 独立于原始消息保存，分页 offset 不计算卡片；跨会话隔离、迟到终态、断网恢复、第二客户端历史恢复经过测试。
- 运行结束不自动勾选未完成步骤；失败/中断保留真实已完成状态。

详见 [任务计划协议](task-plans.md)。实际联调确认内置 Agent，其他 Agent 只有服务端输出相同结构化事件才显示；未增加服务端 CLI 计划桥接功能。

## 验证

- `flutter analyze --fatal-infos`、Dart 格式检查、应用身份/命名门禁及 `git diff --check` 通过。
- **249 项单元/Widget 测试通过，10 项环境跳过**（9 项真实协议、1 项本地字体预览另行执行）；新增 16 项任务计划和 14 项 Agent 目录/图标/路由回归。
- **9 项真实 Studio v1.0.3 HTTP/Socket.IO 契约通过**，固定上游提交 `b44c74318fe5a0a1f3aed29d5095393964fc3d62`；本地确定性模型/语音 Provider，服务端工具/数据库/socket 为真实实现，使用隔离目录及随机测试密码。
- 覆盖 Agent 可用目录一致性、真实任务计划工具、断网期间完成/重连、200 事件缓冲截断后的文本恢复、并行会话、队列、命令、附件与 STT/TTS。
- **1 项截图测试通过，19 张 PNG**，包含新增 Agent 选择与四个任务计划场景。README 使用当前真实 Flutter 组件预览，不添加版本迭代列表；预览数据为夹具、非真机截屏。
- Windows 已串行完成最终源码的签名 Android APK / AAB 构建。没有运行真实外部 Agent CLI/Hermes Python runtime，没有 Android 真机/模拟器端到端验收、iOS 本地编译或远端 GitHub Actions；既有 CI 会自动包含新增测试。

## Android 产物

- 包名 `ai.chatstudio.app`，启动 Activity `ai.chatstudio.app.MainActivity`，名称 `Chat Studio`，versionName `1.0.19` / versionCode `20`。
- minSdk 24 / targetSdk 36，ABI：arm64-v8a / armeabi-v7a / x86_64。
- APK：`dist/chatstudio-1.0.19-android-release.apk`。
- AAB：`dist/chatstudio-1.0.19-android-release.aab`。
- 校验清单：`dist/chatstudio-1.0.19-SHA256SUMS.txt`。
- APK v2 签名校验通过，非 debuggable，含 Dart AOT 且无 debug kernel；沿用已有签名，证书 SHA-256：`51b8f4a1a78f7cb5689601fc762606790c2006b4001658baf5c1480dfc64ff28`。可覆盖同包名、同签名的 1.0.18。
- AAB `bundletool validate`、manifest 校验和 `jarsigner -verify` 退出码为 0；既有自签名证书、无时间戳和 ZIP/JAR 流读取差异警告仍存在，不等于通过 Play Console 审核。

SHA-256：

```text
d8ff0c4a74d9798feea4bc209c6065b0a8c421b17259a34000ad6b7bef787e03  chatstudio-1.0.19-android-release.apk
d6d7638b2e92ccbcd71214e9efceccc9dc60c141ef82d166bc5bb823ac00839f  chatstudio-1.0.19-android-release.aab
```

源码和文档仅本地 Git 提交，不推送远端。二进制、签名密钥、私有诊断日志及原有 `.codegraph/` 索引不提交，也不清理用户已有文件。
