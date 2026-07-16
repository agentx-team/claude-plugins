// Command router. Every inbound room message is classified here:
//   - a control command we intercept (/new /status /cancel /stop /help /sessions)
//   - any other "/foo …"  → PASSTHROUGH to that room's ACP session verbatim
//   - plain text          → PASSTHROUGH (a normal prompt)
//
// Intercepted commands act on the ROOM they were typed in (per-room scope).
// `/new` is the exception: it creates a brand-new room+session.
import { resolve, isAbsolute, basename } from 'node:path'

export const HELP = `acp-chat commands (type in any room):

/new <path> [name]   Create a new room + ACP session.
                     <path>  working dir (relative → resolved against THIS
                             room's cwd; absolute used as-is). Created with
                             mkdir -p if it does not exist.
                     [name]  room name (optional). Empty → the last path
                             segment of <path>.
/status              This room's session state + queued/in-flight messages.
/cancel [n]          Cancel queued messages in THIS room. No n → cancel the
                     in-flight turn (ACP session/cancel) + clear the queue.
                     n → drop the n-th queued message (1 = next to run).
/stop                Delete THIS room's session and its binding (leaves room).
/sessions            List all rooms/sessions this daemon manages.
/help                Show this message.

Any other /command is passed through to the ACP agent unchanged.
At most 5 messages may be buffered per room (configurable); the 6th is
rejected until one drains — use /cancel to make space.`

// Parse a raw message into an intent. Returns:
//   {kind:'passthrough', text}
//   {kind:'cmd', name, args}
export function parse(text) {
  const t = (text || '').trim()
  if (!t.startsWith('/')) return { kind: 'passthrough', text: t }
  const sp = t.indexOf(' ')
  const name = (sp === -1 ? t : t.slice(0, sp)).slice(1).toLowerCase()
  const rest = sp === -1 ? '' : t.slice(sp + 1).trim()
  const INTERCEPT = new Set(['new', 'status', 'cancel', 'stop', 'help', 'sessions'])
  if (!INTERCEPT.has(name)) return { kind: 'passthrough', text: t }
  return { kind: 'cmd', name, args: rest }
}

// Parse `/new <path> [name]`. Path may be quoted to contain spaces.
export function parseNew(args, baseCwd) {
  let path, name
  const m = args.match(/^"([^"]+)"\s*(.*)$/) || args.match(/^'([^']+)'\s*(.*)$/)
  if (m) { path = m[1]; name = m[2].trim() }
  else {
    const sp = args.indexOf(' ')
    if (sp === -1) { path = args.trim(); name = '' }
    else { path = args.slice(0, sp).trim(); name = args.slice(sp + 1).trim() }
  }
  if (!path) return { error: 'usage: /new <path> [name]' }
  const cwd = isAbsolute(path) ? path : resolve(baseCwd, path)
  const roomName = name || basename(cwd) || 'room'
  return { cwd, roomName }
}
