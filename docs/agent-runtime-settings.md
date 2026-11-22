# Agent settings and Runtime

The mobile management area groups Runtime and Agent capabilities under the corresponding Agent entry. Changes are saved to the active Studio server and Profile; the phone does not maintain a separate configuration database.

## Hermes

Hermes settings include runtime behavior, memory, sessions, gateway behavior, tools, skills, MCP, channels, plugins, and related management entries exposed by the server. Runtime versions can be listed, downloaded, activated, or removed when the server grants access.

## Ekko

Ekko settings include model routing, tools, modules, memory, skills, MCP, and advanced runtime options. Settings are edited in native grouped forms and applied explicitly with Save.

## Profiles and servers

Settings are scoped to the selected server and Profile. Switching either one reloads the relevant data and prevents responses from an earlier scope from overwriting the current screen.

## Chat context

The composer can show the context usage reported by the server, including used tokens, the model limit, and remaining capacity. The value is informational and depends on the selected model and server runtime.

New-chat execution choices are separate for each server/account/Profile/Agent/mode. Migration keeps legacy scoped preferences and never overwrites a newer slot. Credentials are excluded. Global requests retain the native model selector and omit scoped Provider/API overrides. Existing conversations keep their mode; model/reasoning changes are locked during work and only become visible after the server accepts them. Conflicts or permission failures retain the prior effective configuration.

## Permissions

Management routes are protected by the server. The app displays the server response when the current account or Profile cannot read or change a setting. Provider keys and other secrets are sent to the server only when a user explicitly saves a form; they are not stored in the mobile app.
