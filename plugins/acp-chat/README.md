# acp-chat plugin

Run a **Kiro CLI v3 ACP** agent as a multi-room chat service. One long-lived
daemon holds a single `kiro-cli acp` connection and **multiplexes many IM chat
rooms onto many ACP sessions**. Each room is a live conversation with the agent;
a small set of `/` commands are intercepted for control, and every other `/`
command passes through to the ACP agent unchanged.

It reuses the exact same bot MCP endpoint and credentials as the `bot-chat`
plugin (create room / send / receive), so if you already have `bot-chat`
configured, acp-chat needs no new IM setup.

## What it does

- **Auto-creates a control room on startup** that behaves like a normal
  bot-chat room: talk to the agent, and its replies come back to the room.
- **`/new <path> [name]`** — create a new room + ACP session.
  - `<path>` is the working directory. **Relative** paths resolve against the
    cwd of the room the command was typed in; **absolute** paths are used as-is.
  - `[name]` is the room name (optional). **Empty ⇒ the last path segment** of
    `<path>` (e.g. `/new /home/me/work/api` → room `api`).
- **`/status`** — this room's session state: cwd, ACP session id, whether a turn
  is in flight, and the queued messages (max 5, configurable).
- **`/cancel [n]`** — withdraw buffered messages in this room. No `n` cancels the
  in-flight turn (ACP `session/cancel`) and clears the queue; `n` drops the
  n-th queued message (`1` = next to run).
- **`/stop`** — delete this room's session and its binding (leaves the room).
  Refused in the control room (stop a worker room instead).
- **`/sessions`** — list every room/session the daemon manages.
- **`/help`** — explain all commands.
- **Any other `/command`** (e.g. `/compact`, a steering command) is **passed
  through to that room's ACP session verbatim.**

At most **5** messages may be buffered per room (`ACP_MAX_QUEUE`); the 6th is
rejected with a note until one drains — use `/cancel` to make space.

## Restart recovery (kiro OR the daemon)

Nothing is lost across a restart. Three identifiers are persisted per room in
`state/rooms.json` (atomic writes):

| Identifier | What it is | Why it survives |
|---|---|---|
| `botSid` (`acp-<uuid>`) | our minted **room-id handle** | the bot server persists the room binding keyed by this string; reusing it resolves back to the **same room** (we never rebind — rebind = leave + recreate = a *new* room) |
| `acpSessionId` (`sess_<uuid>`) | kiro's session id | kiro persists it on disk at `~/.kiro/sessions/<sha256(cwd)[:16]>/<sess>/`; reattached via ACP `session/load` |
| `cwd` | the room's working dir | also locates the on-disk session |

On boot the daemon reloads the store, `session/load`s each ACP session,
verifies each bot binding still resolves (re-binding under the **same** handle
only if it vanished), and resumes polling. **Room ids, ACP sessions, and
bindings all persist.** If kiro pruned a session from disk, a fresh ACP session
is minted while keeping the same room + binding.

## Multi-room delivery (server dependency)

acp-chat gives **every room its own `session_id` (`botSid`), its own `cwd`, and
its own ACP session id** — a fully independent triple, never shared. It relies
on the bot server delivering inbound messages **per `session_id`**, so that many
rooms can receive at once.

**Server support: ✅ available.** The AgentX bot server now keeps one live
delivery session **per `(botId, session_id)`** (previously one per `botId`), so
multiple `accept_delivery:true` rooms coexist — a `/new` room no longer takes
over and unbinds earlier rooms. Verified: with two concurrent delivery bindings
A and B on one bot, A stays `bound` after B binds, and A/B receive in isolation.

See [`docs/multi-room-delivery.md`](docs/multi-room-delivery.md) for the exact
constraint, the client contract, and the (now-completed) server change checklist.

## Setup

1. **Log in to kiro** once (any normal use is enough):
   ```bash
   kiro-cli chat 'hi'   # completes the login; acp-chat reuses this session
   ```
2. **Export the bot credentials** (identical to `bot-chat` — share them):
   ```bash
   export BOT_ID="axb_…"                        # /settings/bots
   export BOT_API_KEY="agx_…"                   # /settings/api-keys
   export BOT_TARGET_USER_ID="@you:matrix.example.com"
   # optional: BOT_ORG_ID, BOT_REQUIRE_MENTION
   ```
3. **Start the daemon** — one unified CLI, `scripts/acp.sh`:
   ```bash
   plugins/acp-chat/scripts/acp.sh start          # background, recovers state
   plugins/acp-chat/scripts/acp.sh start --fg     # foreground (logs to terminal)
   plugins/acp-chat/scripts/acp.sh restart        # recycle a running daemon
   plugins/acp-chat/scripts/acp.sh stop           # stop; state preserved
   plugins/acp-chat/scripts/acp.sh status         # daemon pid + persisted rooms
   plugins/acp-chat/scripts/acp.sh stop-all       # CLOSE & EXIT ALL rooms
   plugins/acp-chat/scripts/acp.sh                 # no args → prints help
   ```
   Or from a Claude Code session: `/acp start | stop | restart | status | rooms | stop-all`.

