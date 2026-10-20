# rhdh-fullsend

[![Fullsend Fleet Status - redhat-developer](https://github.com/redhat-developer/rhdh-fullsend/actions/workflows/fleet-status-redhat-developer.yml/badge.svg)](https://github.com/redhat-developer/rhdh-fullsend/actions/workflows/fleet-status-redhat-developer.yml)
[![Fullsend Fleet Status - rhdh-parasol](https://github.com/redhat-developer/rhdh-fullsend/actions/workflows/fleet-status-rhdh-parasol.yml/badge.svg)](https://github.com/redhat-developer/rhdh-fullsend/actions/workflows/fleet-status-rhdh-parasol.yml)

Custom sandbox images, deployment documentation, and the `/fullsend` Claude Code
skill for the RHDH team's agent infrastructure.

## What's in this repo

| Component | Purpose |
|-----------|---------|
| **`repos.yaml`** | Fleet manifest for per-repo fullsend installs (version pin, mint, repo list) |
| **Sandbox image** | Extends upstream `fullsend-code` with corepack + yarn for JS monorepos |
| **Deployment docs** | GCP setup, repo onboarding, sandbox networking, known issues |
| **`/fullsend` skill** | RHDH-specific Claude Code skill for validating configs, debugging sandboxes, and building custom agents |

## Fleet status

**Fullsend version:** v0.45.0 | **Mint:** `mint.fullsend.sh` (public) | **GCP project:** `rhdh-sidekick-167988` | **WIF pool:** `fullsend-inference`

### Managed repos (`repos.yaml`)

| Repo | Shim customizations |
|------|---------------------|
| `redhat-developer/rhdh-agentic` | All auto-triggers off |
| `redhat-developer/rhdh-cli` | All auto-triggers off |
| `redhat-developer/rhdh-plugins` | All auto-triggers off, workspace `paths:` filter (boost, scorecard, ai-integrations) |
| `redhat-developer/rhdh-plugin-export-overlays` | All auto-triggers off except `issues: [labeled]` (E2E triage + coder, #3823) |
| `redhat-developer/rhdh-skills` | All auto-triggers off |
| `rhdh-parasol/rhdh` | All auto-triggers off |
| `rhdh-parasol/rhdh-agentic` | All auto-triggers off |
| `rhdh-parasol/rhdh-operator` | All auto-triggers off |
| `rhdh-parasol/rhdh-plugins` | All auto-triggers off |
| `rhdh-parasol/rhdh-plugin-export-overlays` | All auto-triggers off |

### Automated verification

The **Fullsend Fleet Status - redhat-developer** and **Fullsend Fleet Status -
rhdh-parasol** workflows each check their organization's repositories in `repos.yaml`
after each push to `main`, including merged PRs. Each workflow has its own status
badge, App token, and report, and installs the fullsend CLI
version specified by `github.fullsend_ref` and checks each target repository's
default branch. “Up to date” means matching the manifest version.

Version drift, missing installations or version pins, API errors, and incomplete
or invalid reports fail the workflow. Other configuration drift produces warnings,
including the fleet's intentional workflow customizations. The job summary lists
the results; each `fullsend-fleet-status-<organization>` artifact contains the raw JSON, CLI
diagnostics, exit code, and Markdown report. Verification does not change target
repositories or create PRs or comments.

Configure the existing GitHub App before running the workflow:

- Install it in every manifest organization and on all managed repositories, with **Contents**,
  **Variables**, and **Secrets** repository permissions set to **Read-only**
  (plus the automatic Metadata permission). Only secret metadata is read.
- Set this repository's Actions variable `FULLSEND_FLEET_APP_ID` to the App ID.
- Set its Actions secret `FULLSEND_FLEET_APP_PRIVATE_KEY` to the App's PEM key.

Each workflow creates an installation token scoped to its organization's
repositories in the manifest. An organization failure does not affect the other
workflow. Adding a repository also requires granting the App access to it.
To recheck after
merging upgrades in target repositories, select the organization's workflow under
**Actions**, then choose **Run workflow** on `main`.

On a fork, configure the App variable and secret in that fork. GitHub requires
the workflow file on the fork's default branch before **Run workflow** becomes
available; you can then select another branch from the dropdown.

To validate changes locally with Node.js 24 or newer:

```bash
npm ci --ignore-scripts
npm run typecheck
npm test
actionlint .github/workflows/fleet-status-*.yml
```

To check the full fleet locally, authenticate with `gh`, install the fullsend
version pinned in `repos.yaml`, and run the same script as CI:

```bash
npm ci --ignore-scripts # Once, and after dependency updates
node scripts/fleet-status.ts
```

Node.js runs the TypeScript script directly using its native type stripping,
with no compilation step. npm installs the pinned YAML parser. You can also run
the check with `npm run fleet:status`.

The script runs fullsend, captures its output, prints the status, and writes `fleet-report/summary.md`
plus the raw diagnostics. It exits with code 0 for a passing check (including
configuration warnings) or 1 for a failed check. It uses your GitHub credentials
and includes all manifest organizations by default. CI calls the same script
with `--owner` to check each organization using its own App token.

Use `--fullsend /path/to/fullsend` to select a CLI binary,
`--manifest /path/to/repos.yaml` to select a manifest, or `--output-dir /path/to/report`
to change the report directory. These options follow the script path in the command.

### Agents

All event-based auto-triggers are disabled. Agents run on-demand via `/fs-*` commands or label-based triggers only.

| Agent | Auto-trigger | Manual trigger |
|-------|-------------|----------------|
| Triage | **Disabled** | `/fs-triage` |
| Review | **Disabled** | `/fs-review` |
| Fix | **Disabled** | `/fs-fix <instruction>` |
| Retro | **Disabled** | `/fs-retro` |
| Code | Label `fullsend` on issue | `/fs-code` |
| Prioritize | Label `priority/*` on issue | `/fs-prioritize` |

### Unmanaged repos

~48 additional repos across `redhat-developer` and `rhdh-parasol` have
`.fullsend/config.yaml` from `fullsend admin install` but are **not** in
`repos.yaml`. They run fullsend independently and don't receive fleet
upgrades. Run `/fullsend fleet-status` to see the full list.

## Getting started

New to fullsend? Start here:

1. Run `/fullsend validate` to check your harness config against the upstream scaffold
2. Run `/fullsend custom-agents` to learn how to build or customize agents

## Documentation

| Doc | What it covers |
|-----|---------------|
| [`repos.yaml`](repos.yaml) | Fleet manifest — bump `github.fullsend_ref` then `fullsend repos install -f repos.yaml`. Merging a pin bump also rebuilds `rhdh-fullsend-code`. |
| [GCP Infrastructure](docs/gcp-infrastructure.md) | GCP project, WIF providers, IAM, service accounts |
| [Sandbox Networking](docs/sandbox-networking.md) | DNS inside OpenShell sandboxes — why it fails, workarounds |

## `/fullsend` skill

The `.claude/skills/fullsend/` directory contains a Claude Code skill that
surfaces all of this repo's knowledge interactively. Available commands:

| Command | What it does |
|---------|-------------|
| `/fullsend validate` | Diff customized harness/env files against upstream scaffold |
| `/fullsend debug <#issue>` | Run sandbox diagnostics |
| `/fullsend fleet-status` | Audit installed vs. managed repos across both orgs |
| `/fullsend onboard <org>/<repo>` | Add a new repo to the fleet (WIF, secrets, scaffold) |
| `/fullsend upgrade [version]` | Upgrade CLI, scaffold files, and dispatch workflows |
| `/fullsend custom-agents` | Guide for building custom standalone agents |
| `/fullsend enable-model` | Enable a model in GCP Model Garden |
| `/fullsend local-setup` | Local agent run setup for Mac |

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

PRs that touch `images/code/**` or `repos.yaml` build but don't push (validation only). Merging a `fullsend_ref` bump to `main` rebuilds and pushes `:latest`.

## Usage

Reference in your fullsend harness config:

```yaml
# .fullsend/rhdh/harness/code.yaml
image: ghcr.io/redhat-developer/rhdh-fullsend-code:latest
```

This replaces the `sandbox-yarn-setup.sh` + `host_files` workaround.

## Local agent runs

Run `/fullsend help setup` in Claude Code, or follow the
[upstream guide](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/running-agents-locally.md)
for the generic steps.

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
