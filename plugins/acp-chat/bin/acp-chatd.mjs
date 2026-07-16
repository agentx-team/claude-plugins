#!/usr/bin/env node
// acp-chat daemon entry point. Long-running: holds one kiro ACP connection,
// multiplexes all rooms, and recovers everything on restart. All logs go to
// stderr / the state-dir log file; stdout stays clean.
import { Daemon } from '../src/daemon.mjs'

const daemon = new Daemon()

async function main() {
  await daemon.start()
}

let shuttingDown = false
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    if (shuttingDown) return   // ignore repeat signals while we drain
    shuttingDown = true
    daemon.log(`received ${sig}, shutting down (state is persisted; rerun to recover)`)
    // Await full teardown (kiro + children exit) BEFORE exiting, so stop never
    // leaves an orphaned kiro-cli acp process behind.
    try { await daemon.stop() } catch {}
    process.exit(0)
  })
}

main().catch(e => {
  console.error(`acp-chat: fatal: ${e.message}`)
  process.exit(1)
})
