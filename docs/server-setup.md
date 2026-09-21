# Server connection

Chat Studio is a client for an existing Hermes Studio-compatible server. The server, database, Agent runtimes, Provider credentials, and model configuration are outside this repository.

## Connect an existing Studio

1. Enter the Studio root URL in the app, without `/api` or a Web subpath.
2. Use a Studio account with access to the target Profile.
3. Configure at least one usable model in Web before starting a chat.
4. Install and configure Hermes or other coding Agents on the server when needed.
5. Ensure the reverse proxy forwards both REST requests and `/socket.io/` WebSocket upgrades.

Use HTTPS for public deployments. For LAN development, use the computer's LAN address and enable the app's LAN HTTP option only on a trusted network. `localhost` and `127.0.0.1` refer to the phone when entered on a physical device.

## Runtime and voice

Hermes requires a working server-side Hermes Runtime. The built-in Ekko engine does not require that Runtime. Voice input requires STT configured for the active Profile; TTS alone provides playback but does not enable transcription.

## Security

Change default server credentials before exposing a deployment. Store Provider credentials and Agent configuration on the server. Do not put passwords, JWTs, API keys, keystores, or provisioning profiles in the repository or in issue reports.

## Server API compatibility

The mobile client uses the regular Web authentication flow and the server's Profile-aware REST and Socket.IO contracts. Keep the app and server on compatible releases when adding new Agent, history, group-chat, or management features.
