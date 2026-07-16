// acp-chat daemon: binds N chat rooms to N kiro ACP sessions over ONE kiro
// process, and interprets a small set of control commands per room.
//
// Data flow per room:
//   room msg ──bot_receive poll──► parse() ──┬─ control cmd → handled locally
//                                            └─ passthrough → enqueue → pump
//   pump: session/prompt ──► session/update stream ──► accumulate agent text
//         ──► turn_end ──► bot_send(accumulated) back to the room
//
// Restart recovery (kiro OR daemon restart): on boot we reload the store and,
// for every persisted room, session/load its durable ACP session and resume
// polling the same botSid (which the bot server still has bound). Nothing is
// re-created, so room ids / ACP sessions / bindings are all preserved.
import { appendFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { cfg, assertConfigured } from './config.mjs'
import { bot } from './bot-client.mjs'
import { store } from './store.mjs'
import { AcpClient } from './acp-client.mjs'
import { parse, parseNew, HELP } from './commands.mjs'

const now = () => new Date().toISOString()

export class Daemon {
  constructor() {
    // Runtime state keyed by ACP sessionId and by botSid.
    this.rooms = new Map()          // botSid → runtime room {queue, busy, accum, ...}
    this.bySession = new Map()      // acpSessionId → botSid
    this.acp = new AcpClient({
      onUpdate: (sid, update) => this._onUpdate(sid, update),
      log: msg => this.log(msg),
    })
    this._pollTimer = null
  }

  log(msg) {
    mkdirSync(cfg.stateDir, { recursive: true })
    try { appendFileSync(join(cfg.stateDir, 'daemon.log'), `${now()} ${msg}\n`) } catch {}
  }

  async start() {
    assertConfigured()
    this.log('daemon starting')
    await this.acp.start()
    this.log('acp initialized')
    await this._recover()
    if (!store.isControl()) await this._createRoom({ cwd: cfg.defaultCwd, roomName: cfg.controlRoomName, control: true })
    this._pollTimer = setInterval(() => this._pollAll().catch(e => this.log(`poll error: ${e.message}`)), cfg.pollMs)
    this.log(`polling every ${cfg.pollMs}ms; ${this.rooms.size} room(s) active`)
  }

  // ── recovery ─────────────────────────────────────────────────────────────
  async _recover() {
    const persisted = store.reload()
    for (const r of persisted) {
      const rt = this._track(r)
      if (r.acpSessionId) {
        try {
          await this.acp.loadSession(r.acpSessionId, r.cwd)
          this.bySession.set(r.acpSessionId, r.botSid)
          this.log(`recovered room ${r.roomName} (${r.botSid}) → ${r.acpSessionId}`)
        } catch (e) {
          // Session gone from disk (e.g. pruned) → mint a fresh one, keep the room+binding.
          this.log(`load failed for ${r.acpSessionId}: ${e.message}; creating new session`)
          const sid = await this.acp.newSession(r.cwd)
          store.setAcpSession(r.botSid, sid)
          this.bySession.set(sid, r.botSid)
        }
      }
      // Verify the bot binding still resolves; if not, re-bind under the SAME
      // botSid so the handle (our "room id") is preserved.
      const st = await bot.status(r.botSid)
      if (!st?.bound) {
        this.log(`binding missing for ${r.roomName}; re-binding under same handle`)
        await bot.bind(r.botSid, r.roomName)
      }
    }
  }

  _track(r) {
    // queue = PENDING messages only. inflight = the message whose turn is
    // currently running (null when idle). Keeping them separate makes /status
    // and /cancel n indices refer purely to pending items.
    const rt = { ...r, queue: [], inflight: null, busy: false, accum: '' }
    this.rooms.set(r.botSid, rt)
    if (r.acpSessionId) this.bySession.set(r.acpSessionId, r.botSid)
    return rt
  }

  // ── room lifecycle ─────────────────────────────────────────────────────
  async _createRoom({ cwd, roomName, control = false }) {
    // Ensure the working directory exists. kiro's session/new silently accepts
    // a non-existent cwd (no error, no mkdir), which would leave the agent
    // pointed at a phantom dir where every file/shell op fails. Create it up
    // front so `/new <path>` means "set this workspace up", as users expect.
    try { mkdirSync(cwd, { recursive: true }) }
    catch (e) { throw new Error(`cannot create working dir ${cwd}: ${e.message}`) }
    const rec = store.create({ roomName, cwd, control })
    store.stampCreated(rec.botSid, now())
    const b = await bot.bind(rec.botSid, roomName)
    if (!b?.ok) {
      store.remove(rec.botSid)
      throw new Error(`bind failed: ${b?.reason || 'unknown'}`)
    }
    const sid = await this.acp.newSession(cwd)
    store.setAcpSession(rec.botSid, sid)
    const rt = this._track({ ...rec, acpSessionId: sid })
    this.log(`created room ${roomName} (${rec.botSid}) cwd=${cwd} session=${sid}`)
    return rt
  }

  async _deleteRoom(rt) {
    if (rt.acpSessionId) { await this.acp.cancel(rt.acpSessionId); this.bySession.delete(rt.acpSessionId) }
    await bot.unbind(rt.botSid)
    store.remove(rt.botSid)
    this.rooms.delete(rt.botSid)
    this.log(`deleted room ${rt.roomName} (${rt.botSid})`)
  }

  // ── polling ──────────────────────────────────────────────────────────────
  async _pollAll() {
    for (const rt of [...this.rooms.values()]) {
      let r
      try { r = await bot.receive(rt.botSid, rt.since) }
      catch (e) { this.log(`receive failed for ${rt.roomName}: ${e.message}`); continue }
      if (r?.next_since) { rt.since = r.next_since; store.setSince(rt.botSid, r.next_since) }
      for (const m of (r?.messages || [])) await this._onMessage(rt, m.text)
    }
  }

  // ── message handling ─────────────────────────────────────────────────────
  async _onMessage(rt, text) {
    const intent = parse(text)
    if (intent.kind === 'cmd') return this._handleCmd(rt, intent)
    // passthrough → enqueue
    if (rt.queue.length >= cfg.maxQueue) {
      return bot.send(rt.botSid, `⚠️ queue full (${cfg.maxQueue}). Use /cancel to drop one, or wait.`)
    }
    rt.queue.push(intent.text)
    this._pump(rt)
  }

  async _handleCmd(rt, { name, args }) {
    try {
      if (name === 'help') return void bot.send(rt.botSid, HELP)
      if (name === 'status') return void bot.send(rt.botSid, this._statusText(rt))
      if (name === 'sessions') return void bot.send(rt.botSid, this._sessionsText())
      if (name === 'new') {
        const p = parseNew(args, rt.cwd)
        if (p.error) return void bot.send(rt.botSid, p.error)
        const nr = await this._createRoom({ cwd: p.cwd, roomName: p.roomName })
        return void bot.send(rt.botSid, `✅ created room "${nr.roomName}" (cwd ${p.cwd}). Talk to it in that room.`)
      }
      if (name === 'cancel') return void this._handleCancel(rt, args)
      if (name === 'stop') {
        if (rt.control) return void bot.send(rt.botSid, '⚠️ refusing to /stop the control room. Use /stop in a worker room.')
        await bot.send(rt.botSid, `🛑 stopping room "${rt.roomName}" — session and binding deleted.`)
        return void this._deleteRoom(rt)
      }
    } catch (e) {
      this.log(`cmd ${name} error: ${e.message}`)
      bot.send(rt.botSid, `error running /${name}: ${e.message}`)
    }
  }

  _handleCancel(rt, args) {
    const n = parseInt(args, 10)
    if (Number.isInteger(n) && n >= 1) {
      // Drop the n-th PENDING message (1 = next to run). The in-flight turn is
      // never touched by a numbered cancel — use bare /cancel for that.
      const idx = n - 1
      if (idx < rt.queue.length) {
        const [dropped] = rt.queue.splice(idx, 1)
        return void bot.send(rt.botSid, `↩️ dropped queued #${n}: "${dropped.slice(0, 60)}"`)
      }
      return void bot.send(rt.botSid, `no queued message #${n} (${rt.queue.length} pending).`)
    }
    // No/invalid n → cancel in-flight turn + clear the whole pending queue.
    const cleared = rt.queue.length
    rt.queue = []
    const wasBusy = rt.busy
    if (wasBusy && rt.acpSessionId) this.acp.cancel(rt.acpSessionId)
    bot.send(rt.botSid, `↩️ cancelled in-flight turn${wasBusy ? '' : ' (none running)'} and cleared ${cleared} pending.`)
  }

  // ── prompt pump: one turn at a time per room ──────────────────────────────
  async _pump(rt) {
    if (rt.busy || !rt.queue.length) return
    rt.busy = true
    rt.accum = ''
    rt.inflight = rt.queue.shift()   // dequeue now → pending indices stay clean
    try {
      await this.acp.prompt(rt.acpSessionId, rt.inflight)
    } catch (e) {
      this.log(`prompt failed in ${rt.roomName}: ${e.message}`)
      bot.send(rt.botSid, `⚠️ turn failed: ${e.message}`)
    } finally {
      rt.inflight = null
      rt.busy = false
      this._flush(rt)
      if (rt.queue.length) this._pump(rt)
    }
  }

  _flush(rt) {
    const out = rt.accum.trim()
    rt.accum = ''
    if (out) bot.send(rt.botSid, out)
  }

  // ── ACP stream → accumulate agent text per room ───────────────────────────
  _onUpdate(sessionId, update) {
    const botSid = this.bySession.get(sessionId)
    if (!botSid) return
    const rt = this.rooms.get(botSid)
    if (!rt) return
    const u = update || {}
    if (u.sessionUpdate === 'agent_message_chunk' && u.content?.type === 'text') {
      rt.accum += u.content.text
    }
    // turn boundaries are handled by the prompt() promise resolving; we only
    // need the text chunks here. (kiro also emits tool_call / thought chunks
    // which we intentionally do not relay to keep rooms readable.)
  }

  _statusText(rt) {
    return [
      `room "${rt.roomName}"${rt.control ? ' (control)' : ''}`,
      `cwd: ${rt.cwd}`,
      `acp session: ${rt.acpSessionId || '(none)'}`,
      `state: ${rt.busy ? '1 in-flight' : 'idle'}, ${rt.queue.length} pending (max ${cfg.maxQueue})`,
      ...(rt.inflight ? [`  ▶ running: ${rt.inflight.slice(0, 60)}`] : []),
      ...rt.queue.map((q, i) => `  #${i + 1}: ${q.slice(0, 60)}`),
    ].join('\n')
  }

  _sessionsText() {
    const lines = [...this.rooms.values()].map(rt =>
      `- "${rt.roomName}"${rt.control ? ' [control]' : ''}  ${rt.busy ? '●' : '○'} q=${rt.queue.length}  ${rt.cwd}`)
    return `acp-chat rooms (${lines.length}):\n${lines.join('\n')}`
  }

  stop() {
    if (this._pollTimer) clearInterval(this._pollTimer)
    this.acp.stop()
  }
}
