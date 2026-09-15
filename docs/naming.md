# Chat Studio 命名与兼容边界

## 客户端命名

- 显示名称：**Chat Studio**。
- Dart 包、工作目录建议名、缓存及测试文件前缀：`chatstudio`。
- Dart 组件：`ChatStudioApp`、`ChatStudioMark`；主题：`chatstudioTheme`、`chatstudioGreen`。
- Android namespace / applicationId 与 iOS Bundle ID：`ai.chatstudio.app`。
- Kotlin 源码：`android/app/src/main/kotlin/ai/chatstudio/app/MainActivity.kt`。
- iOS 测试 target：`ai.chatstudio.app.RunnerTests`。
- 原生文件保存通道：`ai.chatstudio.app/file_export`（Dart / Kotlin / Swift 必须一致）。
- 安全存储：`chatstudio.session.v1`、`chatstudio.servers.v1`、`chatstudio.choice.v1.<scope>`、`chatstudio.device.v1`。
- 自测环境变量：`CHATSTUDIO_TEST_*`、`CHATSTUDIO_KEEP_CONTRACT_STATE`；截图字体：`CHATSTUDIO_PREVIEW_FONT`。
- 本地签名文件：`.local/signing/chatstudio-upload.jks`；CI 临时签名目录与 iOS 压缩产物也使用 `chatstudio` 前缀。

## 必须保留的外部值

客户端重命名不等于重命名服务端。`lib/data/studio_protocol.dart` 集中保存上游内置 Agent 的真实 ID `ekko-agent`、旧别名、显示名称和 `ekko-agent.png` 图标文件名。这些值参与创建会话、恢复历史和请求服务端 Agent 图标，不能替换为客户端名称。测试保留独立的字面值断言，以免错误重命名同时修改实现与期望而漏检。

上游仓库 `EKKOLearnAI/hermes-studio` 的 URL、工作流 checkout、法律声明与作者归属仍保持真实名称；`docs/analysis/` 是上游源码分析证据，`docs/release-*.md` 是历史版本记录，其旧包名、文件名、哈希和签名信息不追溯改写。本地已有的历史构建产物、私有诊断日志、Git 历史和证书主体/alias 也不做伪造性替换。新提交的客户端业务代码中，旧名称只允许存在于该协议适配文件。

## 安装与验证

新应用身份拥有独立沙箱，不能覆盖旧版，也无法直接读取旧应用的安全存储。安装后重新添加服务器并登录，服务端历史不变；旧本地草稿/偏好不自动迁移。iOS 发布需要匹配新 Bundle ID 的 provisioning profile；签名私钥继续使用已有材料，不在重命名时生成新密钥。

运行 `python scripts/verify-app-identity.py` 检查源码/路径、包标识、原生通道与存储前缀；CI 质量、Android/iOS 构建和签名流程均执行此门禁。Flutter 回归测试覆盖新存储键读写、文件导出通道和真实服务端协议；签名 APK 验证脚本另外检查产物 applicationId 和启动 Activity。

## 本地仓库根目录

源码目录和 Kotlin 包路径已重命名。若根目录仍为旧名且被编辑器/Codex 会话占用，Windows 会拒绝移动；不要强制结束不明进程或复制后删除原仓库。关闭占用程序后，从仓库外的 PowerShell 运行 `scripts/rename-workspace.ps1`（可先传 `-WhatIf`），脚本仅将当前仓库改名为同级 `chatstudio`，遇到已存在目标立即停止，不覆盖数据。

重新打开新目录后，串行运行 `flutter clean`、`flutter pub get --enforce-lockfile` 和构建，以重新生成包含绝对路径的工具缓存。本地签名文件可使用相对 `android/app` 的 `../../.local/signing/chatstudio-upload.jks`，避免依赖仓库根目录名称；自定义绝对路径需自行检查。
