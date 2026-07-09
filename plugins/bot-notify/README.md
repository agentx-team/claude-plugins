# bot-notify plugin

Push Claude Code notifications — turn-end results and human-in-the-loop
alerts — to a **single shared** IM chat room (Matrix / WeChat via an AgentX
bot). Outbound only: no inbound polling, no channel, no Node.js, no
`.mcp.json`. Every network call is a plain `curl` from a hook or the `/bot`
command; nothing here ever costs a model token.

This is a stripped-down sibling of [`bot-chat`](../bot-chat): it keeps only
bot-chat's "global/shared room" mode and drops per-session rooms, inbound
message delivery, and the local MCP channel bridge that used to require
Node.js.

## How to use

### 1. Install the plugin

If you haven't added this marketplace yet:

```bash
claude plugin marketplace add agentx-team/claude-plugins
claude plugin install bot-notify@agentx-plugins
```

If you already have the `agentx-plugins` marketplace added (e.g. you already
use `bot-chat`), refresh its manifest first so Claude Code picks up the new
`bot-notify` entry, then install:

```bash
claude plugin marketplace update agentx-plugins
claude plugin install bot-notify@agentx-plugins
```

Both commands work the same inside an interactive session via `/plugin`:

```
/plugin marketplace update agentx-plugins
/plugin install bot-notify@agentx-plugins
```

Verify it's enabled:

```bash
claude plugin list
```

If the plugin was already installed and you're picking up a newer version
from the marketplace, update it instead of reinstalling:

```bash
claude plugin update bot-notify@agentx-plugins
```

### 2. Get your credentials from AgentX and export them

Same three values as bot-chat (all from the AgentX web console):

```bash
export BOT_ID="axb_…"                          # /settings/bots
export BOT_API_KEY="agx_…"                     # /settings/api-keys
export BOT_TARGET_USER_ID="@you:matrix.example.com"
# optional:
# export BOT_ROOM_NAME="Claude Box"   # default: "Claude Code"
# export BOT_ORG_ID="…"               # org scope; empty = the bot's own org
```

Open a new terminal (or `source` your shell profile) so Claude Code sessions
inherit them. Unlike bot-chat there is no `BOT_REQUIRE_MENTION` — this
plugin never reads room replies, so mention-filtering is irrelevant.

### 3. Bind a session and go

```
/bot-notify:bot                # opt this session in — its results now post to the shared room
/bot-notify:bot status          # check whether this session is opted in
/bot-notify:bot stop            # opt this session out (alias: unbind)
```

No `--dangerously-load-development-channels` flag needed — there is nothing
to receive.

## How it works

- **One room for everyone**: the shared room is identified server-side by
  `(bot, BOT_TARGET_USER_ID)` with an **empty** session id, so every host and
  every session using the same bot resolves to the same room. Binding again
  just reuses it (renaming it if `BOT_ROOM_NAME` changed) — it's never
  duplicated.
- **`/bot-notify:bot` is a per-session opt-in**: nothing posts from a session
  until it runs this command. Opt-in state is a local marker file keyed by
  the real session id (`~/.cache/bot-notify/optin/<session_id>`), so
  `/bot-notify:bot stop` only affects the session that runs it — other
  opted-in sessions and the shared room itself are untouched.
- **Per-session label**: since many sessions share one room, every message is
  prefixed with the session's working-directory leaf, e.g. a turn from
  `/home/core/Documents/tmp/bot` arrives as:
  ```
  bot:
  <the assistant's reply>
  ```
- **Outbound only, bound `accept_delivery=false`**: the plugin never polls
  for replies, so it works identically on any model provider (including
  Bedrock/Vertex) — there's no inbound channel to be unavailable. Replies
  typed in the room are routed to the AgentX agent, not back into any local
  session.
- **Two kinds of pushes**: the `Stop` hook posts the final answer of every
  turn; the `Notification` hook posts a `⚠️ …` alert when Claude needs input
  mid-task (permission prompt, idle wait, MCP form) — same opt-in gating,
  same room, same cwd-leaf label.

## What was removed vs. bot-chat, and why

| bot-chat had | bot-notify | why |
|---|---|---|
| `.mcp.json` + `scripts/channel.sh` + `scripts/channel.mjs` (Node.js, `@modelcontextprotocol/sdk`, polling loop) | *(none)* | No inbound message delivery is in scope, so there is nothing to bridge into the session and no reason to run any MCP server, local or remote. Declaring a remote HTTP MCP entry instead was considered, but a connected MCP server always publishes its tool schemas into every session's context (a real, non-zero token cost) even if hooks never call it as a tool — so for an outbound-only plugin, no `.mcp.json` at all is strictly better than a "type: http" one. |
| `package.json` (npm dependency) | *(none)* | Follows from the above — nothing to install. |
| Per-session rooms (`/bot [room_name]`, `.claude/.bot-binding.json`) | *(none — shared room only)* | Out of scope per the simplified requirement. |
| `BOT_GLOBAL_ROOM_NAME` toggle + dual code paths (default mode vs. global mode) | Always shared room | Only one mode exists, so the branching logic collapses. |
| `scripts/global-id.sh`'s LAN-IP + SHA-256 host hashing | `scripts/optin.sh` (opt-in bookkeeping only) | Reviewing bot-chat's code: the hashed "global session id" was only ever used as a boolean ("is global mode on?") — the actual `bot_bind`/`bot_send` calls always pass an **empty** session id for the shared room. Cross-host de-duplication is achieved entirely server-side via `(bot, targetUserId)`. The IP-hashing was dead weight for that purpose, so it's dropped; only the per-session opt-in marker logic is kept. |
| `BOT_REQUIRE_MENTION` / `requireMention` in `X-Config` | *(removed)* | Only affects inbound `bot_receive` filtering, which this plugin never calls. |

## Files

```
.claude-plugin/plugin.json   manifest
commands/bot.md              /bot slash command (! injection → bot-cmd.sh)
hooks/hooks.json              SessionStart + Stop + Notification wiring
hooks/session-start.sh        export BOT_SESSION_ID (inert until /bot)
hooks/stop.sh                  push last_assistant_message if opted in
hooks/notify.sh                forward "needs your input" notifications if opted in
scripts/optin.sh                per-session opt-in marker helpers
scripts/bot.sh                  MCP JSON-RPC curl client (env → body), outbound only
scripts/bot-cmd.sh              /bot router: bind / stop / status
```

See [`bot-chat/docs/bot-api-implementation.md`](../bot-chat/docs/bot-api-implementation.md)
for the server-side endpoint contract this plugin's `scripts/bot.sh` talks to
(`bot_bind` / `bot_unbind` / `bot_send`; `bot_status`/`bot_receive` are
unused by this plugin).
