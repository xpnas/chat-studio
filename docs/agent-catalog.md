# Agent catalog and selection

The picker reads the connected server. Hermes/Ekko always use `/api/agents/availability`. Coding Agents prefer `/api/studio/agents`; only an explicitly missing registry falls back to availability. A successful empty Coding directory remains empty. Authentication, permission and temporary errors never enable a fallback installation guess.

## Supported identities

The app recognizes the built-in Agent and the server identities exposed by the current protocol, including:

- Ekko / built-in Agent
- Hermes
- Claude Code
- Codex
- Pi
- Grok
- OpenCode
- DSH
- Qwen, Kimi, CodeBuddy, Copilot, Cursor, Qoder, Antigravity, and ZCode

Validated plugin descriptors preserve a complete ID such as `plugin:omp/omp`. Plugins need an installed status, a chat surface and a supported mode. Their model route encodes the entire ID as one path segment. The pinned preview contract uses `plugin:mobile-fixture/echo`; it does not prove OMP or arbitrary external plugins were executed.

An Agent is selectable only when the server reports it as installed and the mobile client understands its routing contract. Unknown server entries remain unavailable instead of being silently mapped to another Agent.

## Selection behavior

- The picker displays the server's current installed catalog.
- Agent icons and names follow the server identity contract, with a local fallback when a static icon is unavailable.
- The current selection is placed first in the sheet.
- Refresh and retry request a new availability snapshot.
- Switching a Profile or server invalidates the previous request and clears stale choices.
- Opening an existing conversation preserves the Agent recorded by that conversation; refreshing the catalog does not rewrite history.
- Uninstalled/disabled Agents leave history readable and disable continuation. Unknown identities and modes remain read-only.
- Existing conversation mode is read-only. Start a new conversation to change mode. Cursor/Qoder are global-only; controls follow the validated descriptor.
- Global models come from that Agent's native directory. The empty model ID means the Agent's default; aliases are submitted unchanged even when a concrete name is displayed. Missing saved models remain identifiable instead of silently selecting another model.
- Native discovery distinguishes ready, empty, not installed, authentication required, unsupported, timeout and error. One failed Agent does not erase another Agent's directory.
- Reasoning choices follow model metadata. Provider per-model API modes are recomputed when switching models; cancelling an override preserves the previous value.

`STUDIO_PLUGIN_AGENTS=false` closes plugin routing at build time. See [verified baselines](studio-compatibility.md).

## Server responsibilities

Installation, CLI configuration, Provider credentials, model access, and runtime health are managed on the server. An installed CLI may still require credentials or a working runtime before it can answer a message.
