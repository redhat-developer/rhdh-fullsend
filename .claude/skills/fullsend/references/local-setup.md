# local-setup

Guide for running fullsend agents locally on a Mac. Covers only RHDH-specific setup — for the generic fullsend/OpenShell installation, follow the upstream guide first.

## Usage

```
/fullsend help setup
/fullsend help local
```

## Procedure

### 1. Upstream first

Direct the user to the canonical upstream guide for all generic setup:

```
Follow the upstream guide first:
   https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/running-agents-locally.md

   It covers: fullsend CLI download, OpenShell install, GCP credentials,
   GitHub token, Podman setup, and running default agents.

   Come back here after completing those steps for the RHDH-specific additions below.
```

### 2. RHDH GCP project

Our agents run on the `rhdh-sidekick-167988` GCP project. If the user's team lead provides a service account key, they save it to `~/.config/fullsend/fullsend-local-credentials.json`. If they need to create a SA themselves, point them to `docs/gcp-infrastructure.md` in this repo.

Present the GCP env file with our project values filled in:

```bash
# ~/.config/fullsend/gcp-vertex.env
ANTHROPIC_VERTEX_PROJECT_ID=rhdh-sidekick-167988
CLOUD_ML_REGION=us-east5
GOOGLE_CLOUD_PROJECT=rhdh-sidekick-167988
GOOGLE_APPLICATION_CREDENTIALS=/Users/<you>/.config/fullsend/fullsend-local-credentials.json
FULLSEND_SANDBOX_IMAGE=ghcr.io/redhat-developer/rhdh-fullsend-code:latest
```

**IMPORTANT:** `FULLSEND_SANDBOX_IMAGE` must point to the RHDH custom image, not the upstream
default (`ghcr.io/fullsend-ai/fullsend-sandbox:dev`). The custom image includes corepack,
yarn, and openspec — without it, `yarn install` and `openspec validate` will fail inside
the sandbox.

### 3. RHDH custom sandbox image

Our image extends upstream with corepack + yarn for JS monorepos:

```
ghcr.io/redhat-developer/rhdh-fullsend-code:latest
```

To test a locally built image instead:

```bash
podman build -t rhdh-fullsend-code:local \
  -f images/code/Containerfile images/code/

export FULLSEND_SANDBOX_IMAGE=localhost/rhdh-fullsend-code:local
```

### 4. Per-agent env files

Each agent needs a local env file with the runner-context variables that
`expand: true` substitutes into the sandbox. The scaffold's env templates
(e.g., `env/code-agent.env`) reference `${GH_TOKEN}`, `${ISSUE_NUMBER}`, etc.
— your local env file provides the values.

**Common variables all agents need:**

| Variable | Source | Notes |
|----------|--------|-------|
| `GH_TOKEN` | `gh auth token` | Read-only in sandbox; used for `gh` commands |
| `ISSUE_NUMBER` | Per-run | The issue or PR number to work on |
| `GITHUB_ISSUE_URL` | Per-run | Full URL to the issue |
| `REPO_FULL_NAME` | Per-run | `owner/repo` format |

**Code agent** (`~/.config/fullsend/code-agent.env`):

```bash
GH_TOKEN=<output of gh auth token>
ISSUE_NUMBER=<number>
GITHUB_ISSUE_URL=https://github.com/redhat-developer/rhdh-plugins/issues/<number>
REPO_FULL_NAME=redhat-developer/rhdh-plugins
GIT_BOT_EMAIL=noreply@local
GIT_AUTHOR_NAME=fullsend-local
GIT_AUTHOR_EMAIL=noreply@local
GIT_COMMITTER_NAME=fullsend-local
GIT_COMMITTER_EMAIL=noreply@local
MAX_RETRIES=1
TIMEOUT_SECONDS=2100
```

`GIT_BOT_EMAIL` is required — the scaffold's `code-agent.env` template uses
`${GIT_BOT_EMAIL}` for `GIT_AUTHOR_EMAIL` and `GIT_COMMITTER_EMAIL`. In CI,
this is resolved from the GitHub App bot identity. Locally, `noreply@local` works.

