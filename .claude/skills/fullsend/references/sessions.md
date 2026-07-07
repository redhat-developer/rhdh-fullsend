# sessions

Share and browse team Claude Code session transcripts via a shared git repo.

## Overview

Exports regular Claude Code sessions (not just fullsend runs) to a shared git repo, making them viewable in AgentsView alongside fullsend agent runs. Sessions are auto-exported on session end via a `SessionEnd` hook, committed locally, and pushed on demand.

## Prerequisites

- `~/.config/fullsend/sessions.env` exists with `FULLSEND_SESSIONS_REPO` set to a valid git repo path
- `jq` installed
- The sessions repo must be initialized (`git init`) before first use

## Usage

```
/fullsend sessions                # status — config check, session count, last sync
/fullsend sessions push           # push local commits to remote
/fullsend sessions pull           # pull team sessions from remote
/fullsend sessions view           # start AgentsView with shared sessions
```

## Setup

If sessions are not yet configured, guide the user through setup:

1. Create or clone the shared sessions repo:
   ```bash
   # New repo
   mkdir -p ~/src/team-sessions && cd ~/src/team-sessions && git init

   # Or clone existing
   git clone git@github.com:org/team-sessions.git ~/src/team-sessions
   ```

2. Create the config file:
   ```bash
   mkdir -p ~/.config/fullsend
   echo 'FULLSEND_SESSIONS_REPO=/Users/me/src/team-sessions' > ~/.config/fullsend/sessions.env
   chmod 600 ~/.config/fullsend/sessions.env
   ```

3. Verify the hook is active — `.claude/settings.json` in the project repo should have the `SessionEnd` hook configured. This is already committed in rhdh-fullsend.

## Procedure

### Status check (no subcommand)

Check and report:

1. **Config**: Does `~/.config/fullsend/sessions.env` exist? Is `FULLSEND_SESSIONS_REPO` set and pointing to a valid directory?
   ```bash
   if [ -f ~/.config/fullsend/sessions.env ]; then
     . ~/.config/fullsend/sessions.env
     echo "Sessions repo: ${FULLSEND_SESSIONS_REPO:-not set}"
     [ -d "${FULLSEND_SESSIONS_REPO:-}" ] && echo "Status: exists" || echo "Status: directory not found"
   else
     echo "Not configured — run /fullsend sessions for setup instructions"
   fi
   ```

2. **Session count**: How many `.jsonl` files are in the sessions repo?
   ```bash
   find "$FULLSEND_SESSIONS_REPO" -name '*.jsonl' | wc -l
   ```

3. **Project breakdown**: Which projects have sessions?
   ```bash
   ls -d "$FULLSEND_SESSIONS_REPO"/*/ 2>/dev/null | xargs -I{} sh -c 'echo "$(basename {}): $(find {} -name "*.jsonl" | wc -l) sessions"'
   ```

4. **Git status**: Any unpushed commits?
   ```bash
   git -C "$FULLSEND_SESSIONS_REPO" log --oneline '@{upstream}..HEAD' 2>/dev/null | wc -l
   ```

If not configured, print the setup instructions from the Setup section above.

### push

Push local session commits to the remote:

```bash
. ~/.config/fullsend/sessions.env
git -C "$FULLSEND_SESSIONS_REPO" push
```

Report how many commits were pushed. If no remote is configured, tell the user to add one:
```bash
git -C "$FULLSEND_SESSIONS_REPO" remote add origin <url>
```

### pull

Pull team sessions from the remote:

```bash
. ~/.config/fullsend/sessions.env
git -C "$FULLSEND_SESSIONS_REPO" pull --rebase
```

Report new sessions received (count of new `.jsonl` files).

### view

Start AgentsView with the sessions repo as the data source:

```bash
cd agentsview && make sessions
```

This sets `AGENTSVIEW_RUNS` to the sessions repo path and starts the container.

## Architecture

```
Claude Code session ends
  │
  ▼  SessionEnd hook (.claude/settings.json)
  │
  ▼  export-session.sh (reads stdin JSON)
  │
  ├── Sources config from ~/.config/fullsend/sessions.env
  ├── Copies transcript with metadata header
  └── git add + git commit (local only)
  │
  ▼
<sessions-repo>/<user>_<project>/<session-id>.jsonl
  │
  ├── /fullsend sessions push → git push
  ├── /fullsend sessions pull → git pull --rebase
  └── /fullsend sessions view → make sessions → AgentsView
```

Session directory layout:
```
team-sessions/
  marcel-hild_rhdh-fullsend/
    abc-123-def.jsonl
    xyz-789-ghi.jsonl
  marcel-hild_rhdh-plugins/
    ...
  teammate_their-project/
    ...
```
