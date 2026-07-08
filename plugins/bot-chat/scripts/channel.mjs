#!/usr/bin/env node
// bot-channel: local stdio MCP channel that bridges the remote bot HTTP MCP
// into this Claude Code session. Inbound only — outbound stays on the Stop
// hook / /bot command, so no extra tool schemas enter the context.
//
// Config comes ONLY from environment variables (same set as scripts/bot.sh);
// bot identity/config travels in the X-Config header, invisible to MCP tool
// semantics. The body carries only session_id/since.
// The active binding (session_id + room) is read from .claude/.bot-binding.json,
// written by /bot. No binding file → poller idles.
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = process.env.CLAUDE_PROJECT_DIR || process.cwd()
const URL = process.env.BOT_API_URL || 'https://agentx.nx.run/bots.v1.BotService/McpServer'
const POLL_MS = Number(process.env.BOT_POLL_MS || 5000)

// Validate config at initialization. Failing here surfaces as a server
// connection error in /mcp (stderr → debug log) and costs zero context —
// config/env details must never reach prompt-visible text.
const missing = ['BOT_ID', 'BOT_API_KEY'].filter(k => !process.env[k])
if (missing.length) {
  console.error(`bot-channel: missing env: ${missing.join(', ')} — refusing to start`)
  process.exit(1)
}

const XCONFIG = JSON.stringify({
  botId: process.env.BOT_ID,
  targetUserId: process.env.BOT_TARGET_USER_ID || '',
  requireMention: (process.env.BOT_REQUIRE_MENTION ?? 'true') !== 'false',
})

function binding() {
  try { return JSON.parse(readFileSync(join(ROOT, '.claude/.bot-binding.json'), 'utf8')) }
  catch { return null }
}

async function callBot(tool, args) {
  const headers = {
    Authorization: `Bearer ${process.env.BOT_API_KEY || ''}`,
    'X-Config': XCONFIG,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  }
  if (process.env.BOT_ORG_ID) headers['X-Org-Id'] = process.env.BOT_ORG_ID
  const res = await fetch(URL, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      jsonrpc: '2.0', id: 1, method: 'tools/call',
      params: { name: tool, arguments: args },
    }),
    signal: AbortSignal.timeout(10_000),
  })
  const j = await res.json()
  return j.result?.structuredContent ?? null
}

const mcp = new Server(
  { name: 'bot-channel', version: '1.0.0' },
  {
    capabilities: { experimental: { 'claude/channel': {} } },
    // Prompt-visible text: describe message handling only. No env vars, no
    // headers, no endpoint/config vocabulary.
    instructions:
      'Messages from the bound IM room arrive as <channel source="bot-channel" from="...">. ' +
      'Handle them as user requests. Your final answer is pushed back to the room automatically — do not try to reply through a tool.',
  },
)
await mcp.connect(new StdioServerTransport())

let since = null
async function tick() {
  const b = binding()
  if (!b?.session_id) return
  let r
  try { r = await callBot('bot_receive', { session_id: b.session_id, ...(since ? { since } : {}) }) }
  catch (e) { console.error(`bot-channel: poll failed: ${e.message}`); return }
  if (!r?.messages?.length) { if (r?.next_since) since = r.next_since; return }
  since = r.next_since ?? since
  for (const m of r.messages) {
    await mcp.notification({
      method: 'notifications/claude/channel',
      params: {
        content: m.text,
        meta: { from: String(m.from ?? ''), msg_id: String(m.id ?? '') },
      },
    })
  }
}
setInterval(tick, POLL_MS)
console.error(`bot-channel: polling every ${POLL_MS}ms`)
