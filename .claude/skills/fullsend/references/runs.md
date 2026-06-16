# runs

Browse, search, and analyze fullsend agent run transcripts using AgentsView.

## Overview

Downloads fullsend agent transcripts from GitHub Actions artifacts and serves them in [AgentsView](https://github.com/kenn-io/agentsview) — a web UI for browsing, searching (FTS), and tracking cost across all agent sessions.

Sessions are grouped by repo + agent type (e.g. `rhdh-plugins_review`, `rhdh-agentic_code`). Issue numbers and run metadata are searchable via full-text search.

## Prerequisites

- `gh` CLI authenticated with access to the target repos
- `jq` installed
- Podman or Docker available

## Usage

```
/fullsend runs              # show status and setup instructions
/fullsend runs fetch        # download all available runs
/fullsend runs up           # fetch + start AgentsView container
/fullsend runs down         # stop the container
```

## Procedure

### Status check

If no subcommand is given, check:

1. Does `agentsview/` exist in this repo? If not, tell the user to create it:
   ```bash
   mkdir -p agentsview/scripts
   ```
2. Does `agentsview/runs/` contain any `.jsonl` files? Report the count and project breakdown.
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

### down

```bash
cd agentsview && make down
```

## Architecture

```
GitHub Actions artifacts (fullsend-*)
  │
  ▼  fetch-fullsend-runs.sh
  │  (gh api --paginate → gh run download → inject metadata → organize)
  │
  ▼
agentsview/runs/                     ← local disk, gitignored
  rhdh-plugins_review/*.jsonl
  rhdh-agentic_code/*.jsonl
  ...
  │
  ▼  docker-compose.fullsend.yaml
  │  (mounts ./runs as /agents/claude:ro)
  │
  ▼
AgentsView container                 ← SQLite index in Docker volume
  → http://localhost:8081
  → FTS search, analytics, cost tracking
```

Data flow:
- **Source of truth**: JSONL files on disk in `runs/`
- **Index**: SQLite + FTS5 in a Docker volume (rebuilt on container restart)
- **GitHub artifacts expire after 90 days** — once downloaded, local copies persist

## Searching for runs

In the AgentsView UI:
- Filter by project dropdown to select a repo + agent combination
- Search `#3966` to find all runs for a specific issue
- Search `failure` to find failed runs
- Search tool names like `Bash` or `Read` to find specific tool usage patterns
