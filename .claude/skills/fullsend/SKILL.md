---
description: "Fullsend harness validation, drift checking, sandbox debugging, and fullsend setup"
---

# /fullsend

Tooling for managing fullsend sandbox configurations — validating customized harness/env files against the upstream scaffold, debugging sandbox issues, and managing fullsend setup.

## Essential Principles

1. **Customized files are full replacements.** When a repo places a file in `.fullsend/customized/harness/`, fullsend uses it *instead of* the scaffold version — not merged, not overlaid. Any field omitted from the customized file is silently dropped.
2. **Upstream scaffold is source of truth.** The canonical harness and env definitions live in the scaffold repo. Customizations must track upstream changes or they drift.
3. **Always diff before deploying.** Never commit a customized harness without comparing it field-by-field against the current upstream version.

## Setup Gates

**Scaffold directory** (required by `validate`):

1. Environment variable `FULLSEND_SCAFFOLD_DIR` (if set)
2. Default relative path: `../asdlc-lab/resources/fullsend-ai/fullsend/internal/scaffold/fullsend-repo/`

If neither resolves to a readable directory, stop and ask the user to set `FULLSEND_SCAFFOLD_DIR` or clone `asdlc-lab`.

**Target repo** (used by `validate` and `inspect`):

1. Explicit argument (repo path or `--repo` flag)
2. Default: `../rhdh-agentic`

## Commands

| Command | Description |
|---------|-------------|
| `validate [repo-path]` | Diff customized harness/env files against upstream scaffold |
| `inspect <run-id \| #issue>` | Investigate a fullsend agent run — status, timing, output, logs |

## Routing

1. Parse the first word after `/fullsend` as the subcommand.
2. If it matches a command above, read the corresponding reference file from `references/<command>.md` and follow its procedure.
3. If no arguments are given, display the commands table above and ask which the user wants.
