#!/usr/bin/env node
// acp-chat daemon entry point. Long-running: holds one kiro ACP connection,
// multiplexes all rooms, and recovers everything on restart. All logs go to
// stderr / the state-dir log file; stdout stays clean.
import { Daemon } from '../src/daemon.mjs'

const daemon = new Daemon()

async function main() {
  await daemon.start()
}

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    daemon.log(`received ${sig}, shutting down (state is persisted; rerun to recover)`)
    daemon.stop()
    process.exit(0)
  })
}

main().catch(e => {
  console.error(`acp-chat: fatal: ${e.message}`)
  process.exit(1)
})