Then open the control room in your IM client and chat, or `/new` more rooms.

**Closing everything:** `stop` only pauses the daemon (rooms survive, recovered
on next `start`). To tear down for real — leave every IM room and clear the
store — use `stop-all` (add `--keep-control` to keep just the control room).

## Configuration (all env vars)

| Env var | Default | Purpose |
|---|---|---|
| `BOT_ID` ✅ | — | bot public id (`axb_…`) |
| `BOT_API_KEY` ✅ | — | AgentX API key (`agx_…`) |
| `BOT_TARGET_USER_ID` | — | room peer (Matrix id / WeChat id) |
| `BOT_REQUIRE_MENTION` | `true` | group-room @-mention filter (inbound) |
| `BOT_ORG_ID` | — | org scope (`X-Org-Id`) |
| `BOT_API_URL` | `https://agentxapi.nx.run/…/McpServer` | bot endpoint |
| `BOT_POLL_MS` | `3000` | inbound poll interval |
| `ACP_KIRO_BIN` | `kiro-cli` | kiro binary |
| `ACP_ENGINE` | `v3` | `--agent-engine` |
| `ACP_MODEL` | `claude-opus-4.6` | initial model |
| `ACP_DEFAULT_CWD` | `$HOME` | control room cwd + base for bare `/new` |
| `ACP_CONTROL_ROOM` | `acp-chat` | control room name |
| `ACP_MAX_QUEUE` | `5` | per-room buffered messages |
| `ACP_STATE_DIR` | `<plugin>/state` | persisted store + logs |
| `ACP_TOKEN_CMD` | — | command that prints the ACP token (see auth) |
| `KIRO_API_KEY` | — | bearer token (auth priority 2) |
| `ACP_SSO_TOKEN_FILE` | `~/.aws/sso/cache/kiro-auth-token.json` | token file (auth priority 3) |

## ACP auth

Kiro v3 ACP launches with `--auth=acp-callback`: the host must answer the
`_kiro/auth/getAccessToken` request with `{ accessToken, expiresAt, profileArn }`
(all three were confirmed required in testing). The daemon resolves the token by
priority:

1. **`ACP_TOKEN_CMD`** — a shell command printing either that JSON object or a
   bare access token. Point it at your own credential source.
2. **`KIRO_API_KEY`** — an env bearer token.
3. **`ACP_SSO_TOKEN_FILE`** — a JSON token file.
4. **Shipped fallback** — `scripts/kiro-token.mjs` reads kiro-cli's own on-disk
   login (`~/.local/share/kiro-cli/data.sqlite3`) and emits the object. This is
   why "log in to kiro once" is all the setup you need.

## Architecture

```
                 ┌──────────── one kiro-cli acp process (stdio, JSON-RPC) ───────────┐
 IM rooms        │  session sess_A ↔ room A (cwd /proj/a)                             │
   ▲  │          │  session sess_B ↔ room B (cwd /proj/b)                             │
   │  │ bot_send │  session sess_ctl ↔ control room                                   │
   │  ▼          └───────────────────────▲───────────────────────────────────────────┘
   │  bot_receive (poll)                 │ session/new · session/load · session/prompt
   │  bot_bind / bot_unbind              │ session/cancel · session/update (stream)
   └────────────── acp-chatd (daemon) ───┘   _kiro/auth/getAccessToken → token-cmd
                        │
                        └─ state/rooms.json  (botSid ↔ acpSessionId ↔ cwd, atomic)
```

Inbound room message → `parse()` → control command handled locally, or
passthrough enqueued → `session/prompt` → streamed `agent_message_chunk`s
accumulate → turn end → `bot_send` the reply back to the room.

## Files

```
.claude-plugin/plugin.json   manifest
package.json                 zero runtime deps (node ≥ 22 for node:sqlite fallback)
bin/acp-chatd.mjs            daemon entry point
src/config.mjs               env-var config + validation
src/bot-client.mjs           bot MCP HTTP client (bind/unbind/status/send/receive)
src/acp-client.mjs           kiro ACP stdio client (multiplexed sessions + auth)
src/store.mjs                durable room store (atomic writes, recovery)
src/commands.mjs             /command parser + /help text
src/daemon.mjs               orchestrator: rooms, queues, poll loop, recovery
commands/acp.md              /acp slash command → scripts/acp.sh
scripts/acp.sh               unified CLI: start|stop|restart|status|rooms|stop-all|help
scripts/kiro-token.mjs       reference ACP_TOKEN_CMD (reuses kiro login)
```
