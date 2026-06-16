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
📘 Follow the upstream guide first:
   https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/running-agents-locally.md

   It covers: fullsend CLI download, OpenShell install, GCP credentials,
   GitHub token, Podman setup, and running default agents.

   Come back here after completing those steps for the RHDH-specific additions below.
```

### 2. RHDH GCP project

Our agents run on the `rhdh-sidekick-167988` GCP project. If the user's team lead provides a service account key, they save it to `~/.config/fullsend/fullsend-local-credentials.json`. If they need to create a SA themselves, point them to `docs/gcp-infrastructure.md` in this repo.

Present the GCP env file with our project values filled in:

```
# ~/.config/fullsend/gcp-vertex.env
ANTHROPIC_VERTEX_PROJECT_ID=rhdh-sidekick-167988
CLOUD_ML_REGION=us-east5
GOOGLE_CLOUD_PROJECT=rhdh-sidekick-167988
GOOGLE_APPLICATION_CREDENTIALS=/path/to/.config/fullsend/fullsend-local-credentials.json
FULLSEND_SANDBOX_IMAGE=ghcr.io/redhat-developer/rhdh-fullsend-code:latest
```

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

### 4. Running an RHDH agent

After gateway is running, show a typical triage run:

```bash
# Agent-specific env
# ~/.config/fullsend/triage.env
GH_TOKEN=<your-github-pat>
GITHUB_ISSUE_URL=https://github.com/<org>/<repo>/issues/<number>
```

```bash
fullsend run triage \
  --fullsend-dir /path/to/fullsend/internal/scaffold/fullsend-repo/ \
  --target-repo /path/to/your/target-repo/ \
  --env-file ~/.config/fullsend/gcp-vertex.env \
  --env-file ~/.config/fullsend/triage.env \
  --no-post-script
```

`--no-post-script` prevents the agent from modifying the GitHub issue. Remove it when you want the agent to act on its triage result.

Refer to the upstream guide's per-agent env var tables for `code`, `review`, and `fix` agents.

### 5. What to expect

| Metric | Value |
|--------|-------|
| Sandbox creation | ~2-8 seconds |
| Bootstrap | ~7 seconds |
| Agent inference | ~30-60 seconds per iteration |
| Total (triage) | ~2 minutes |
| Estimated cost (triage) | ~$2.00 |

Output: `/tmp/fullsend/agent-triage-*/iteration-*/output/agent-result.json`

### 6. Troubleshooting (RHDH-specific)

For generic troubleshooting (sandbox creation, gateway connectivity, missing env vars, arm64 image pulls, Podman host-gateway), see the upstream guide.
