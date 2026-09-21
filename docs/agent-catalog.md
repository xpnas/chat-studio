# Agent catalog and selection

The new-chat Agent picker reads availability from the connected Studio server. It does not use a hard-coded installation list.

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

An Agent is selectable only when the server reports it as installed and the mobile client understands its routing contract. Unknown server entries remain unavailable instead of being silently mapped to another Agent.

## Selection behavior

- The picker displays the server's current installed catalog.
- Agent icons and names follow the server identity contract, with a local fallback when a static icon is unavailable.
- The current selection is placed first in the sheet.
- Refresh and retry request a new availability snapshot.
- Switching a Profile or server invalidates the previous request and clears stale choices.
- Opening an existing conversation preserves the Agent recorded by that conversation; refreshing the catalog does not rewrite history.

## Server responsibilities

Installation, CLI configuration, Provider credentials, model access, and runtime health are managed on the server. An installed CLI may still require credentials or a working runtime before it can answer a message.
