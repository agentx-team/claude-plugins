// Central config for the acp-chat daemon. All configuration is environment
// variables — nothing enters a model context, and no JSON edits are needed
// after install. The bot identity/config (BOT_*) matches the bot-chat plugin
// exactly, so the two share credentials; ACP_* configure the kiro ACP bridge.
import { homedir } from 'node:os'
import { join } from 'node:path'

const HOME = homedir()

export const cfg = {
  // ── bot MCP HTTP endpoint (identical semantics to bot-chat) ──────────────
  botApiUrl: process.env.BOT_API_URL || 'https://agentxapi.nx.run/bots.v1.BotService/McpServer',
  botId: process.env.BOT_ID || '',
  botApiKey: process.env.BOT_API_KEY || '',
  botTargetUserId: process.env.BOT_TARGET_USER_ID || '',
  botRequireMention: (process.env.BOT_REQUIRE_MENTION ?? 'true') !== 'false',
  botOrgId: process.env.BOT_ORG_ID || '',
  pollMs: Number(process.env.BOT_POLL_MS || 3000),

  // ── kiro ACP bridge ──────────────────────────────────────────────────────
  kiroBin: process.env.ACP_KIRO_BIN || 'kiro-cli',
  engine: process.env.ACP_ENGINE || 'v3',
  model: process.env.ACP_MODEL || 'claude-opus-4.6',
  // Base directory used for the control room and for resolving relative /new
  // paths that are not typed inside another room.
  defaultCwd: process.env.ACP_DEFAULT_CWD || HOME,
  controlRoomName: process.env.ACP_CONTROL_ROOM || 'acp-chat',
  maxQueue: Number(process.env.ACP_MAX_QUEUE || 5),

  // ── ACP auth (host-mediated `_kiro/auth/getAccessToken`) ─────────────────
  // Resolution priority (see acp-client._resolveToken):
  //   ACP_TOKEN_CMD → KIRO_API_KEY → SSO token file → shipped kiro-token.mjs.
  // The shipped fallback reuses kiro-cli's own on-disk login, so once you've
  // run `kiro-cli` and logged in, acp-chat authenticates with no extra setup.
  tokenCmd: process.env.ACP_TOKEN_CMD || '',
  defaultTokenCmd: `node "${join(process.env.CLAUDE_PLUGIN_ROOT || join(HOME, '.acp-chat'), 'scripts/kiro-token.mjs')}"`,
  kiroApiKey: process.env.KIRO_API_KEY || '',
  ssoTokenFile: process.env.ACP_SSO_TOKEN_FILE
    || join(HOME, '.aws/sso/cache/kiro-auth-token.json'),

  // ── persistence ──────────────────────────────────────────────────────────
  stateDir: process.env.ACP_STATE_DIR
    || join(process.env.CLAUDE_PLUGIN_ROOT || join(HOME, '.acp-chat'), 'state'),
}

export function assertConfigured() {
  const missing = ['botId', 'botApiKey'].filter(k => !cfg[k])
  if (missing.length) {
    const names = missing.map(k => (k === 'botId' ? 'BOT_ID' : 'BOT_API_KEY'))
    // stderr only — never leak config into any prompt-visible surface.
    console.error(`acp-chat: missing env: ${names.join(', ')} — refusing to start`)
    process.exit(1)
  }
}
