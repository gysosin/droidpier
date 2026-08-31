# Architecture

DroidPier consists of a Flutter desktop, shared Dart packages, native texture
bridges, a Kotlin Android companion, and a Java shell agent deployed through ADB.

| Layer | Responsibility |
| --- | --- |
| `apps/desktop` | Desktop presentation, bootstrap, host clipboard, platform runners |
| `packages/open_dex_api` | Immutable state, typed commands and public facade |
| `packages/open_dex_core` | Device/session lifecycle, window orchestration, recovery |
| `packages/open_dex_protocol` | Versioned envelopes and authenticated loopback servers |
| `plugins/open_dex_platform` | ADB, deployment, scrcpy transport, decoder processes |
| `plugins/open_dex_texture` | Native Flutter texture registration and frame statistics |
| `android/companion` | Status, permissions, notifications and media state |
| `android/agent` | Restricted device commands running through authorized ADB |

The UI consumes `OpenDexFacade`; it does not open sockets or start device processes.
The Linux beta retains the embedded scrcpy recording/FFmpeg/texture pipeline.
Windows/macOS use the direct scrcpy transport only after native validation.

Protocol v1 envelopes carry `v`, `id`, `type`, `timestamp`, and `data`. Session
credentials are generated in memory, sent through authorized ADB and used to
protect loopback connections. Unknown message types are ignored. The agent uses
device port 3698 and the companion uses 3699 through session-owned ADB mappings.

The companion advertises `sessionDisconnect: true` in `companion.hello`; a compatible
desktop responds with `companion.welcome`. The companion sends
`companion.disconnect.request` only after negotiation; the desktop replies with
`companion.disconnect.ack` correlated by `replyTo`, then closes windows, processes,
services, and its mappings. Explicit disconnect is not a transport failure and
must not trigger recovery. Older peers continue without this optional capability.

Public branding is DroidPier. Existing internal `open_dex_*` identifiers,
Android application IDs, protocol names, and environment variables are retained
for compatibility. `version.properties` is the release version authority.
