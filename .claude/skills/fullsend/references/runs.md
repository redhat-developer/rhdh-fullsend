# runs

Browse, search, and analyze fullsend agent run transcripts using AgentsView.

## Overview

Downloads fullsend agent transcripts from GitHub Actions artifacts and serves them in [AgentsView](https://github.com/kenn-io/agentsview) — a web UI for browsing, searching (FTS), and tracking cost across all agent sessions.

Sessions are grouped by repo + agent type (e.g. `rhdh-plugins_review`, `rhdh-agentic_code`). Issue numbers and run metadata are searchable via full-text search.

## Prerequisites

- `gh` CLI authenticated with access to the target repos (for `fetch`/`up`)
- `jq` installed
- Podman or Docker available

## Usage

```
/fullsend runs                    # show status and setup instructions
/fullsend runs fetch              # download all available runs
/fullsend runs up                 # fetch + start AgentsView container
/fullsend runs local [dir]        # import local fullsend runs + start viewer
/fullsend runs viewer             # start viewer without fetching
/fullsend runs down               # stop the container
```

## Procedure

### Status check

If no subcommand is given, check:

1. Does `agentsview/` exist in this repo? If not, tell the user to create it:
   ```bash
   mkdir -p agentsview/scripts
   ```
2. Does `agentsview/runs/` or `agentsview/runs-local/` contain any `.jsonl` files? Report the count and project breakdown for each.
3. Is a container running? Check with:
   ```bash
   podman compose -f agentsview/docker-compose.fullsend.yaml ps 2>/dev/null || \
   docker compose -f agentsview/docker-compose.fullsend.yaml ps 2>/dev/null
   ```
4. Print the URL if running.

### fetch

Run the fetch script:
```bash
cd agentsview && ./scripts/fetch-fullsend-runs.sh
```

The script:
- Paginates through all GitHub Actions artifacts matching `fullsend-*`
- Skips already-downloaded runs (idempotent)
- Extracts transcript JSONLs from artifact archives
- Injects a metadata header with repo, issue, agent, and run URL
- Organizes into `runs/<repo>_<agent>/` directories

Custom repos can be passed as arguments:
```bash
./scripts/fetch-fullsend-runs.sh org/repo1 org/repo2
```

Default repos: `redhat-developer/rhdh-agentic`, `redhat-developer/rhdh-plugins`.

### up

```bash
cd agentsview && make up
```

Or with custom host/port for remote access:
```bash
AGENTSVIEW_HOST=myhost.local AGENTSVIEW_PORT=8082 make up
```

This runs `fetch` first (idempotent), then starts the container.

### local

Import local fullsend runs and start the viewer:

```bash
cd agentsview && make local                                  # auto-discover from $TMPDIR/fullsend
cd agentsview && make local DIR=/tmp/fullsend                # explicit --output-dir
cd agentsview && make local DIR=/tmp/fullsend/agent-triage-3705-1234567890  # single run
```

Without `DIR`, the script auto-discovers runs from `$TMPDIR/fullsend` (macOS per-user temp)
then `/tmp/fullsend`. With `DIR`, accepts either fullsend's `--output-dir` (discovers all
`agent-*` subdirectories) or a single agent run directory. Idempotent — reruns skip
already-imported transcripts.

Local sessions appear in AgentsView under `local_<agent>` project groups
(e.g. `local_my-prs`, `local_triage`), distinguishable from GitHub Actions runs.

### viewer

Start the AgentsView container without fetching or importing — useful when you've already
run `make fetch` or `make local` and just want to restart the viewer:

```bash
cd agentsview && make viewer
```

### down

```bash
cd agentsview && make down
```

## Architecture

```
GitHub Actions artifacts (fullsend-*)       Local fullsend runs (--output-dir)
  │                                           │
  ▼  fetch-fullsend-runs.sh                   ▼  import-local-run.sh
  │                                           │
  ▼                                           ▼
agentsview/runs/                            agentsview/runs-local/
  rhdh-plugins_review/*.jsonl                 local_triage/*.jsonl
  rhdh-agentic_code/*.jsonl                   local_my-prs/*.jsonl
  │                                           │
  │  (make up)                                │  (make local)
  ▼                                           ▼
docker-compose.fullsend.yaml
  AGENTSVIEW_RUNS=./runs (default)    or    AGENTSVIEW_RUNS=./runs-local
  │
  ▼
AgentsView container
  → http://localhost:8081
  → FTS search, analytics, cost tracking
```

Data flow:
- **Remote runs** go to `runs/`, **local runs** go to `runs-local/` — kept separate so `make local` shows only local sessions
- **Index**: SQLite + FTS5 in a Docker volume, cleared on `make down` (`-v`) and rebuilt on next start
- **GitHub artifacts expire after 90 days** — once downloaded, local copies persist

## Searching for runs

In the AgentsView UI:
- Filter by project dropdown to select a repo + agent combination
- Search `#3966` to find all runs for a specific issue
- Search `failure` to find failed runs
- Search tool names like `Bash` or `Read` to find specific tool usage patterns
