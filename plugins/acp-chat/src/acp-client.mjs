// ACP client: one long-lived `kiro-cli acp` process, JSON-RPC 2.0 over stdio,
// multiplexing MANY sessions over the single connection (ACP supports this
// natively — session/new returns a sessionId used to tag every later call).
//
// Responsibilities:
//   - spawn kiro-cli acp --agent-engine <v3> --model <…> --trust-all-tools
//   - initialize handshake
//   - answer host-mediated auth: `_kiro/auth/getAccessToken` (token-cmd hook)
//   - auto-approve `session/request_permission` (we run --trust-all-tools, but
//     answer defensively in case a tool still asks)
//   - session/new, session/load (restart recovery), session/prompt, session/cancel
//   - fan session/update stream events to per-session listeners
//
// The daemon layer (daemon.mjs) owns the mapping session ↔ room and turns the
// streamed agent_message chunks into bot_send calls.
import { spawn, execFile } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { cfg } from './config.mjs'

// The kiro ACP launch command is fixed. To change the binary, engine, or model,
// edit these constants directly (no env vars).
//   engine v3 = kiro's newest agent engine (v1/v2/v3; v2 is kiro's own default).
//   claude-sonnet-5 = 1M-context Sonnet 5. Per-session model can still be
//   changed at runtime via ACP session/set_model.
const KIRO_BIN = 'kiro-cli'
const KIRO_ARGS = ['--v3', 'acp', '--agent-engine', 'v3', '--model', 'claude-sonnet-5', '--trust-all-tools']

export class AcpClient {
  constructor({ onUpdate, log = () => {} }) {
    this.onUpdate = onUpdate          // (sessionId, update) => void
    this.log = log
    this.proc = null
    this.buf = ''
    this.nextId = 1
    this.pending = new Map()          // id → {resolve, reject}
    this.ready = null                 // resolves after initialize
  }

  start() {
    const args = KIRO_ARGS
    this.log(`spawning ${KIRO_BIN} ${args.join(' ')}`)
    // detached:true puts kiro in its OWN process group, so we can signal the
    // whole tree at shutdown. kiro-cli is a launcher that spawns the real ACP
    // server as a child; a plain proc.kill() would hit only the launcher and
    // leave that child orphaned (the `ps aux | grep kiro` survivor). Killing
    // the process group (-pid) reaps the launcher AND its children.
    this.proc = spawn(KIRO_BIN, args, { stdio: ['pipe', 'pipe', 'pipe'], detached: true })
    this.proc.stdout.on('data', d => this._onData(d))
    this.proc.stderr.on('data', d => {
      const s = d.toString()
      if (/error|token|auth|fail/i.test(s)) this.log(`kiro: ${s.trim().slice(0, 200)}`)
    })
    this.proc.on('exit', code => {
      this.log(`kiro acp exited (code=${code})`)
      for (const { reject } of this.pending.values()) reject(new Error('acp process exited'))
      this.pending.clear()
      this.proc = null
    })

    this.ready = this._request('initialize', {
      protocolVersion: 1,
      clientCapabilities: { fs: { readTextFile: true, writeTextFile: true } },
    })
    return this.ready
  }

  get alive() { return !!this.proc }

  get pid() { return this.proc?.pid ?? null }

  _send(obj) {
    if (!this.proc) throw new Error('acp not running')
    this.proc.stdin.write(JSON.stringify(obj) + '\n')
  }

