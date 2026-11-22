# Persistent goals and message organization

Open **More actions → Tasks** for goals across authorized conversations, or **Conversation goals** for the current conversation. Search, status, order and all-authorized-Profile scope are server-backed. Each goal shows its conversation/resource Profile, updated time, source and completion evidence. These goals persist across turns; an ordinary run's task plan remains a separate view. An unavailable interface, denied access and an empty result are distinct states.

Complete, reopen and close use the displayed task's exact `expected_updated_at`. A conflict refreshes the view and requires another explicit action. A lost response is reconciled through reads; the app does not replay a status write. Source/evidence lookup is exact, cancellable and limited to 20 pages. Missing, forbidden and undisplayable targets produce a result rather than opening a nearby message or starting a run.

Long-press a supported message or use **Select messages**. Selection starts with the server's authoritative full grouping. A run can include tools, hidden rows and records on other pages. The confirmation shows group/record counts and hidden records. Compression, summary and unknown-boundary groups remain protected. BOT mixed timelines and unsupported Coding Agents do not use ordinary message deletion routes.

Deletion requires confirmation and submits the original `messageIds` and `historyRevision`. Single-chat IDs/versions are numeric; group IDs/versions are opaque strings. A new run, compression, another client's deletion or revoked access can invalidate a selection. The app never stops work or retries a destructive write with a new revision to bypass that refusal. A lost response requires read-only reconciliation before selecting again.

Deleting a goal's source removes that goal. Deleting completion evidence reopens the goal and clears its evidence. These are server results, not a second set of client cascade rules. Successful deletion refreshes history, run plans and goal/result views, invalidates old async pages and keeps unsent text/files. The reading position returns to valid remaining content or an empty view.

Remote archive preserves content and draft. A removal event triggers list refresh and targeted verification. Only a confirmed missing resource detaches a deleted conversation; a 403 reports lost access, and temporary failures keep the draft. Recoverable drafts stay within their original server/account/Profile and are never sent automatically.

Build-time rollback: `--dart-define=STUDIO_SESSION_TASKS=false` hides goal entries; `--dart-define=STUDIO_MESSAGE_SELECTION=false` disables message selection. Existing chat/run plans continue to work. A client rollback does not delete server goals or restore messages already deleted.