**Triage agent** (`~/.config/fullsend/triage.env`):

```bash
GH_TOKEN=<output of gh auth token>
GITHUB_ISSUE_URL=https://github.com/<org>/<repo>/issues/<number>
```

### 5. Running an RHDH agent

After gateway is running (`~/.config/fullsend/start-gateway.sh`), run an agent:

```bash
# Triage (quickest — ~2 min, ~$2)
fullsend run triage \
  --fullsend-dir ~/src/rhdh/asdlc-lab/resources/fullsend-ai/fullsend/internal/scaffold/fullsend-repo/ \
  --target-repo ~/src/rhdh/rhdh-plugins/ \
  --env-file ~/.config/fullsend/gcp-vertex.env \
  --env-file ~/.config/fullsend/triage.env \
  --no-post-script

# Code (full run — ~15-35 min, ~$15-30)
fullsend run code \
  --fullsend-dir ~/src/rhdh/asdlc-lab/resources/fullsend-ai/fullsend/internal/scaffold/fullsend-repo/ \
  --target-repo ~/src/rhdh/rhdh-plugins/ \
  --env-file ~/.config/fullsend/gcp-vertex.env \
  --env-file ~/.config/fullsend/code-agent.env \
  --no-post-script
```

`--no-post-script` prevents the agent from pushing branches or creating PRs.
Remove it only when you want the agent to act on its result.

### 6. Checking sandbox logs

After a run, inspect sandbox logs for network policy issues:

```bash
# Find the latest run output
ls -td /tmp/fullsend/agent-*/ | head -1

# Check for DENIED requests
grep "DENIED" /tmp/fullsend/agent-*/logs/openshell-sandbox.log | sort | uniq -c | sort -rn

# Full sandbox log
less /tmp/fullsend/agent-*/logs/openshell-sandbox.log
```

### 7. What to expect

| Metric | Value |
|--------|-------|
| Sandbox creation | ~2-8 seconds |
| Bootstrap | ~7 seconds |
| Agent inference | ~30-60 seconds per iteration |
| Total (triage) | ~2 minutes |
| Total (code) | ~15-35 minutes |
| Estimated cost (triage) | ~$2.00 |
| Estimated cost (code) | ~$15-30 |

Output: `/tmp/fullsend/agent-<type>-*/iteration-*/output/agent-result.json`

### 8. Viewing local runs in AgentsView

After running an agent locally, import the output into AgentsView:

```bash
cd agentsview && make local                                  # auto-discovers from $TMPDIR/fullsend
cd agentsview && make local DIR=/tmp/fullsend/agent-triage-3705-1234567890  # single run
```

Without `DIR`, the script auto-discovers runs from fullsend's default output location
(`$TMPDIR/fullsend` on macOS). All `agent-*` subdirectories are discovered and imported.

### 9. Troubleshooting (RHDH-specific)

For generic troubleshooting (sandbox creation, gateway connectivity, missing env vars,
arm64 image pulls, Podman host-gateway), see the upstream guide.

**Common local setup mistakes:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `yarn: command not found` | Using upstream default image instead of RHDH custom image | Set `FULLSEND_SANDBOX_IMAGE=ghcr.io/redhat-developer/rhdh-fullsend-code:latest` in gcp-vertex.env |
| Agent can't run `gh` commands | Missing `GH_TOKEN` in local env file | Add `GH_TOKEN=<gh auth token>` to your agent env file |
| Git commits fail with empty email | Missing `GIT_BOT_EMAIL` in code-agent.env | Add `GIT_BOT_EMAIL=noreply@local` — the scaffold template uses `${GIT_BOT_EMAIL}` |
| `COREPACK_HOME` not set | Using upstream image (Docker ENV stripped at runtime) | Use RHDH custom image + `rhdh-toolchain.env` sets it via `.env.d/` |
| `DENIED ... edge.openspec.dev:443` | openspec telemetry not in policy | Set `OPENSPEC_TELEMETRY=0` in `rhdh-toolchain.env` |
| 268 DENIED for `registry.npmjs.org` | Yarn scoped packages use `%2F` encoding | Add `allow_encoded_slash: true` to npmjs endpoint in policy |