  _request(method, params) {
    const id = this.nextId++
    const p = new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }))
    this._send({ jsonrpc: '2.0', id, method, params })
    return p
  }

  _respond(id, result) { this._send({ jsonrpc: '2.0', id, result }) }

  _onData(d) {
    this.buf += d
    let i
    while ((i = this.buf.indexOf('\n')) >= 0) {
      const line = this.buf.slice(0, i).trim()
      this.buf = this.buf.slice(i + 1)
      if (!line) continue
      let m
      try { m = JSON.parse(line) } catch { continue }
      this._dispatch(m)
    }
  }

  _dispatch(m) {
    // Response to one of our requests.
    if (m.id !== undefined && (m.result !== undefined || m.error !== undefined) && !m.method) {
      const p = this.pending.get(m.id)
      if (!p) return
      this.pending.delete(m.id)
      if (m.error) p.reject(new Error(m.error.message || 'acp error'))
      else p.resolve(m.result)
      return
    }
    // Requests FROM the agent that the host must answer.
    if (m.method === '_kiro/auth/getAccessToken') {
      this._answerAuth(m.id)
      return
    }
    if (m.method === 'session/request_permission') {
      const opt = m.params?.options?.find(o => /allow|accept|yes/i.test(o.optionId || o.name || ''))
        || m.params?.options?.[0]
      this._respond(m.id, { outcome: { outcome: 'selected', optionId: opt?.optionId || 'allow' } })
      return
    }
    if (m.method === 'fs/read_text_file') {
      readFile(m.params.path, 'utf8')
        .then(t => this._respond(m.id, { content: t }))
        .catch(() => this._respond(m.id, { content: '' }))
      return
    }
    // Streamed notifications.
    if (m.method === 'session/update') {
      const sid = m.params?.sessionId
      if (sid) this.onUpdate(sid, m.params.update, m.params)
      return
    }
  }

  async _answerAuth(id) {
    try {
      const token = await this._resolveToken()
      // Provider expects at least { accessToken }. profileArn is optional and
      // derived by kiro when present in the token file.
      this._respond(id, typeof token === 'string' ? { accessToken: token } : token)
    } catch (e) {
      this.log(`auth callback failed: ${e.message}`)
      this._respond(id, {})   // empty → kiro surfaces TokenInvalidError; we log it
    }
  }

  // Token resolution priority:
  //   ACP_TOKEN_CMD → KIRO_API_KEY → SSO token file → shipped kiro-token.mjs.
  // kiro's provider needs { accessToken, expiresAt, profileArn } — an object
  // response carries all three; a bare string is accepted as the access token.
  async _resolveToken() {
    if (cfg.tokenCmd) return this._runTokenCmd(cfg.tokenCmd)
    if (cfg.kiroApiKey) return cfg.kiroApiKey
    try {
      const j = JSON.parse(await readFile(cfg.ssoTokenFile, 'utf8'))
      return {
        accessToken: j.accessToken ?? j.access_token,
        ...(j.expiresAt ?? j.expires_at ? { expiresAt: j.expiresAt ?? j.expires_at } : {}),
        ...(j.profileArn ? { profileArn: j.profileArn } : {}),
      }
    } catch {
      // Final fallback: reuse kiro-cli's own on-disk login.
      return this._runTokenCmd(cfg.defaultTokenCmd)
    }
  }

  _runTokenCmd(cmd) {
    return new Promise((resolve, reject) => {
      execFile('bash', ['-lc', cmd], { timeout: 15_000 }, (err, stdout) => {
        if (err) return reject(err)
        const out = stdout.trim()
        try { resolve(JSON.parse(out)) }   // full JSON { accessToken, expiresAt, profileArn }…
        catch { resolve(out) }             // …or a bare access token string
      })
    })
  }

  // ── session operations ─────────────────────────────────────────────────
  async newSession(cwd) {
    await this.ready
    const r = await this._request('session/new', { cwd, mcpServers: [] })
    return r.sessionId
  }

  // Restart recovery: reattach to a session kiro persisted on disk.
  async loadSession(sessionId, cwd) {
    await this.ready
    return this._request('session/load', { sessionId, cwd, mcpServers: [] })
  }

  prompt(sessionId, text) {
    // Fire-and-forget at the RPC layer: the turn's content arrives as
    // session/update stream events; the result resolves at turn end.
    return this._request('session/prompt', {
      sessionId,
      prompt: [{ type: 'text', text }],
    })
  }

  cancel(sessionId) {
    return this._request('session/cancel', { sessionId }).catch(() => {})
  }

  // Terminate kiro AND its child ACP server, resolving only once the process
  // has actually exited (or we've SIGKILLed it). Awaiting this before the
  // daemon calls process.exit() is what prevents orphaned `kiro-cli acp`
  // processes surviving a stop.
  stop() {
    const proc = this.proc
    if (!proc) return Promise.resolve()
    const pid = proc.pid
    const signalGroup = (sig) => {
      // Negative pid → the whole process group (created via detached:true).
      try { process.kill(-pid, sig) } catch { try { proc.kill(sig) } catch {} }
    }
    return new Promise(resolve => {
      let done = false
      const finish = () => { if (!done) { done = true; clearTimeout(t); resolve() } }
      proc.once('exit', finish)
      signalGroup('SIGTERM')
      // Escalate to SIGKILL if it hasn't exited within the grace window.
      const t = setTimeout(() => { signalGroup('SIGKILL'); setTimeout(finish, 500) }, 3000)
    })
  }
}
