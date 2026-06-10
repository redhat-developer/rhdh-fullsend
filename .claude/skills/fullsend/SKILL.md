---
name: fullsend
description: |
  Fullsend harness validation, drift checking, sandbox debugging, and fullsend setup.
  Use when asked to validate fullsend config, check for drift against upstream scaffold,
  diff or compare customized harness/env files against upstream, debug a sandbox run,
  inspect a fullsend agent run, or look at a specific run by ID or issue number.
  Also use when asked why a fullsend run failed, what changed in the harness, or how
  to set up env vars for the sandbox.
---

# /fullsend

Tooling for managing fullsend sandbox configurations — validating customized harness/env files against the upstream scaffold, debugging sandbox issues, and managing fullsend setup.

<essential_principles>

## Essential Principles

1. **Customized files are full replacements.** When a repo places a file in `.fullsend/customized/harness/`, fullsend uses it *instead of* the scaffold version — not merged, not overlaid. Any field omitted from the customized file is silently dropped.
2. **Upstream scaffold is source of truth.** The canonical harness and env definitions live in the scaffold repo. Customizations must track upstream changes or they drift.
3. **Always diff before deploying.** Never commit a customized harness without comparing it field-by-field against the current upstream version.
4. **Docker ENV is dead at runtime.** OpenShell strips Containerfile `ENV` directives — they exist during `docker build` but not in the sandbox. All runtime env vars must go through `.env.d/` files.
5. **Path flattening.** Fullsend overlays `.fullsend/customized/env/` → `env/`, `.fullsend/customized/harness/` → `harness/`, etc. Harness `host_files.src` paths are always relative to the **flattened** working dir (e.g., `env/foo.env`, never `customized/env/foo.env`).

</essential_principles>

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
| Target repo | `validate`, `inspect` | Explicit argument, `--repo` flag, or `../rhdh-agentic` exists | Ask user for the repo path |
| `gh` CLI | `inspect` | `gh auth status` succeeds | Ask user to install and authenticate `gh` — `inspect` cannot run without it |

</setup>

<intake>

## Commands

| Command | Description |
|---------|-------------|
| `validate [repo-path]` | Diff customized harness/env files against upstream scaffold |
| `inspect <run-id \| #issue>` | Investigate a fullsend agent run — status, timing, output, logs |

If no arguments are given, display this table and ask which the user wants.

</intake>

<routing>

## Routing

Parse the first word after `/fullsend` as the subcommand.

| Command | Reference |
|---------|-----------|
| `validate` | `references/validate.md` |
| `inspect` | `references/inspect.md` |

</routing>
