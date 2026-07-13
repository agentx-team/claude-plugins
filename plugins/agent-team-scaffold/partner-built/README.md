# partner-built

Reserved for **third-party / vendor sub-plugins** — self-contained plugins
authored and versioned by someone else (a tool vendor, a data provider, a
partner team).

This directory is empty by design. It is the extension point: when you integrate
an outside plugin, drop it here as its own self-contained directory:

```
partner-built/
└── <partner-name>/
    ├── .claude-plugin/plugin.json   # partner's own manifest + version + author
    ├── agents/   skills/            # the partner's own components
    └── .mcp.json                    # the partner's data connectors
```

Why a separate top-level dir (not folded into `agents/` or `skills/`): partner
assets are classified by **source/ownership**, which is orthogonal to component
type. Keeping them isolated lets the vendor evolve and version independently
without touching — or being touched by — your core role agents and workflows.
