// Thin client for the bot MCP HTTP endpoint — the SAME 3 capabilities the
// bot-chat plugin uses (create/bind room, send, receive), plus unbind. Identity
// and connection config travel in the X-Config header, never in the body, so
// MCP tool semantics never see the bot id / target user / api key.
//
//   bot_bind    {session_id, room_name}      → create room + persist binding[sid]
//   bot_send    {session_id, text}           → send to bound room
//   bot_receive {session_id, since?}         → pull new room messages
//   bot_unbind  {session_id}                 → leave room + drop binding
//   bot_status  {session_id}                 → {bound, room_name}
//
// `session_id` is a CLIENT-chosen opaque handle. acp-chat mints a durable
// `acp-<uuid>` per room (our "room id"): the server persists the binding under
// it, so reusing the same handle after a restart resolves to the SAME room —
// we never rebind (rebind = leave old + create new = a fresh, different room).
import { cfg } from './config.mjs'

const xConfig = () => JSON.stringify({
  botId: cfg.botId,
  targetUserId: cfg.botTargetUserId,
  requireMention: cfg.botRequireMention,
})

async function call(tool, args) {
  const headers = {
    Authorization: `Bearer ${cfg.botApiKey}`,
    'X-Config': xConfig(),
    'Content-Type': 'application/json',
    Accept: 'application/json',
  }
  if (cfg.botOrgId) headers['X-Org-Id'] = cfg.botOrgId
  let res
  try {
    res = await fetch(cfg.botApiUrl, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        jsonrpc: '2.0', id: 1, method: 'tools/call',
        params: { name: tool, arguments: args },
      }),
      signal: AbortSignal.timeout(15_000),
    })
  } catch (e) {
    return { ok: false, reason: 'network', _err: e.message }
  }
  let j
  try { j = await res.json() } catch { return { ok: false, reason: 'parse' } }
  return j.result?.structuredContent
    ?? { ok: false, reason: 'bad_response', raw: j.result?.content?.[0]?.text ?? j.error?.message }
}

export const bot = {
  bind: (sid, roomName) => call('bot_bind', { session_id: sid, room_name: roomName, accept_delivery: true }),
  unbind: sid => call('bot_unbind', { session_id: sid }),
  status: sid => call('bot_status', { session_id: sid }),
  send: (sid, text) => call('bot_send', { session_id: sid, text }),
  receive: (sid, since) => call('bot_receive', since ? { session_id: sid, since } : { session_id: sid }),
}
