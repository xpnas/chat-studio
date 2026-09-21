# Agent capabilities

The mobile management area mirrors the Web Studio capability entries while keeping editing and navigation native to the phone. Data is read from and written to the active server and Profile.

## Hermes

Hermes capability entries include:

- Tasks: create, edit, pause, resume, run, and delete scheduled tasks.
- Channels: inspect channel status, edit behavior, manage credentials, and use supported QR login flows.
- Skills: browse, enable, pin, edit, and delete skills.
- Plugins: inspect and toggle supported plugins.
- MCP: add, edit, remove, and test external MCP servers.
- Memory: browse and edit supported memory records.

## Ekko

Ekko exposes the capability entries supported by its server module, including skills, MCP servers, and memory records.

## Interaction rules

- Capabilities are opened from the Agent management entry; Runtime and capabilities are not duplicated as separate top-level menus.
- Long JSON, Markdown, and text values use full-screen editors.
- Destructive operations require confirmation.
- Refresh actions update the current capability instead of rebuilding the whole management page.
- Successful writes reload the current server snapshot so Web and other devices see the same state.
- Server authorization remains authoritative. A hidden or unavailable entry cannot be made accessible by the mobile client.
