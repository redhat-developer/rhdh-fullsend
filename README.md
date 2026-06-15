# rhdh-fullsend

Custom sandbox images, deployment documentation, and the `/fullsend` Claude Code
skill for the RHDH team's agent infrastructure.

## What's in this repo

| Component | Purpose |
|-----------|---------|
| **Sandbox image** | Extends upstream `fullsend-code` with corepack + yarn for JS monorepos |
| **Deployment docs** | GCP setup, repo onboarding, sandbox networking, known issues |
| **`/fullsend` skill** | Claude Code skill for validating configs, inspecting runs, triggering agents, and building custom agents |

## Getting started

New to fullsend? Start here:

1. Read [Repo Onboarding](docs/repo-onboarding.md) to install fullsend on a repo
2. Run `/fullsend help` in Claude Code for the agent pipeline overview
3. Run `/fullsend help custom-agents` to learn how to build or customize agents

## Documentation

| Doc | What it covers |
|-----|---------------|
| [Local Setup](docs/local-setup.md) | Podman VM, OpenShell gateway, GCP credentials, running agents locally |
| [Repo Onboarding](docs/repo-onboarding.md) | Installing fullsend on a new RHDH repo (standard and manual methods) |
| [GCP Infrastructure](docs/gcp-infrastructure.md) | GCP project, WIF providers, IAM, service accounts |
| [Sandbox Networking](docs/sandbox-networking.md) | DNS inside OpenShell sandboxes — why it fails, workarounds |
| [Known Issues](docs/known-issues.md) | Active friction points, workarounds, upstream tracking |

## `/fullsend` skill

The `.claude/skills/fullsend/` directory contains a Claude Code skill that
surfaces all of this repo's knowledge interactively. Available commands:

| Command | What it does |
|---------|-------------|
| `/fullsend validate` | Diff customized harness/env files against upstream scaffold |
| `/fullsend inspect <run-id\|#issue>` | Investigate an agent run — status, timing, output, logs |
| `/fullsend trigger <agent> <#issue>` | Post a slash command to start an agent |
| `/fullsend watch <#issue>` | Monitor a run until completion, then auto-inspect |
| `/fullsend debug <#issue>` | Run sandbox diagnostics |
| `/fullsend comment <#issue> <msg>` | Post a comment on an issue or PR |
| `/fullsend label <#issue> <add\|remove> <label>` | Manage issue labels |
| `/fullsend help [topic]` | Agent pipeline, deployment overview, upstream docs |
| `/fullsend custom-agents` | Guide for building custom standalone agents |

## Image

The upstream `fullsend-code` image ships with Go, Python, and shell tooling but
no JavaScript package manager. RHDH monorepos require yarn — without it baked
in, agents spend 10-15 minutes bootstrapping on every run.

```
ghcr.io/fullsend-ai/fullsend-code:latest   (upstream)
  └── ghcr.io/redhat-developer/rhdh-fullsend-code:latest   (this repo)
```

| What's added | Why |
|-------------|-----|
| `corepack enable` | `/usr` is read-only in the sandbox — can't enable at runtime |
| `corepack prepare yarn@stable` | Pre-downloads yarn binary, zero cold-start |
| `/usr/local/bin/yarn` wrapper | Git hooks (husky) run in subprocesses without the agent's PATH |

## Tags

| Tag | When | Use |
|-----|------|-----|
| `latest` | Push to `main` | Production — harness configs reference this |
| `dev` | Any non-PR build | Testing and CI |
| `X.Y.Z` | Tag push `v*` | Immutable release pin |
| `X.Y` | Tag push `v*` | Floating minor for auto-patch |
| `<sha>` | Every non-PR build | Debugging and rollback |

PRs build but don't push (validation only).

## Usage

Reference in your fullsend harness config:

```yaml
# .fullsend/customized/harness/code.yaml
image: ghcr.io/redhat-developer/rhdh-fullsend-code:latest
```

This replaces the `sandbox-yarn-setup.sh` + `host_files` workaround.

## Local agent runs

See [Local Setup](docs/local-setup.md) for running agents on macOS.

## Local build

Requires Podman (or Docker). Builds for your native architecture only.

```bash
podman build -t rhdh-fullsend-code:local \
  -f images/code/Containerfile images/code/
```

### Testing locally with fullsend

After building, use the local image for `fullsend run` by setting the
`FULLSEND_SANDBOX_IMAGE` env var:

```bash
export FULLSEND_SANDBOX_IMAGE=localhost/rhdh-fullsend-code:local

fullsend run code \
  --fullsend-dir /path/to/fullsend/internal/scaffold/fullsend-repo/ \
  --target-repo /path/to/rhdh-plugins/ \
  --env-file ~/.config/fullsend/gcp-vertex.env \
  --env-file ~/.config/fullsend/code.env \
  --no-post-script
```

### Verifying the image contents

```bash
# Check yarn is available
podman run --rm rhdh-fullsend-code:local yarn --version

# Check corepack home
podman run --rm rhdh-fullsend-code:local ls -la /usr/local/share/corepack/

# Interactive shell for debugging
podman run --rm -it rhdh-fullsend-code:local bash
```

### Cross-platform build (requires QEMU)

Build for a different architecture (e.g., amd64 on an Apple Silicon Mac):

```bash
podman build --platform linux/amd64 -t rhdh-fullsend-code:amd64 \
  -f images/code/Containerfile images/code/
```

## Adding more tools

Edit `images/code/Containerfile`. Follow the upstream pattern:
- Pin versions via `ARG`
- Verify checksums with `sha256sum -c` for binary downloads
- Keep `USER sandbox` as the last line

## Upstream tracking

This image inherits everything from `fullsend-code:latest`. When upstream
updates their base image (Claude Code, gitleaks, Go, etc.), our image picks
it up automatically on the next rebuild. Pin `BASE_IMAGE` to a specific
digest if you need reproducibility:

```dockerfile
ARG BASE_IMAGE=ghcr.io/fullsend-ai/fullsend-code@sha256:abc123...
```
