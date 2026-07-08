# bot-chat plugin

Bind a Claude Code session to an IM chat room: push long-task results to the room, and receive room messages into the session (via a local channel bridge).

## Zero-config install

The plugin ships its own `.mcp.json` (the local `bot-channel` bridge only). **No json edits after install** — everything is environment variables. Bot identity/config travels in the `X-Config` header, invisible to MCP tool semantics (the body carries only `session_id` + tool args; `targetUserId`/`requireMention` remain optional per-call overrides server-side):

| Env var | Required | Default | Sent as |
|---|---|---|---|
| `BOT_ID` | ✅ | — | `X-Config.botId` — the bot's **public id** (`axb_…`), copy it from AgentX `/settings/bots` |
| `BOT_API_KEY` | ✅ | — | `Authorization` header — an AgentX API key (`agx_…`) from `/settings/api-keys` |
| `BOT_TARGET_USER_ID` | for bind | — | `X-Config.targetUserId` (Matrix: `@user:server`; WeChat: the bound `wx_user_id`) |
| `BOT_REQUIRE_MENTION` | no | **`true`** | `X-Config.requireMention` |
| `BOT_ORG_ID` | no | — | `X-Org-Id` header; empty = the bot's own org (Personal org for personal bots) |
| `BOT_API_URL` | no | `https://agentx.nx.run/bots.v1.BotService/McpServer` | — |
| `BOT_POLL_MS` | no | `5000` | — |

Server-side queue semantics: at most **10** pending inbound messages per
binding (overflow is rejected and the room is notified), a room member can
type **`/clear`** at any time to drop the pending queue, and each delivered
message stays re-readable for **≥3s** before it is pruned.

## What it does
- `/bot <room_name>` — create a room and bind this session (auto-unbinds + leaves a previous room). Writes `.claude/.bot-binding.json`, the shared anchor.
- `/bot unbind` — unbind and leave the room.
- `/bot status` — show current binding.
- **Outbound**: on every turn end (`Stop` hook), if bound, the `last_assistant_message` is pushed to the room. Pure shell, zero model tokens; unbound sessions make zero network calls.
- **Inbound**: `bot-channel` (local stdio MCP channel, spawned from the plugin's `.mcp.json`) polls `bot_receive` on the remote endpoint and injects new room messages into the session as `<channel source="bot-channel" ...>` events. `require_mention` filtering happens server-side.

Start the session with the channel enabled (research preview):
```bash
claude --dangerously-load-development-channels server:bot-channel
```

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
hooks/session-start.sh       export BOT_SESSION_ID
hooks/stop.sh                push last_assistant_message if bound
scripts/bot.sh               MCP JSON-RPC curl client (env → body)
scripts/bot-cmd.sh           /bot router: bind / unbind / status
scripts/channel.mjs          inbound poller → channel notifications
docs/bot-api-implementation.md   server-side API spec
```

See `docs/bot-api-implementation.md` for the endpoint contract the server must implement.
