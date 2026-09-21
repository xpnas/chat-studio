# Naming and compatibility

## Application identity

- Display name: **Chat Studio**
- Dart package: `chatstudio`
- Android namespace and application ID: `ai.chatstudio.app`
- iOS bundle identifier: `ai.chatstudio.app`
- Native channel names use the `ai.chatstudio.app` prefix.

The application identity is intentionally separate from older Ekko Mobile builds. Installing Chat Studio may require a new login and server entry; server-side conversation history is unaffected.

## External protocol values

The following values are part of the server contract and must not be renamed only for display:

- Agent IDs such as `ekko-agent`, `hermes`, `codex`, `claude-code`, `pi`, `grok`, `opencode`, and `dsh`;
- REST paths and Socket.IO event names;
- server Profile names;
- persisted conversation source and Agent identifiers.

User-facing labels and local implementation names may use Chat Studio branding while preserving these external values.
