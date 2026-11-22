# Release notes

## 1.0.44 — BOT models and conversation creation

- Change a BOT's model from its composer using the account's authorized Profile/provider catalog, with configuration revision checks and isolated ordinary-chat preferences.
- Add new BOT conversations from the BOT tab; place its new-conversation button and search above the tabs using the ordinary-chat header layout and list spacing.
- Preserve drafts and existing BOT settings; reconcile failed model writes without replaying them, and require checking the list after an uncertain creation.

## 1.0.43 — One reading layout across all chats

- Single, BOT and group conversations now share the complete reading layout and scroll behavior: folding composer, floating reading progress, latest-message button, new-content badge, stop positioning and safe-area spacing.
- Preserve the visible paragraph while new replies arrive; return to latest after the composer and history finish laying out.
- Retain each conversation's own send/stop, mentions, approvals, attachment routes, paging, navigation and draft handling.

## 1.0.42 — Shared chat rendering and live continuation

- BOT conversations now use the ordinary chat's exact message, attachment, audio and history-list widgets, including assistant segment grouping and bottom alignment.
- Keep BOT streaming replies visible as the keyboard and message height change; show peer-device input and completed replies immediately before persisted history refreshes.
- Restore sending in existing legacy conversations whose server session mode is empty, while preserving known global modes and keeping unknown modes read-only.

## 1.0.41 — Shared BOT tab navigation

- Right swipe from BOT chat opens the same conversation drawer as ordinary chat, with BOT selected among the single/group/BOT/history tabs.
- Tab navigation supports switching chat types while retaining each BOT's draft.

## 1.0.40 — BOT swipe directions

- Swipe left for active collaborations and right for the BOT list, matching ordinary chat's list gesture.
- Header buttons open the corresponding panels on the same sides.

## 1.0.39 — BOT navigation and chat layout

- Added a BOT tab beside single/group chat and history tabs.
- Reused ordinary chat input and message styling while keeping BOT configuration and sends isolated.
- Moved active collaborations and background tasks into the right-swipe panel; left swipe opens the BOT list without losing the draft.

## Unreleased — upstream mobile synchronization

- Pinned legacy/stable/preview compatibility manifest and reproducible, counted client contracts.
- Capability-driven Agent discovery, scoped/global model preferences and exact continuation configuration.
- Cross-device observer/read ACKs, remote-removal draft recovery and protected older reading windows.
- Persistent goals, bounded evidence lookup and server-grouped single/group message deletion with task cascades.
- Account-owned BOT conversations, tasks and sequential/parallel collaboration, with a projected mixed timeline and atomic bounded cache. Enabled after joint real Studio and Android emulator acceptance using an approved controlled local model. Real models remain unverified; iOS testing was waived.

See [compatibility and acceptance limits](docs/studio-compatibility.md), [goal/deletion effects](docs/session-goals-and-message-selection.md), and [BOT prerequisites and rollback](docs/bot-conversations.md). These changes are unreleased. Existing upstream attribution remains unchanged.
