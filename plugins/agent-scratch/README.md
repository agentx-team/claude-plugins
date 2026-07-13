# agent-scratch

**Start-from-scratch session utilities** for Claude Code, packaged as a plugin
named **`scratch`**. Modeled on the layout conventions of
[`agent-team-scaffold`](../agent-team-scaffold): plugin manifest in
`.claude-plugin/`, thin markdown commands, `${CLAUDE_PLUGIN_ROOT}` hooks.

## How to use

### 1. Install the plugin

Add the AgentX marketplace (once) and install:

```bash
claude plugin marketplace add agentx-team/claude-plugins
claude plugin install scratch@agentx-plugins
```

Or, working from a local checkout:

```bash
claude plugin marketplace add /path/to/claude-plugins   # repo root (the marketplace)
claude plugin install scratch@agentx-plugins
```

Requirements: bash + `git` + `python3` (stdlib only). No Node, no credentials.
The plugin is **read-only toward `~/.claude`** — it scans, never writes.

### 2. Use it

```
/scratch:fresh                              # rescan ~/.claude, orient in the cwd
/scratch:fresh https://github.com/me/api    # clone into ./projects/api, then orient there
/scratch:takeover ~/work/old-project        # absorb history + mv into ./projects/old-project
```

A `SessionStart` hook also injects a brief capability snapshot at every session
start; if you'd rather opt in per-session, disable the hook and use the
commands directly.

Two capabilities, both of which **always rescan `~/.claude/skills` and
`~/.claude/plugins` first** so the session knows every capability available:

| Command | What it does |
|---|---|
| `/scratch:fresh` | Start a new session with full awareness of `~/.claude` — skills, plugins, user agents/commands, MCP servers — **clone the target git project into `./projects/<name>`**, then orient there. |
| `/scratch:takeover <dir>` | Find another directory's Claude session, absorb its conversation history into the current context, **`mv` all its files into `./projects/<name>`**, and continue the work from there. |

> **Workspace convention:** both commands keep work under a `./projects/`
> subdirectory — `fresh` clones into `./projects/<repo>` and `takeover` moves the
> source into `./projects/<name>` — so the cwd root stays clean and multiple
> projects can coexist. `./projects/` is git-ignored.

---

## Feature 1 — `/scratch:fresh`

Bootstraps a session and clones the target project into `./projects/`:

1. Runs `scripts/scan-claude-home.sh`, which enumerates (read-only):
   - `~/.claude/skills/*/SKILL.md` — every user skill with its description
   - `~/.claude/plugins/installed_plugins.json` — installed plugins + versions
   - `~/.claude/agents/*.md` · `~/.claude/commands/*.md` — user-level agents/commands
   - `~/.claude/settings.json → mcpServers` — user-registered MCP servers
2. **Clones the target git project into `./projects/<repo>`** (`git clone <url>
   ./projects/$(basename <url> .git)`) and `cd`s into it — never the cwd root.
   If no repo is named, it skips cloning and orients in the current directory.
3. Reads any skill/agent relevant to your stated goal so it can be invoked correctly.
4. Orients in the working directory (`git status`, `CLAUDE.md`/`AGENT.md`/`README.md`).
5. Reports what's available and starts on your goal (or asks for one).

A `SessionStart` hook also injects a **brief** version of the same inventory at
every session start, so even without running the command the session begins
knowing what skills and plugins exist.

## Feature 2 — `/scratch:takeover <source-dir>`

Migrates a project — history **and** files — into the current directory:

- **Step 0 · rescan** — same `~/.claude` scan as Feature 1, so the continued
  work can use every installed skill/plugin.
- **Step A · absorb the session** — `scripts/find-session.sh <dir>` locates the
  source directory's transcripts under `~/.claude/projects/<encoded-path>/*.jsonl`
  (the absolute path with non-alphanumerics replaced by `-`), newest first.
  `scripts/extract-session.py` then distills the newest transcript into a
  readable digest — user prompts, assistant conclusions, tools touched — capped
  at a context-friendly size (oldest turns elided first). Claude reads the
  digest so the prior conversation becomes part of the current context.
- **Step B · move the files** — after a preview and one confirmation
  (`AskUserQuestion`), the whole source directory (files, dotfiles, and its own
  `.git`) is moved into `./projects/<name>` via `mv src ./projects/$(basename
  src)`, and all paths from the old session are re-anchored under
  `./projects/<name>/`.
- **Step C · fallback** — if no session transcript exists, context is built
  from the project's own docs instead, tried in order:
  **`CLAUDE.md` → `AGENT.md` → `README.md`**, supplemented by `git log` and a
  scan of the tree.

It finishes by reporting where the history came from, the state of the work,
and the next action — then continues that work from the current directory.

---

## Directory structure

```
agent-scratch/
├── .claude-plugin/
│   └── plugin.json            ★ plugin manifest — name: "scratch", commands + hooks
├── commands/
│   ├── fresh.md               /scratch:fresh — rescan ~/.claude + orient here
│   └── takeover.md            /scratch:takeover — absorb session + mv files + continue
├── scripts/                   deterministic helpers the commands call
│   ├── scan-claude-home.sh    inventory of skills/plugins/agents/commands/MCP (read-only)
│   ├── find-session.sh        dir → ~/.claude/projects/<encoded>/ transcript paths, newest first
│   └── extract-session.py     transcript .jsonl → conversation digest (stdlib only)
└── hooks/
    ├── hooks.json             SessionStart → brief capability snapshot
    └── session-start.sh
```

**Design notes** (inherited from agent-team-scaffold):

- **Markdown commands stay thin; scripts do the deterministic work.** Path
  encoding, JSONL parsing, and inventory walking are exact, testable shell/Python;
  the `.md` files only orchestrate and interpret.
- **Standard plugin layout, no `.claude/` directory.** All hook paths go through
  `${CLAUDE_PLUGIN_ROOT}` (with a `dirname`-based fallback so the scripts also run
  straight from a checkout).
- **Read-only toward `~/.claude`.** Both features scan the Claude home; neither
  ever writes to it. The only destructive action — moving the source directory —
  is previewed and explicitly confirmed.

## Standalone scripts

The helper scripts also work without the plugin:

```bash
bash scripts/scan-claude-home.sh [--brief]
bash scripts/find-session.sh ~/work/old-project
python3 scripts/extract-session.py <session.jsonl> [--max-chars 60000] [--full]
```
