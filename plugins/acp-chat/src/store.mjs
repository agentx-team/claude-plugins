// Durable store for acp-chat. This is the file that makes "survive a restart of
// kiro OR the daemon" work: it records, for every room, the three identifiers
// that must NOT be lost —
//
//   botSid        our minted "room id" handle (acp-<uuid>). The bot server
//                 persists the room binding under this key; reusing it after a
//                 restart resolves back to the SAME room (no rebind).
//   acpSessionId  kiro's durable session id (sess_<uuid>). Reloadable from disk
//                 via ACP session/load, so the conversation itself survives.
//   cwd           working directory (also where kiro persisted the session on
//                 disk: ~/.kiro/sessions/<sha256(cwd)[:16]>/<acpSessionId>/).
//
// Writes are atomic (tmp + rename) so a crash mid-write never corrupts state.
import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'
import { cfg } from './config.mjs'

const FILE = join(cfg.stateDir, 'rooms.json')
const SCHEMA = 1

function load() {
  try {
    const j = JSON.parse(readFileSync(FILE, 'utf8'))
    if (j.schema !== SCHEMA || !Array.isArray(j.rooms)) return { schema: SCHEMA, rooms: [] }
    return j
  } catch { return { schema: SCHEMA, rooms: [] } }
}

let state = load()

function persist() {
  mkdirSync(cfg.stateDir, { recursive: true })
  const tmp = FILE + '.tmp'
  writeFileSync(tmp, JSON.stringify(state, null, 2))
  renameSync(tmp, FILE)
}

export const store = {
  all: () => state.rooms.slice(),
  get: botSid => state.rooms.find(r => r.botSid === botSid) || null,
  isControl: () => state.rooms.find(r => r.control) || null,

  // Create a new room record. botSid is minted here — this is the durable
  // "room id". The ACP session id is filled in once kiro creates the session.
  create({ roomName, cwd, control = false }) {
    const room = {
      botSid: `acp-${randomUUID()}`,
      roomName,
      cwd,
      control,
      acpSessionId: null,   // set by setAcpSession once session/new returns
      since: null,          // bot_receive cursor
      createdAt: null,      // stamped by the caller (Date.now unavailable here)
    }
    state.rooms.push(room)
    persist()
    return room
  },

  setAcpSession(botSid, acpSessionId) {
    const r = store.get(botSid)
    if (r) { r.acpSessionId = acpSessionId; persist() }
    return r
  },
  setSince(botSid, since) {
    const r = store.get(botSid)
    if (r && since && r.since !== since) { r.since = since; persist() }
  },
  stampCreated(botSid, ts) {
    const r = store.get(botSid)
    if (r && !r.createdAt) { r.createdAt = ts; persist() }
  },
  remove(botSid) {
    state.rooms = state.rooms.filter(r => r.botSid !== botSid)
    persist()
  },
  reload() { state = load(); return state.rooms.slice() },
  fileExists: () => existsSync(FILE),
  filePath: () => FILE,
}
