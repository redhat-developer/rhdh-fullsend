---
name: fullsend
description: |
  Fullsend harness validation, drift checking, sandbox debugging, and fullsend setup.
  Use when asked to validate fullsend config, check for drift against upstream scaffold,
  diff or compare customized harness/env files against upstream, debug a sandbox run,
  inspect a fullsend agent run, or look at a specific run by ID or issue number.
  Also use when asked why a fullsend run failed, what changed in the harness, or how
  to set up env vars for the sandbox.
  Also use when asked to trigger a fullsend agent, post a slash command on an issue,
  watch or monitor a fullsend run, comment on an issue, or manage labels.
  Also use when asked to run sandbox diagnostics, debug the sandbox environment,
  check if yarn/corepack/openspec work, or build a custom fullsend agent.
  Also use when asked what fullsend agents are, how they work, how to use them,
  what agents are available, how to get started with fullsend, or how the local
  deployment is configured.
---

# /fullsend

Tooling for managing fullsend sandbox configurations — validating customized harness/env files against the upstream scaffold, debugging sandbox issues, triggering and monitoring agent runs, and managing issue metadata.

<essential_principles>

## Essential Principles

1. **Customized files are full replacements.** When a repo places a file in `.fullsend/customized/harness/`, fullsend uses it *instead of* the scaffold version — not merged, not overlaid. Any field omitted from the customized file is silently dropped.
2. **Upstream scaffold is source of truth.** The canonical harness and env definitions live in the scaffold repo. Customizations must track upstream changes or they drift.
3. **Always diff before deploying.** Never commit a customized harness without comparing it field-by-field against the current upstream version.
4. **Docker ENV is dead at runtime.** OpenShell strips Containerfile `ENV` directives — they exist during `docker build` but not in the sandbox. All runtime env vars must go through `.env.d/` files.
5. **Path flattening.** Fullsend overlays `.fullsend/customized/env/` → `env/`, `.fullsend/customized/harness/` → `harness/`, etc. Harness `host_files.src` paths are always relative to the **flattened** working dir (e.g., `env/foo.env`, never `customized/env/foo.env`).
6. **Confirm before mutating.** Commands that write to GitHub (`trigger`, `comment`, `label`) must confirm with the user before acting. These are shared-state actions visible to the whole team.

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
| `gh` CLI | `inspect`, `trigger`, `watch`, `comment`, `label` | `gh auth status` succeeds | Ask user to install and authenticate `gh` |

</setup>

<intake>

## Commands

| Command | Description |
|---------|-------------|
| `validate [repo-path]` | Diff customized harness/env files against upstream scaffold |
| `inspect <run-id \| #issue>` | Investigate a fullsend agent run — status, timing, output, logs |
| `trigger <agent> <#issue\|#PR> [--repo] [--force]` | Post a fullsend slash command to start an agent |
| `watch <#issue\|run-id> [--repo]` | Monitor a triggered run until completion, then auto-inspect |
| `debug <#issue> [--repo]` | Run sandbox diagnostics (shortcut for `trigger debug`) |
| `comment <#issue> <message> [--repo]` | Post a comment on an issue or PR |
| `label <#issue> <add\|remove> <label> [--repo]` | Add or remove a label on an issue or PR |
| `help [topic]` | Onboarding companion — agent pipeline, local deployment overview, upstream docs |

If no arguments are given, display this table and ask which the user wants.

</intake>

<routing>

## Routing

Parse the first word after `/fullsend` as the subcommand.

| Command | Reference |
|---------|-----------|
| `validate` | `references/validate.md` |
| `inspect` | `references/inspect.md` |
| `trigger` | `references/trigger.md` |
| `watch` | `references/watch.md` |
| `debug` | `references/debug.md` |
| `comment` | `references/comment.md` |
| `label` | `references/label.md` |
| `help` | `references/help.md` |

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

Parse assistant output:
```bash
python3 -c "
import json
with open('output.jsonl') as f:
    for line in f:
        obj = json.loads(line)
        if obj.get('type') == 'assistant':
            for c in obj['message'].get('content', []):
                if c.get('type') == 'text': print(c['text'])
"
```

</troubleshooting>

<sandbox_image>

## Sandbox Image

The custom image (`ghcr.io/redhat-developer/rhdh-fullsend-code:latest`) is built from `images/code/Containerfile` in rhdh-fullsend. Auto-builds on push to main when `images/code/**` changes.

### What's in it (on top of upstream fullsend-code)

- **corepack** enabled with yarn pre-activated (pinned to repo's `packageManager` version)
- **openspec** CLI (`@fission-ai/openspec`)
- `COREPACK_HOME=/tmp/corepack` with recursive write permissions

### Version pinning

The image must pin the same yarn version the target repos use. Check:
```bash
grep packageManager <repo>/package.json
```

If the repo pins `yarn@4.12.0`, the Containerfile must use `corepack prepare yarn@4.12.0 --activate`. A mismatch forces a runtime re-download through the proxy.

</sandbox_image>
