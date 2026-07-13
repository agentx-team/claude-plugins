---
description: Start fresh — rescan ~/.claude (skills, plugins, agents, commands, MCP), clone the target git project into ./projects/<name>, and report every Claude capability available to this session
argument-hint: "[git URL to clone, and/or what you plan to work on next]"
allowed-tools: Bash, Read, Glob, Grep
---

# Fresh Start

Bootstrap this session with a full picture of the user's Claude configuration
and a freshly-cloned project to work in. Run the inventory scan, clone the
target project under `./projects/`, absorb the result, then confirm readiness.

## Steps

1. **Rescan `~/.claude`** — run the bundled scanner:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/scan-claude-home.sh"
   ```

   It enumerates, read-only:
   - `~/.claude/skills/*/SKILL.md` — every user-level skill, with its description
   - `~/.claude/plugins/installed_plugins.json` — installed plugins and versions
   - `~/.claude/agents/*.md` and `~/.claude/commands/*.md` — user-level agents / commands
   - `~/.claude/settings.json → mcpServers` — user-registered MCP servers

2. **Clone the target project into `./projects/<name>`.** If `$ARGUMENTS`
   contains a git URL (or the user names a repo to work on), clone it into a
   subdirectory of `./projects/` named after the repo, then work from there:

   ```bash
   REPO=$(basename "<git-url>" .git)
   mkdir -p ./projects
   git clone "<git-url>" "./projects/$REPO"
   cd "./projects/$REPO"
   ```

   Cloning always lands under `./projects/<repo>` — never the current directory
   root — so the workspace stays tidy and multiple projects can coexist. If
   `./projects/$REPO` already exists, reuse it (pull instead of re-clone) or
   pick a non-colliding name, and tell the user. If `$ARGUMENTS` names no repo,
   skip cloning and just orient in the current directory (step 3).

3. **Absorb the inventory.** For anything relevant to the user's stated goal
   (`$ARGUMENTS`, if given), read the actual `SKILL.md` / agent file so you know
   how to invoke it correctly. Remember: skills listed here are invoked via the
   Skill tool or `/<name>`; plugin commands are namespaced `/<plugin>:<command>`.

4. **Orient in the working directory** (the freshly-cloned `./projects/<name>`
   if you cloned, else the current directory). Check `git status`, and read
   `CLAUDE.md` (or `AGENT.md` / `README.md`) if present, so project context is
   loaded too.

5. **Report back concisely**: how many skills / plugins / agents / commands /
   MCP servers are available, where the project was cloned (`./projects/<name>`),
   anything that looks directly useful for `$ARGUMENTS`, and what the project
   contains. Then ask what to do next — or, if `$ARGUMENTS` was given, start on it.

Do not modify any file under `~/.claude`; the `~/.claude` scan is strictly
read-only discovery.
