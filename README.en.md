# Chat Studio

[中文](README.md)

[![Mobile CI](https://github.com/xpnas/chat-studio/actions/workflows/mobile-ci.yml/badge.svg)](https://github.com/xpnas/chat-studio/actions/workflows/mobile-ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Chat Studio is a Flutter mobile client for interfaces compatible with [Hermes Studio](https://github.com/EKKOLearnAI/hermes-studio). It supports Android and iOS and connects directly to the server through REST and Socket.IO. It is a native Flutter application, not a WebView wrapper.

## Features

- Sign in with Studio credentials, manage multiple servers, switch Profiles, and securely persist sessions.
- Direct chats, group chats, and history with search, pinning, archiving, categories, import, and deletion synchronized with Web.
- Streaming responses, Markdown, collapsible reasoning, stop generation, reconnect/resume, and independent multi-session state.
- Dynamic discovery of server-installed Agents, including Hermes, Ekko, Claude, Codex, Pi, Grok, OpenCode, and DSH where supported by the server.
- Provider-grouped model selection and reasoning-depth settings.
- Image, file, and audio attachments; voice input uses server-side STT and voice playback uses server-side TTS.
- Agent task plans, tool status, approval prompts, and running-state indicators.
- Server workspace browsing, remote file previews, and server-side workspace selection.
- Management screens for Hermes Runtime, Ekko Agent, models, Providers, skills, plugins, MCP, channels, memory, logs, and usage.
- Simplified Chinese and English, with light, dark, and system themes.

Group configuration, Provider credentials, model keys, and server-side Agent installation remain managed by Studio or its Web client. The mobile app does not execute Agent CLIs locally or store model keys.

## Screenshots

<p>
  <img src="docs/screenshots/login.png" width="220" alt="Sign in" />
  <img src="docs/screenshots/chat.png" width="220" alt="Chat" />
  <img src="docs/screenshots/history-tasks.png" width="220" alt="History" />
  <img src="docs/screenshots/agents.png" width="220" alt="Agent picker" />
  <img src="docs/screenshots/models.png" width="220" alt="Model picker" />
  <img src="docs/screenshots/workspace.png" width="220" alt="Server workspace" />
</p>

See the [screenshot catalog](docs/screenshots/README.md) for more views.

## Requirements

- Flutter 3.44.9 or a compatible version
- Dart 3.12 or a compatible version
- Android 7.0 / API 24 or later
- iOS 15.0 or later
- JDK 17 for Android release builds
- macOS, Xcode, and Apple developer credentials for signed iOS builds

## Quick start

```sh
flutter pub get --enforce-lockfile
flutter run
```

Enter the Studio server root, for example:

```text
https://studio.example.com
```

Do not enter an `/api` path or a Web subpath. The server must support REST and Socket.IO WebSocket upgrades. For LAN development, use the computer's LAN address rather than the computer's `localhost` from the phone.

## Build and release

Local builds:

```sh
flutter build apk --release
flutter build appbundle --release
```

APKs can be installed directly; AAB files are intended for store upload. Production Android builds require your own signing material. iOS distribution requires Apple signing configuration.

GitHub Actions provides:

| Workflow | Purpose |
| --- | --- |
| `Mobile CI` | Formatting, static checks, automation, and cross-platform builds |
| `Signed packages` | Manually create signed Android / iOS packages |
| `Branch releases` | Create prerelease packages for non-default branches |
| `Studio contract` | Exercise the protocol against a compatible Studio server |

See [build and release](docs/build-release.md) for details.

## Server requirements

The mobile app connects to a deployed Studio server; it does not include the server. Configure the required Runtime, Provider, model, and permissions in Web before using Hermes, Ekko, or other Agents.

- HTTPS is recommended for public deployments.
- LAN HTTP is intended only for trusted development networks.
- The account must have access to the selected Profile.
- Voice input requires STT configured for the active Profile; TTS alone does not enable voice input.
- Agent availability, history, pinning, archiving, and categories are server-owned and synchronized with other clients.

See [server connection](docs/server-setup.md) and [Agent capabilities](docs/agent-capabilities.md).

## Documentation

- [Documentation index](docs/README.md)
- [Agent catalog and selection](docs/agent-catalog.md)
- [Agent settings and Runtime](docs/agent-runtime-settings.md)
- [Agent capabilities](docs/agent-capabilities.md)
- [Task plans](docs/task-plans.md)
- [Chat commands](docs/chat-composer-commands.md)
- [Server workspace and gestures](docs/workspace-navigation.md)
- [Build and release](docs/build-release.md)
- [Naming and compatibility](docs/naming.md)
- [Privacy and security](PRIVACY.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Repository layout

```text
lib/core/                 address validation and platform policy
lib/data/                 REST, Socket.IO, models, and secure storage
lib/state/                chat, session, and history state
lib/ui/                   login, chat, history, settings, and management
android/  ios/            Android and iOS projects
test/                     automated tests
scripts/                  build and release scripts
docs/                     user and developer documentation
.github/workflows/        GitHub Actions workflows
```

## License and upstream relationship

Chat Studio is an independent third-party client. It is not an official EKKOLearnAI project and has no endorsement. This repository does not include the Hermes Studio server source; interface compatibility does not grant rights to upstream code, trademarks, logos, or other resources.

Original code in this repository is licensed under [Apache License 2.0](LICENSE). Hermes Studio / Hermes Web UI is licensed under the terms declared by the upstream project. Third-party dependencies and assets retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Privacy

The client stores session credentials and application preferences, but not passwords or model keys. Chat data, attachments, tool execution, model calls, and retention are controlled by the connected Studio server and its Provider configuration. See [PRIVACY.md](PRIVACY.md) for details.
