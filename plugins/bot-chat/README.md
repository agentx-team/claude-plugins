# bot-chat plugin

Bind a Claude Code session to an IM chat room: push long-task results to the room, and receive room messages into the session (via a local channel bridge).

## How to use

### 1. Install the plugin

Add the AgentX marketplace (once) and install:

```bash
claude plugin marketplace add agentx-team/claude-plugins
claude plugin install bot-chat@agentx-plugins
```

### 2. Get your credentials from AgentX and export them

Three values are needed (all from the AgentX web console):

1. **`BOT_ID`** — open **Settings → Bots** (`/settings/bots`). If you don't
   have a bot yet, click **Add Bot** and connect one (Matrix and WeChat are
   recommended; WeChat binds via QR scan). Each bot row shows its public id
   (`axb_…`) next to the status dot — click it to copy.
2. **`BOT_API_KEY`** — open **Settings → API Keys** (`/settings/api-keys`)
   and create a key (`agx_…`). The plaintext is shown **once**; copy it.
   The key must belong to the same organization as the bot (for a personal
   bot: any key you create in your Personal org).
3. **`BOT_TARGET_USER_ID`** — who the bot should pull into the room on bind:
   - Matrix: your Matrix user id, e.g. `@you:matrix.example.com`
   - WeChat: the bound WeChat user id (`wx_user_id` in the bot's config)

Add them to your `~/.bashrc` / `~/.zshrc` (or your shell profile of choice):

```bash
export BOT_ID="axb_…"                          # from /settings/bots
export BOT_API_KEY="agx_…"                     # from /settings/api-keys
export BOT_TARGET_USER_ID="@you:matrix.example.com"
# optional:
# export BOT_ORG_ID="…"          # org scope; empty = the bot's own org
# export BOT_REQUIRE_MENTION=false  # group rooms: queue ALL messages, not just @mentions
```

Open a new terminal (or `source ~/.bashrc`) so Claude Code sessions inherit them.

### 3. Start Claude Code with the inbound channel enabled

Room replies reach the session through a **channel** (research preview), so
start Claude Code with:

```bash
claude --dangerously-load-development-channels server:bot-channel
```

The id after `server:` is the MCP server name declared in the plugin's
`.mcp.json` (`mcpServers` key) — for this plugin it is `bot-channel`. Without
this flag the plugin is outbound-only: results are still pushed to the room,
but room replies are not injected back into the session.

**Dependencies**: no manual `npm install` needed. The channel is launched via
`scripts/channel.sh`, which installs the single npm dependency
(`@modelcontextprotocol/sdk`) into the plugin directory automatically on
first run — you just need `node` and `npm` on your PATH. The `/bot` command
and the Stop hook are pure shell (`curl` + `jq`) and need no Node at all.

### 4. Bind a room and go

In the session:

```
/bot-chat:bot                  # bind this session (room named after the cwd), start posting
/bot-chat:bot my-task-room     # …or bind with an explicit room name
/bot-chat:bot status           # check the binding
/bot-chat:bot stop             # stop posting from this session (alias: unbind)
```

From then on, every completed turn's final answer is pushed to the room
automatically (Stop hook, zero model tokens). Reply in the room to talk back;
type `/clear` in the room to drop the pending message queue.

## Global room mode — one room for ALL sessions on a machine

Set **`BOT_GLOBAL_ROOM_NAME`** so that when you run `/bot`, the session posts
into a single **shared** Matrix room instead of a per-session room:

```bash
export BOT_GLOBAL_ROOM_NAME="Claude Box"
```

Global mode changes only **which room** `/bot` binds to — **not when posting
starts**. `/bot` is still an explicit, per-session opt-in: a session posts only
after you run `/bot` in it, and stops when you run `/bot stop`. Sessions where
you never ran `/bot` post nothing. Nothing is bound and no context is injected
until you run `/bot`.

- **`/bot`** — opt this session in; its turn results now post to the shared
  room. The shared room is created/bound once and reused by every opted-in
  session.
- **`/bot stop`** (or `/bot unbind`) — opt THIS session out. Other opted-in
  sessions keep posting; the shared room is left intact.
- **`/bot status`** — whether this session is opted in.
- **Deterministic room per host**: the shared session id is derived as
  `gbl-<sha256(room name + this host's private LAN IP)>`, so every session on
  the same machine resolves to the same room and different machines never
  collide. The room is named after `BOT_GLOBAL_ROOM_NAME`.
- **Per-session label**: since many sessions share one room, each message is
  prefixed with the session's working-directory leaf so you can tell them
  apart, e.g. a turn from `/home/core/Documents/tmp/bot` arrives as:
  ```
  bot:
  <the assistant's reply>
  ```
  (Claude Code exposes no human session name to hooks; the cwd leaf is the
  closest stable identifier.)
- **Outbound only**: inbound `bot_receive` is disabled in this mode (a shared
  room has no single session to reply into), so it works even on third-party
  model providers (Bedrock/Vertex) where the inbound channel is unavailable.
- Leave `BOT_GLOBAL_ROOM_NAME` unset for the normal per-session behavior above.

## Configuration reference

The plugin ships its own `.mcp.json` (the local `bot-channel` bridge only). **No json edits after install** — everything is environment variables. Bot identity/config travels in the `X-Config` header, invisible to MCP tool semantics (the body carries only `session_id` + tool args; `targetUserId`/`requireMention` remain optional per-call overrides server-side):

| Env var | Required | Default | Sent as |
|---|---|---|---|
| `BOT_ID` | ✅ | — | `X-Config.botId` — the bot's **public id** (`axb_…`), copy it from AgentX `/settings/bots` |
| `BOT_API_KEY` | ✅ | — | `Authorization` header — an AgentX API key (`agx_…`) from `/settings/api-keys` |
| `BOT_TARGET_USER_ID` | for bind | — | `X-Config.targetUserId` (Matrix: `@user:server`; WeChat: the bound `wx_user_id`) |
| `BOT_REQUIRE_MENTION` | no | **`true`** | `X-Config.requireMention` |
| `BOT_ORG_ID` | no | — | `X-Org-Id` header; empty = the bot's own org (Personal org for personal bots) |
| `BOT_GLOBAL_ROOM_NAME` | no | — | Enables **global room mode** (see above): all host sessions → one room named this; inbound disabled |
| `BOT_API_URL` | no | `https://agentx.nx.run/bots.v1.BotService/McpServer` | — |
| `BOT_POLL_MS` | no | `5000` | — |

Server-side queue semantics: at most **10** pending inbound messages per
binding (overflow is rejected and the room is notified), a room member can
type **`/clear`** at any time to drop the pending queue, and each delivered
message stays re-readable for **≥3s** before it is pruned.

## What it does
- `/bot [room_name]` — bind this session and start posting (no name ⇒ the room is named after the working-directory leaf; auto-unbinds a previous room). Writes `.claude/.bot-binding.json`, the shared anchor.
- `/bot stop` (alias `unbind`) — stop posting from this session / leave the room.
- `/bot status` — show current binding.
- **Outbound**: on every turn end (`Stop` hook), if bound, the `last_assistant_message` is pushed to the room. Pure shell, zero model tokens; unbound sessions make zero network calls.
- **Inbound**: `bot-channel` (local stdio MCP channel, spawned from the plugin's `.mcp.json`) polls `bot_receive` on the remote endpoint and injects new room messages into the session as `<channel source="bot-channel" ...>` events. `require_mention` filtering happens server-side. Requires the special startup flag from step 3 above.

## Architecture
```
                    ┌────────────── outbound (shell, 0 tokens) ──────────────┐
/bot cmd, Stop hook ─ curl ─► https://agentx.nx.run/bots.v1.BotService/McpServer ─► IM room
                                        ▲ bot_receive (poll)
bot-channel (stdio, .mcp.json) ─────────┘
        │ notifications/claude/channel
        ▼
Claude Code session  ── reply is just the next turn's answer ─► Stop hook pushes it back
```
Inbound and outbound share one loop: a room message arrives → Claude handles it → its final answer is pushed back by the Stop hook. No reply tool schema needed in context.

## Files
```
.claude-plugin/plugin.json   manifest
.mcp.json                    bot-channel bridge (ships with plugin, no edits)
commands/bot.md              /bot slash command (! injection → bot-cmd.sh)
hooks/hooks.json             SessionStart + Stop wiring
hooks/session-start.sh       export BOT_SESSION_ID (inert until /bot)
hooks/stop.sh                push last_assistant_message if opted in
scripts/global-id.sh         per-host global session id + per-session opt-in (global mode)
scripts/bot.sh               MCP JSON-RPC curl client (env → body)
scripts/bot-cmd.sh           /bot router: bind / unbind / status
scripts/channel.sh           channel launcher (auto npm-install on first run)
scripts/channel.mjs          inbound poller → channel notifications
docs/bot-api-implementation.md   server-side API spec
```

See `docs/bot-api-implementation.md` for the endpoint contract the server must implement.
