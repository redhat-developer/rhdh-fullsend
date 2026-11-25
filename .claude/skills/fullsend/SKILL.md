---
name: fullsend
description: |
  RHDH-specific fullsend configuration — harness validation, drift checking,
  sandbox debugging, local setup, custom agents, and upgrade management.
  Use when asked to validate fullsend config, check for drift against upstream scaffold,
  diff or compare customized harness/env files against upstream, debug a sandbox run,
  or set up env vars for the sandbox.
  Also use when asked to run sandbox diagnostics, debug the sandbox environment,
  check if yarn/corepack/openspec work, or build a custom fullsend agent.
  Also use when asked to upgrade fullsend, sync scaffold files with a new
  version, update the CLI, bump fullsend, or check what version we're on.
  Also use when asked to onboard a new repo, add a repo to the fleet,
  set up fullsend on a repo, or configure WIF for a new repo.
  Also use when asked to enable a model in the Model Garden, activate
  a new Claude/Anthropic/Grok model, or check model enablement status.
  Also use when asked about local fullsend setup, RHDH GCP project config,
  or the custom sandbox image.
  Also use when asked to audit the fleet, check which repos have fullsend
  installed, compare managed vs. unmanaged repos, or run fleet-status.
---

# /fullsend (RHDH)

RHDH-specific tooling for managing fullsend sandbox configurations — validating customized harness/env files against the upstream scaffold, debugging sandbox issues, and managing the RHDH deployment.

For user-facing fullsend commands (trigger, inspect, watch, help), use the upstream `/fullsend` skill from `fullsend-ai/skill`.

<essential_principles>

## Essential Principles

1. **`base:` composition, not `customized/` overlay.** ADR 0064 removed `.fullsend/customized/`. Repo-owned agents live under `.fullsend/rhdh/` and register in `.fullsend/config.yaml`. Harnesses inherit upstream via `base:` and override only the fields that differ.
2. **`repos.yaml` is the fleet source of truth.** Version pins, mint URL, and the managed repo list live at the root of this repo. Roll a new fullsend version by bumping `github.fullsend_ref` and running `fullsend repos install -f repos.yaml` (PRs only, never `--direct`).
3. **Always diff before deploying.** Thin `base:` harnesses still need a field-by-field check against the upstream file they inherit.
4. **Docker ENV is dead at runtime.** OpenShell strips Containerfile `ENV` directives — they exist during `docker build` but not in the sandbox. All runtime env vars must go through `.env.d/` files.
5. **Harness paths are relative to `.fullsend/`.** `host_files.src` values such as `rhdh/env/yarn-proxy.env` resolve from the per-repo `.fullsend/` root, not from a flattened `customized/` overlay.
6. **Confirm before mutating.** Commands that write to GitHub (`comment`, `label`) must confirm with the user before acting. These are shared-state actions visible to the whole team. Scaffold upgrades go through PRs.

</essential_principles>

<repo_resolution>

## Repo Resolution

All commands that interact with GitHub use the same resolution order:

1. **Explicit `--repo owner/name`** flag — highest priority.
2. **`FULLSEND_REPO` env var** — if set.
3. **cwd detection** — if cwd is inside a git repo with `.fullsend/config.yaml`, derive `owner/name` from `gh repo view --json nameWithOwner -q .nameWithOwner`.
4. **Fallback** — check if `../rhdh-agentic` exists and use its `owner/name`.

If none resolve, ask the user.

</repo_resolution>

<env_delivery>

## How Env Vars Reach the Sandbox

Files in `/sandbox/workspace/.env.d/` are sourced at sandbox startup:
```
for f in /sandbox/workspace/.env.d/*.env; do [ -f "$f" ] && . "$f"; done
```

To add a variable, create an env file and wire it via `host_files` in the harness:

| What | Where | `expand` | Example |
|------|-------|----------|---------|
| Runner-side secrets (tokens, credentials) | `env/<name>.env` with `export VAR=${RUNNER_VAR}` | `true` | `GH_TOKEN`, `ISSUE_NUMBER` |
| Container toolchain config (fixed paths) | `env/<name>.env` with `export VAR=/fixed/path` | omit (false) | `COREPACK_HOME`, `GOPATH` |
| Runner-only vars (never enter sandbox) | `runner_env:` in harness YAML | n/a | `PUSH_TOKEN`, `REPO_DIR` |

**`expand: true`** runs `os.ExpandEnv()` on the file using the **GitHub Actions runner's** environment before copying it into the sandbox. `${PATH}` would become the runner's PATH, not the container's. Omit `expand` for hardcoded values.

</env_delivery>

<setup>

## Setup Gates

