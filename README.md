# Chat Studio

[English](README.en.md)

[![Mobile CI](https://github.com/xpnas/chat-studio/actions/workflows/mobile-ci.yml/badge.svg)](https://github.com/xpnas/chat-studio/actions/workflows/mobile-ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Chat Studio 是一个面向 [Hermes Studio](https://github.com/EKKOLearnAI/hermes-studio) 兼容接口的 Flutter 移动客户端，支持 Android 和 iOS。应用使用原生 Flutter 界面直接连接服务端 REST 与 Socket.IO 接口，不是 WebView 包装。

## 功能

- 使用 Studio 的账号密码登录，支持多服务器、Profile 切换和安全保存会话。
- 支持单聊、群聊和历史记录；历史记录支持搜索、置顶、归档、分类、导入和删除，并与 Web 端同步。
- 支持流式回答、Markdown、思考内容折叠、停止生成、断线恢复和多会话切换。
- 动态读取服务端已安装的 Agent，支持 Hermes、Ekko、Claude、Codex、Pi、Grok、OpenCode 和 DSH 等 Agent 的选择与识别。
- 模型按照 Provider 分组显示，支持模型选择和思考深度设置。
- 支持图片、文件和音频附件；语音输入使用服务端 STT，语音播放使用服务端 TTS。
- 支持 Agent 任务计划、工具状态、审批提示和运行状态展示。
- 支持服务器工作区浏览、远程文件预览和工作目录选择。
- 提供 Hermes Runtime、Ekko Agent、模型、Provider、技能、插件、MCP、频道、记忆、日志和用量等管理入口。
- 支持简体中文和 English，适配浅色、深色及跟随系统主题。

群聊配置、Provider 密钥、模型凭据和服务端 Agent 安装仍由 Studio 服务端或 Web 端负责。移动端不会在手机上执行 Agent CLI，也不会保存模型密钥。

## 界面预览

<p>
  <img src="docs/screenshots/login.png" width="220" alt="登录" />
  <img src="docs/screenshots/chat.png" width="220" alt="聊天" />
  <img src="docs/screenshots/history-tasks.png" width="220" alt="历史记录" />
  <img src="docs/screenshots/agents.png" width="220" alt="Agent 选择" />
  <img src="docs/screenshots/models.png" width="220" alt="模型选择" />
  <img src="docs/screenshots/workspace.png" width="220" alt="服务器工作区" />
</p>

更多图片见 [截图目录](docs/screenshots/README.md)。

## 环境要求

- Flutter 3.44.9 或兼容版本
- Dart 3.12 或兼容版本
- Android 7.0 / API 24 及以上
- iOS 15.0 及以上
- Android Release 构建需要 JDK 17
- iOS 签名构建需要 macOS、Xcode 和 Apple 开发者资料

## 快速开始

```sh
flutter pub get --enforce-lockfile
flutter run
```

启动应用后填写 Studio 服务根地址，例如：

```text
https://studio.example.com
```

不要填写 `/api` 路径或网页子路径。服务端需要支持 REST 和 Socket.IO WebSocket upgrade。局域网调试时使用电脑的局域网 IP，不要在手机上填写电脑服务的 `localhost`。

## 构建与发布

本地构建：

```sh
flutter build apk --release
flutter build appbundle --release
```

APK 可直接安装，AAB 用于应用商店上传。正式 Android 发布需要配置自己的签名材料；iOS 发布需要 Apple 签名配置。

GitHub Actions 提供以下工作流：

| 工作流 | 用途 |
| --- | --- |
| `Mobile CI` | 格式检查、静态分析、自动化检查和跨平台构建 |
| `Signed packages` | 手动生成签名 Android / iOS 包 |
| `Branch releases` | 为非主分支生成预发布 Release 包 |
| `Studio contract` | 与兼容 Studio 服务端进行协议联调 |

详细步骤见 [构建与发布](docs/build-release.md)。

## 服务端要求

移动端连接的是已部署的 Studio 服务，不包含服务端本身。使用 Hermes、Ekko 或其他 Agent 前，请在 Web 端完成对应的 Runtime、Provider、模型和权限配置。

- 公网部署建议使用 HTTPS。
- 局域网 HTTP 仅适合可信网络中的调试环境。
- 当前账号必须具有目标 Profile 的访问权限。
- 语音输入需要在当前 Profile 配置 STT；仅配置 TTS 不会启用语音输入。
- Agent 列表、历史记录、置顶、归档和分类均以服务端数据为准，并与其他设备同步。

参见 [服务端连接](docs/server-setup.md) 和 [Agent 能力管理](docs/agent-capabilities.md)。

## 文档

- [文档索引](docs/README.md)
- [Agent 目录与选择](docs/agent-catalog.md)
- [Agent 设置与 Runtime](docs/agent-runtime-settings.md)
- [Agent 能力管理](docs/agent-capabilities.md)
- [任务计划](docs/task-plans.md)
- [聊天命令](docs/chat-composer-commands.md)
- [服务器工作区与手势](docs/workspace-navigation.md)
- [构建与发布](docs/build-release.md)
- [命名与兼容边界](docs/naming.md)
- [隐私与安全](PRIVACY.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

## 项目结构

```text
lib/core/                 地址校验和平台策略
lib/data/                 REST、Socket.IO、数据模型和安全存储
lib/state/                会话、聊天和历史状态
lib/ui/                   登录、聊天、历史、设置和管理界面
android/  ios/            Android 与 iOS 工程
test/                     自动化测试
scripts/                  构建和发布脚本
docs/                     用户与开发文档
.github/workflows/        GitHub Actions 工作流
```

## 许可证与上游关系

Chat Studio 是独立的第三方客户端，不是 EKKOLearnAI 官方项目，也未获得其背书。本仓库不包含 Hermes Studio 服务端源码；兼容其接口不代表获得上游代码、商标、Logo 或其他资源的授权。

本仓库原创代码采用 [Apache License 2.0](LICENSE)。Hermes Studio / Hermes Web UI 按上游项目所声明的许可证发布。第三方依赖和资源遵循各自许可证，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 隐私

客户端保存登录会话和应用偏好，不保存密码或模型密钥。聊天、附件、工具执行、模型调用和数据保留由所连接的 Studio 服务端及其 Provider 配置决定。完整说明见 [PRIVACY.md](PRIVACY.md)。
