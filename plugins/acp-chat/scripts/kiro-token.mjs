#!/usr/bin/env node
// Reference ACP_TOKEN_CMD: print the host-auth response kiro's ACP mode needs
// (`{accessToken, expiresAt, profileArn}`) from kiro-cli's own on-disk login,
// so acp-chat reuses your existing `kiro-cli` session — no separate login.
//
// kiro v3 ACP launches with --auth=acp-callback and calls the host method
// `_kiro/auth/getAccessToken`; the daemon runs THIS command to answer it. The
// three fields are what kiro validated as required in testing:
//   accessToken  the bearer (auth_kv "kirocli:odic:token".access_token)
//   expiresAt    ISO expiry (…"expires_at") — omitting it → TokenInvalidError
//   profileArn   CodeWhisperer profile (state "api.codewhisperer.profile".arn)
//                — omitting it → "profileArn is required for this request"
//
// Set ACP_KIRO_DB if your kiro data.sqlite3 lives elsewhere.
import { DatabaseSync } from 'node:sqlite'
import { homedir } from 'node:os'
import { join } from 'node:path'

const DB = process.env.ACP_KIRO_DB
  || join(homedir(), '.local/share/kiro-cli/data.sqlite3')

const db = new DatabaseSync(DB, { readOnly: true })
const get = (tbl, key) => {
  const r = db.prepare(`SELECT value FROM ${tbl} WHERE key=?`).get(key)
  if (!r) return null
  let v = r.value
  if (v instanceof Uint8Array) v = Buffer.from(v).toString('utf8')
  try { return JSON.parse(v) } catch { return null }
}

const tok = get('auth_kv', 'kirocli:odic:token')
if (!tok?.access_token) {
  console.error('kiro-token: no access token found — run `kiro-cli` and log in first')
  process.exit(1)
}
const prof = get('state', 'api.codewhisperer.profile')

process.stdout.write(JSON.stringify({
  accessToken: tok.access_token,
  expiresAt: tok.expires_at,
  ...(prof?.arn ? { profileArn: prof.arn } : {}),
}))