| Gate | Required by | Check | If fail |
|------|-------------|-------|---------|
| Scaffold dir | `validate` | `$FULLSEND_SCAFFOLD_DIR` or `../asdlc-lab/resources/fullsend-ai/fullsend/internal/scaffold/fullsend-repo/` is a readable directory | Ask user to set `FULLSEND_SCAFFOLD_DIR` or clone `asdlc-lab` |
| Target repo | all commands | Repo resolution (see above) | Ask user for the repo |
| `gh` CLI | `comment`, `label` | `gh auth status` succeeds | Ask user to install and authenticate `gh` |

</setup>

<intake>

## Commands

| Command | Description |
|---------|-------------|
| `validate [repo-path]` | Diff customized harness/env files against upstream scaffold |
| `debug <#issue> [--repo]` | Run sandbox diagnostics (shortcut for `trigger debug`) |
| `comment <#issue> <message> [--repo]` | Post a comment on an issue or PR |
| `label <#issue> <add\|remove> <label> [--repo]` | Add or remove a label on an issue or PR |
| `fleet-status` | Audit installed vs. managed repos across both orgs |
| `onboard <org>/<repo>` | Add a new repo to the fullsend fleet (WIF, variables, secrets, scaffold) |
| `upgrade [version]` | Upgrade CLI, bump `repos.yaml`, and converge target repos via PRs |
| `custom-agents` | Guide for building custom standalone agents (scaffold, dispatch, security) |
| `enable-model` | Enable a partner model in GCP Model Garden (requires browser + Owner creds) |
| `local-setup` | Guide for running fullsend agents locally on a Mac |

If no arguments are given, display this table and ask which the user wants.

</intake>

<routing>

## Routing

Parse the first word after `/fullsend` as the subcommand.

| Command | Reference |
|---------|-----------|
| `validate` | `references/validate.md` |
| `debug` | `references/debug.md` |
| `comment` | `references/comment.md` |
| `label` | `references/label.md` |
| `enable-model` | `references/enable-model.md` |
| `fleet-status` | `references/fleet-status.md` |
| `onboard` | `references/onboard.md` |
| `upgrade` | `references/upgrade.md` |
| `custom-agents` | `references/custom-agents.md` |
| `local-setup` | `references/local-setup.md` |

</routing>

<troubleshooting>

## Troubleshooting

Common sandbox failures and how to diagnose them.

### "Not logged in" (agent exits immediately)

The Claude API credentials didn't reach the sandbox. Check:

1. **Mount paths** — `host_files[].dest` must use `/sandbox/workspace/` (not `/tmp/workspace/`). OpenShell 0.0.54 changed the mount point. Run `/fullsend validate` to catch stale paths.
2. **`expand: true`** on `gcp-vertex.env` — the env file contains `${RUNNER_VAR}` references that must be expanded from the GitHub Actions runner environment before copying into the sandbox.
3. **GCP credentials file** — `GOOGLE_APPLICATION_CREDENTIALS` dest should be `/tmp/.gcp-credentials.json` (not under `/sandbox/workspace/`).

### yarn install fails or retries

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Failed to create cache directory" | `/tmp/corepack/v1/` owned by root, sandbox user can't write | Image: `chmod -R 777 $COREPACK_HOME` (recursive, not just root dir) |
| Version mismatch (downloads at runtime) | Image has `yarn@stable` but repo pins a specific version | Image: `corepack prepare yarn@<pinned-version> --activate` matching repo's `packageManager` |
| Postinstall triggers nested install | Monorepo root `postinstall` conflicts | Use `yarn install --mode skip-build` |
| Agent sleep-polls background install | Agent backgrounds `yarn install` then polls with `sleep 30` | Agent prompt/skill issue — should run synchronously |

### curl fails but yarn/node work

Expected. The sandbox policy gates network by binary. `curl` is intentionally excluded from all endpoint groups to prevent `disallowedTools` bypass via raw HTTP. Use `node -e "fetch(...)"` or `gh api` for network diagnostics.

### Dispatch 401 on /fs-debug

`GITHUB_TOKEN` can't call `gh workflow run` in some repos due to workflow permissions settings. Workaround: trigger directly via `gh workflow run fullsend-debug.yml --repo <owner/name> --ref main -f issue_key="<N>"`.

### Auto-rebase (stale branch)

The fix agent automatically rebases the PR branch onto `origin/${TARGET_BRANCH}` before running. This happens in the pre-script, outside the sandbox, while the push token is fresh.

| Scenario | What happens |
|----------|-------------|
| Branch is up-to-date | No-op — skips rebase entirely |
| Branch is behind, no conflicts | Rebases and force-pushes (`--force-with-lease`), then agent runs on current base |
| Rebase conflicts | Fails fast with `::error::` — tells human to rebase manually and re-trigger `/fs-fix` |

**You no longer need to ask the agent to rebase.** If someone comments "please rebase" on a PR, just re-trigger `/fs-fix` — the pre-script handles it.

