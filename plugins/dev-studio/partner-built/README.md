# partner-built/

Reserved extension point for third-party / team sub-plugins. Empty by design.

To add one, drop a self-contained directory here — `partner-built/<name>/` — with its own
`.claude-plugin/plugin.json`, its agents/skills, and (if needed) its own `.mcp.json`. Isolation
by ownership lets a contributor version their extension independently of the core studio.

Keep the core invariants: one-level delegation, one writer per surface, nothing applied live, and
the scaffold repo (github.com/aws300/scaffold) as the process spec.
