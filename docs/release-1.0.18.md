# Chat Studio 1.0.18（19）

## 命名重构

- Dart 包统一为 `chatstudio`，同步所有测试与性能测试的 imports；应用/图形组件改为 `ChatStudioApp` / `ChatStudioMark`，主题命名同步更新。
- Android namespace / applicationId 与 iOS Bundle ID 统一为 `ai.chatstudio.app`，Kotlin 路径移至 `android/app/src/main/kotlin/ai/chatstudio/app/MainActivity.kt`，iOS 三套配置及测试 Bundle ID 同步。
- Dart、Kotlin、Swift 的文件导出通道统一为 `ai.chatstudio.app/file_export`；安全存储键、音频/附件临时文件、模型测试夹具、脚本环境变量、签名临时目录及 CI iOS 压缩包名称同步。
- 上游真实 Agent ID、名称、别名与图标集中在 `lib/data/studio_protocol.dart`，保留兼容字面值；作者/许可证归属、上游 URL 与历史记录不伪造性改写。详见 [命名规范](naming.md)。
- 新增源码命名与应用标识门禁，接入 Mobile CI、Studio contract 与 Signed packages；APK 验证脚本增加产物包名/启动 Activity 校验。
- README、隐私说明、构建/测试与截图复现文档同步更新；README 不添加版本迭代列表。

## 安装差异

**新应用身份，不能覆盖安装旧包或读取旧包私有存储。** 安装后重新添加服务器并登录，服务端历史仍在；本地草稿、偏好和服务器列表不自动跨应用迁移。签名证书继续沿用已有材料，无需新建密钥。iOS 需要匹配新 Bundle ID 的 App ID / provisioning profile。

仓库内源码路径已重命名；本地根目录被当前会话/进程占用，Windows 拒绝从旧名移动，未强制结束用户进程。关闭占用程序后可从仓库外运行 `scripts/rename-workspace.ps1`，将当前仓库改为同级 `chatstudio`。脚本已完成 WhatIf、隔离目录实际改名及重复执行验证；本地私钥路径已改成相对路径，具体操作见命名规范。

## 验证

- 命名门禁、Dart 格式、静态分析通过；门禁另外验证 7 种错误命名/通道/包标识会被拒绝。
- **219 项单元/Widget 测试通过，8 项环境跳过**，新增 7 项存储/原生通道/Agent 协议回归。
- **7 项隔离真实 Studio HTTP/Socket.IO 契约通过**，包含实际 socket 断线/恢复、多会话、文件上传、STT / TTS 等；使用本地模型与语音夹具，不使用生产数据或收费模型。
- 截图测试通过，重新生成 14 张实际 Flutter 组件预览；本次重构没有视觉布局变化，图片与此前一致。
- PowerShell 脚本语法检查、Bash 脚本语法检查与 Python 编译检查通过。
- Windows 已构建 Android；没有 Android 真机/模拟器端到端验收，没有运行真实 Codex CLI / Hermes Python runtime。iOS 源码配置已更新，仍需 macOS / Xcode 或 GitHub Runner 验证；未运行远端 Actions。

## Android 产物

- 包名 `ai.chatstudio.app`，启动 Activity `ai.chatstudio.app.MainActivity`，名称 `Chat Studio`，versionName `1.0.18` / versionCode `19`。
- minSdk 24 / targetSdk 36，包含 arm64-v8a / armeabi-v7a / x86_64。
- APK：`dist/chatstudio-1.0.18-android-release.apk`。
- AAB：`dist/chatstudio-1.0.18-android-release.aab`。
- 校验清单：`dist/chatstudio-1.0.18-SHA256SUMS.txt`。
- APK v2 签名校验通过，非 debuggable，含 Dart AOT 且无 debug kernel；签名证书 SHA-256 为 `51b8f4a1a78f7cb5689601fc762606790c2006b4001658baf5c1480dfc64ff28`。
- AAB `bundletool validate` 与 `jarsigner -verify` 退出码均为 0；dump manifest 确认包名/版本正确。仍存在既有自签名证书、无时间戳和 ZIP/JAR 流读取差异警告，不代表通过 Play Console 审核。

SHA-256：

```text
64889392f7de6e616beed10f08f986d27ba87f011db6587812d2dc2bd02e3a62  chatstudio-1.0.18-android-release.apk
890044181c5d3e3e8507e9e236dbbf19732036d8c7d5ece7af0d222f1fb0259b  chatstudio-1.0.18-android-release.aab
```

二进制、私钥、私有诊断和本地 CodeGraph 索引不提交 Git。此次仅本地 Git 提交，不代表已推送远端或已完成商店发布。
