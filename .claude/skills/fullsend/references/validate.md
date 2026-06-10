# validate

Diff customized harness and env files against the upstream scaffold to catch drift.

## Usage

```
/fullsend validate [repo-path]
```

- `repo-path`: path to the repo with `.fullsend/customized/` overrides. Default: `../rhdh-agentic`

## Procedure

### 1. Resolve paths

```
SCAFFOLD_DIR = $FULLSEND_SCAFFOLD_DIR or ../asdlc-lab/resources/fullsend-ai/fullsend/internal/scaffold/fullsend-repo/
TARGET_DIR   = <repo-path>/.fullsend/customized/
```

Verify both directories exist. Abort with a clear message if either is missing.

### 2. Validate harness files

For each `*.yaml` in `TARGET_DIR/harness/`:

1. Read the customized file.
2. Read the upstream file at `SCAFFOLD_DIR/harness/<same-name>.yaml`.
   - If the upstream file does not exist, report it as **WARNING: no upstream counterpart** (may be a repo-specific harness).
3. Run a structured diff. Classify each difference:

#### Error (blocks deployment)

- **Missing top-level field**: a field present in upstream but absent in the customized file. Because customized files are full replacements, this means the field is silently dropped at runtime.
  - Known critical fields: `policy`, `agent`, `pre_script`, `post_script`
- **Stale paths**: any `host_files[].dest` containing `/tmp/workspace/` — this was replaced by `/sandbox/workspace/` in OpenShell 0.0.54.

#### Review (needs human judgement)

- **Changed paths**: `host_files[].dest` values that differ from upstream but are not stale (may be intentional).
- **Changed values**: fields like `image`, `timeout_minutes`, `model` that differ from upstream — these are often intentional overrides but should be confirmed.
- **Missing list items**: entries in upstream `host_files`, `skills`, or `plugins` arrays that are absent in the customized version.

#### Info (expected differences)

- **Intentional overrides**: fields that differ but are clearly repo-specific customizations (e.g., different `image` tag, different `timeout_minutes` for debugging).
- **Added fields**: fields in the customized file that don't exist in upstream (repo-specific extensions).
- **Comment differences**: comment-only changes.

### 3. Validate env files

For each file in `TARGET_DIR/env/`:

1. Read the customized file.
2. Read the upstream file at `SCAFFOLD_DIR/env/<same-name>`.
   - If no upstream counterpart exists, report as **INFO: repo-specific env file**.
3. Compare exported variable names:
   - Variables in upstream but missing from customized → **ERROR: missing variable**.
   - Variables in customized but not in upstream → **INFO: repo-specific variable**.
4. For shared variables, flag value differences as **REVIEW** (may be intentional overrides like different `GIT_AUTHOR_NAME`).

### 4. Cross-check for orphaned customizations

List any files in `TARGET_DIR/harness/` or `TARGET_DIR/env/` that have no upstream counterpart — these may be leftover from a renamed or removed upstream file.

### 5. Report

Output a structured report grouped by severity:

```
## Fullsend Validation: <repo-name>

### Errors (must fix before deploying)
- harness/code.yaml: missing field `doc` (present in upstream)
- harness/code.yaml: missing field `plugins` (present in upstream)

### Review (confirm these are intentional)
- harness/code.yaml: `timeout_minutes` changed: 35 → 5
- harness/code.yaml: `image` changed: ghcr.io/fullsend-ai/... → ghcr.io/redhat-developer/...

### Info
- harness/code.yaml: comment added at line 1 (repo-specific)

### Summary
- Files checked: 2 harness, 0 env
- Errors: 2 | Review: 2 | Info: 1
```

If there are zero errors, end with: **All customizations are consistent with upstream.**

## Special Checks

These are run regardless of whether a field is classified above:

| Check | Condition | Severity |
|-------|-----------|----------|
| Stale workspace path | Any `dest` containing `/tmp/workspace/` | ERROR |
| Missing policy | `policy` field absent from harness | ERROR |
| Missing agent | `agent` field absent from harness | ERROR |
| Dropped plugins | `plugins` list shorter than upstream | REVIEW |
| Dropped skills | `skills` list shorter than upstream | REVIEW |
| host_files dest changed | `dest` differs from upstream | REVIEW |
| runner_env subset | Customized `runner_env` keys are subset of upstream | REVIEW |
| expand on fixed values | `host_files` entry has `expand: true` but file contains only hardcoded values (no `${}`). Expand is unnecessary and risks accidental substitution | REVIEW |
| missing .env.d dest | `host_files` entry for an env file has `dest` outside `/sandbox/workspace/.env.d/`. File won't be auto-sourced | ERROR |

## Implementation Notes

- Use `diff -u` for a quick visual diff, but also do field-level YAML comparison for the structured report. Read both files and compare key-by-key.
- YAML keys are unordered — don't flag reordering as drift.
- When in doubt about whether a difference is intentional, classify as REVIEW, not ERROR.
