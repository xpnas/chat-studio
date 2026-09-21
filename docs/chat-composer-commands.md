# Chat composer and commands

The composer keeps model, reasoning depth, attachments, voice input, and send controls together while preserving room for the conversation.

## Slash commands

Type `/` at the beginning of an empty command prefix to open the server-provided command suggestions. Suggestions can be filtered by command name or description and selected with a tap, Enter, Tab, or the arrow keys. Selecting a command fills the draft; it is not sent until the user submits the message.

Skills and bundles are loaded for the active Profile. If the Profile or conversation changes while a selector is open, the stale result is discarded.

## Attachments and voice

Images and files are selected through native platform pickers and remain local until the user sends them. Voice input requires the active Profile to have a usable server STT provider. Server TTS audio can be played as an audio attachment; ordinary text replies are not automatically converted to speech.

## Context

When the composer is empty, the upper-right context indicator can show server-reported usage, model limit, and remaining capacity. It remains visible while typing when the context data is available.