**PRE_AGENT_HEAD caveat**: `PRE_AGENT_HEAD` is set by the workflow *before* the harness runs, so after a rebase it points to the old (pre-rebase) HEAD. This means post-fix.sh's `CHANGED_FILES` may include rebased upstream commits. This is harmless — if the agent made no changes, the post-script push is a no-op; if it did, the push is a fast-forward on top of the already-rebased branch.

### Fix agent fixes the wrong thing

The fix agent has limited context. It does NOT read CI logs, PR comments, or issue threads. Its two input channels are:

| Input | Source | When populated |
|-------|--------|----------------|
| **`HUMAN_INSTRUCTION`** | Text after `/fs-fix` in the comment body | Human-triggered only. Bare `/fs-fix` → `"none"` |
| **`review-body.txt`** (pre-fetched) | Latest `CHANGES_REQUESTED` review by the review bot | Bot-triggered, or when review bot requested changes |

If both are empty, the agent improvises by scanning PR comments — and often fixes the wrong thing (e.g., a changeset bot warning instead of a CI failure).

**Rule: never post bare `/fs-fix`.** Always include a specific instruction:
```
/fs-fix CI fails because report.api.md is missing. Run `yarn build:api-reports` from workspaces/boost/ and commit the generated file.
```

### New Backstage package CI failures cascade

When a fullsend agent creates a new plugin package (e.g., `boost-common`), CI typically fails through a sequence of gates. Each must be fixed in order — fixing one reveals the next:

| CI step | What it checks | Fix command |
|---------|---------------|-------------|
| `build:api-reports` | `report.api.md` exists for packages with public exports | `yarn build:api-reports` |
| `publish check` | `publishConfig`, `main`, `types`, `files` in `package.json` are correct | `yarn backstage-cli repo fix` |
| `prettier:check` | Code formatting | `yarn prettier:fix` |
| `lint` | ESLint | `yarn lint:all --fix` |
| `tsc` | TypeScript compilation | `yarn tsc:full` |

Running `yarn chores` from the workspace root does all of these in one pass.

### Auto-trigger configuration

All auto-triggers are **disabled fleet-wide**. The shim only listens to
`issue_comment` (for `/fs-*` commands) and `pull_request_target: [labeled, unlabeled]`
(for intentional label-based triggers like `fullsend` → code, `priority/*` → prioritize).

| Agent | Auto-trigger | Manual trigger |
|-------|-------------|----------------|
| triage | Disabled (was: issue opened/edited) | `/fs-triage` |
| review | Disabled (was: PR opened/synced) | `/fs-review` |
| fix | Disabled (was: review changes_requested) | `/fs-fix <instruction>` |
| retro | Disabled (was: PR closed) | `/fs-retro` |
| code | Label `fullsend` on issue | `/fs-code` |
| prioritize | Label `priority/*` on issue | `/fs-prioritize` |

To re-enable an auto-trigger, add the corresponding event back to the shim.
See `/fullsend upgrade` step 6a for the full event-to-agent mapping.

**This is a shim edit — `fullsend repos install` will overwrite it.** See
`/fullsend upgrade` step 6a for the re-apply procedure.

### Downloading agent logs

```bash
gh run download <run-id> --repo <owner/name> --name fullsend-<agent> --dir /tmp/inspect
```

Artifact structure:
```
agent-<agent>-<issue>-<timestamp>/
  iteration-1/
    output.jsonl             ← high-level: init, assistant turns, result
    transcripts/<id>.jsonl   ← full conversation with every tool call
  logs/
    openshell-sandbox.log    ← sandbox process logs
    openshell-gateway.log    ← container lifecycle
```

</troubleshooting>

<sandbox_image>

## Sandbox Image

The custom image (`ghcr.io/redhat-developer/rhdh-fullsend-code:latest`) is built from `images/code/Containerfile` in rhdh-fullsend. Auto-builds on push to `main` when `images/code/**` or `repos.yaml` changes (a `fullsend_ref` bump rebuilds so `:latest` picks up the new upstream `fullsend-code` base). `workflow_dispatch` remains for an out-of-band rebuild.

### What's in it (on top of upstream fullsend-code)

- **corepack** enabled with yarn pre-activated (pinned to repo's `packageManager` version)
- **openspec** CLI (`@fission-ai/openspec`)
- `COREPACK_HOME=/tmp/corepack` with recursive write permissions

### Version pinning

The image must pin the same yarn version the target repos use. Check:
```bash
grep packageManager <repo>/package.json
```

If a target repo pins `yarn@4.17.1` (rhdh-plugins, overlays) or `yarn@4.12.0` (rhdh-agentic), the Containerfile must `corepack prepare` those versions. A mismatch forces a runtime re-download through the proxy.

</sandbox_image>
