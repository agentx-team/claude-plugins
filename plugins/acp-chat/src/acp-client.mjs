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
    const args = [
      'acp',
      '--agent-engine', cfg.engine,
      '--model', cfg.model,
      '--trust-all-tools',
    ]
    this.log(`spawning ${cfg.kiroBin} ${args.join(' ')}`)
    this.proc = spawn(cfg.kiroBin, args, { stdio: ['pipe', 'pipe', 'pipe'] })
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

  stop() {
    if (this.proc) { try { this.proc.kill() } catch {} }
  }
}
