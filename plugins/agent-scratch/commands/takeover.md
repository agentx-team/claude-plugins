---
description: Take over another directory's project — absorb its Claude session history into this context, move its files under ./projects/<name>, and continue the work from there
argument-hint: "<source-directory, e.g. ~/work/old-project>"
allowed-tools: Bash, Read, Glob, Grep, Write, Edit, AskUserQuestion
---

# Takeover

Move a project — files **and** conversation history — from a source directory
into `./projects/<name>` (a subdirectory of the current directory), and continue
the work there as if the old session never stopped.

If no source directory is given in `$ARGUMENTS`, ask "Which directory should I
take over?" and stop.

## Step 0 — rescan Claude capabilities

Before anything else, rescan `~/.claude` (skills, plugins, agents, commands,
MCP) so the continued work can use everything available:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/scan-claude-home.sh"
```

If the absorbed history references a skill or plugin, check it against this
inventory before invoking it.

## Step A — absorb the source directory's session history

1. Locate its Claude session transcripts:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/find-session.sh" <source-dir>
   ```

   Transcripts live under `~/.claude/projects/<encoded-path>/*.jsonl`, where
   the encoded path is the absolute source path with every non-alphanumeric
   character replaced by `-`. The script prints matches newest-first.

2. If sessions were found, digest the most recent one (the largest/newest
   `.jsonl`; digest a second one too if the newest is tiny):

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/extract-session.py" <session.jsonl> --max-chars 60000
   ```

   Read the digest carefully — it is the prior conversation: what the user
   asked for, what was built, decisions made, and where work stopped. This
   history is now part of YOUR context; treat its goals and decisions as
   already-established facts, not things to re-ask.

## Step B — move the files into ./projects/<name>

1. Preview what will move: `ls -la <source-dir>` and check
   `git -C <source-dir> status` if it is a git repo. Warn the user if the
   source has uncommitted changes, then confirm with `AskUserQuestion` before
   moving.

2. Move the whole source directory — files, dotfiles, and any `.git` — into a
   subdirectory of `./projects/`, named after the source basename:

   ```bash
   SUBDIR=$(basename "<source-dir>")
   mkdir -p ./projects
   mv "<source-dir>" "./projects/$SUBDIR"
   ```

   A plain `mv` is used (not `cp+rm`): the destination `./projects/$SUBDIR` is a
   fresh path, so there are no conflicts to overwrite, and `mv` preserves the
   source's own `.git` intact rather than merging it into the current repo. If
   `./projects/$SUBDIR` already exists, pick a non-colliding name (e.g. append a
   short suffix) and tell the user.

3. Re-anchor the absorbed context to the new location: from now on, every path
   from the old session maps under `./projects/$SUBDIR/` — `<source-dir>/x/y` is
   now `./projects/$SUBDIR/x/y`. Verify the key files mentioned in the digest
   actually exist at their new paths, then `cd ./projects/$SUBDIR` to continue.

## Step C — fallback when there is no session

If Step A found no transcripts, build context from the project's own docs
instead. After moving the files (Step B), read them under
`./projects/$SUBDIR/` **in this order, first hit wins as the primary source**:
`CLAUDE.md`, then `AGENT.md`, then `README.md`. Supplement with
`git -C ./projects/$SUBDIR log --oneline -20` and a quick scan of the top-level
layout. If none of the three files exists, explore the moved tree directly
and summarize what the project appears to be.

## Finish

Report: the new location (`./projects/$SUBDIR`), where the history came from
(session digest vs. docs), what the project is, what state the work was in, and
the single most likely next action — then continue that work from
`./projects/$SUBDIR`.
