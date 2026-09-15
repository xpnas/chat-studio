# Chat Studio 1.0.17（18）

## 本次变更

1. 图片改为近全屏无标题预览，周边仅 2 logical px 留白；保持图片比例、双指缩放，轻点图片关闭。右下角 16 px 图标/11 px 字号的保存、关闭入口保留正常触控区域。错误重试、取消下载、系统保存及鉴权不变。
2. AI 音频仅播放/停止/下载，移除转文字入口和控制器触发方法；麦克风语音输入 STT 不受影响。
3. 登录页和个人信息可进入服务器管理。登录成功保存地址、token、Profile、LAN HTTP 选项；同一标准化地址去重，旧版单服务器会话自动迁入安全存储。不保存密码或模型供应商密钥。
4. 切换服务器先失效旧回调、关闭网络/播放、清空聊天和未发送草稿；不停止远端任务。各服务器保留自己的登录/模型/引擎偏好。授权过期仅清理对应 token；退出保留服务器配置和其他服务器登录，删除记录需要确认。
5. 顶部菜单右侧和 AI 气泡根据当前会话显示 Agent 图标和名称；支持 Ekko、Hermes、Codex、Claude、Pi、Grok、OpenCode。未知 Agent 显示其 ID/缩写。
6. Android/iOS 桌面显示名称、登录页、抽屉、关于页和服务端设备名称统一为 Chat Studio。

## 资源与升级兼容

Agent 静态文件名来自固定源码 `packages/client/src/utils/chat-agent-avatar.ts` 和 Agent Manager；PNG/SVG 从用户当前服务器 `/coding-agents/` 获取，不打包/再分发上游图标，不携带 token，不使用第三方图标代理。不可用时显示本地标识或 Agent 缩写。

保留 `ai.ekkolearn.ekko_app` 包标识、Dart 包名、平台文件导出通道、安全存储键及已有 Android 签名，以支持覆盖升级并迁移已有登录。不是新的包名应用。服务器记录按地址保存一个账号，需要换同服务器账号时退出并重新登录。

## 验证

- 格式与静态分析通过。
- 212 项单元/Widget 测试通过，8 项环境跳过；新增 10 项精确回归，原后台重复修复测试保留。
- 7 项隔离真实 Studio HTTP/Socket.IO 契约通过（包含实际 socket 断线/恢复）；模型/语音采用本地夹具，不使用生产会话或收费模型。
- 14 张真实 Flutter 组件预览已刷新并查看；其中全屏图片预览等待图片完成解码后截图，非真机截图。
- 当前 Windows 无 iOS 编译环境；未运行远端 Actions，没有 Android 真机/模拟器端到端体验验收。Agent 图标映射依照固定源码，未启动真实 Codex CLI/Hermes Python runtime。

## Android 交付

- 已构建签名 Release APK 与 AAB，包名 `ai.ekkolearn.ekko_app`，桌面名称 `Chat Studio`，versionName `1.0.17`、versionCode `18`，minSdk 24 / targetSdk 36。
- APK：`dist/chat-studio-1.0.17-android-release.apk`。
- AAB：`dist/chat-studio-1.0.17-android-release.aab`。
- 校验清单：`dist/chat-studio-1.0.17-SHA256SUMS.txt`。
- APK `apksigner verify` v2 校验通过；证书 SHA-256 `51b8f4a1a78f7cb5689601fc762606790c2006b4001658baf5c1480dfc64ff28`，沿用旧版本签名而非 debug key。
- AAB `bundletool validate`、`jarsigner -verify` 退出码均为 0；仍有既有自签名证书、无时间戳和 ZIP/JAR 流校验警告，不能据此宣称已经通过商店审核。

SHA-256：

```text
717327d2a8c7aae035c25f34b3acc2812c211df346a18fd673737b00069af39b  chat-studio-1.0.17-android-release.apk
f4b4d263efa554f9d6f8efa96e4ccec87fee99015cda224668f4aabfa539789b  chat-studio-1.0.17-android-release.aab
```

二进制、签名私钥和本地诊断日志不提交 Git。此次仅本地提交，不代表已推送或执行 GitHub Actions。
