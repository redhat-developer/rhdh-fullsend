# inspect

Investigate a fullsend agent run — pull together status, timing, agent output, and logs into a single report.

## Usage

```
/fullsend inspect <run-id>
/fullsend inspect #<issue-number>
/fullsend inspect
```

- `<run-id>`: GitHub Actions run ID (numeric)
- `#<issue-number>`: find the latest fullsend run triggered by this issue
- No argument: inspect the most recent fullsend run

Default repo: `../rhdh-agentic`. Override with `FULLSEND_REPO` env var or `--repo <owner/name>`.

## Procedure

### 1. Resolve the run

Determine the GitHub repo owner/name and the run ID.

**If run ID given** (bare number):
```bash
gh run view <run-id> --repo <owner/name> --json databaseId,status 2>&1
```
Verify it exists. If not, abort with "Run not found."

**If `#N` given** (issue number):
```bash
gh run list --repo <owner/name> --limit 10 --json databaseId,event,status,conclusion,createdAt \
  --jq '[.[] | select(.event == "issue_comment" or .event == "issues")] | .[0].databaseId'
```
Then cross-reference: fetch issue N's comments for `fullsend:agent-status:<run-id>` anchors. Use the latest matching run ID.

**If no argument**:
```bash
gh run list --repo <owner/name> --limit 5 --json databaseId,event,status,conclusion,createdAt \
  --jq '[.[] | select(.event == "issue_comment" or .event == "issues")] | .[0]'
```
Use the most recent fullsend-triggered run.

### 2. Gather run overview

```bash
gh run view <run-id> --repo <owner/name> \
  --json databaseId,status,conclusion,event,createdAt,updatedAt,jobs,url
```

Extract:
- **Status/conclusion**: `completed/success`, `completed/failure`, `in_progress`, etc.
- **Duration**: compute from `createdAt` → `updatedAt`
- **Trigger event**: `issue_comment`, `issues`, `pull_request`
- **Jobs table**: for each job, extract name, status, conclusion, duration (startedAt → completedAt). Skip jobs with conclusion `skipped` from the duration calculation.

Identify the **agent job** — the one that is NOT `Route` and NOT `stop-fix` and has conclusion != `skipped`. Its name (e.g., `dispatch / Code / Code`) tells you which agent ran.

### 3. Gather agent status comment

Find the triggering issue number. Strategy:
1. If the user passed `#N`, use that.
2. Otherwise, extract from the run's event payload — check the run's `headBranch` or use `gh api repos/<owner/name>/actions/runs/<run-id> --jq '.event'` combined with searching recent issue comments.

Then fetch the status comment:
```bash
gh api repos/<owner/name>/issues/<N>/comments \
  --jq '.[] | select(.body | test("fullsend:agent-status:<run-id>")) | {body, created_at}'
```

Parse from the comment body:
- Agent name and result (Success / Failure)
- Commit SHA (from the `Commit:` backtick)
- Timestamps

If no status comment found, note: "No agent status comment — the run may have failed before posting."

### 4. Check for PR or branch

If a commit SHA was found in step 3:

```bash
# Find branches containing the commit (in the local clone)
cd <repo-path> && git fetch --quiet && git branch -r --contains <sha> 2>/dev/null
```

```bash
# Check for PRs from that branch
gh pr list --repo <owner/name> --state all --head <branch-name> \
  --json number,title,state,url --jq '.[] | "\(.number) \(.state) \(.title)"'
```

Report:
- Branch name and whether it was pushed
- PR number, state (OPEN/CLOSED/MERGED), title, URL
- If no PR exists despite a successful commit: flag as `⚠️ No PR created`

### 5. Download and summarize artifact

```bash
gh api repos/<owner/name>/actions/runs/<run-id>/artifacts \
  --jq '.artifacts[] | {name, size_in_bytes, expired, archive_download_url}'
```

If an artifact exists and `expired == false`:

```bash
# Download to temp dir
TMPDIR=$(mktemp -d)
gh run download <run-id> --repo <owner/name> --name <artifact-name> --dir "$TMPDIR"
```

**Parse `output.jsonl`** (at `$TMPDIR/iteration-1/output.jsonl` or similar):
- Count total conversation turns
- Count tool_use calls by tool name
- Find any `error` or `failure` messages
- Extract the model ID used

**Check sandbox logs** (at `$TMPDIR/logs/`):
- `openshell-sandbox.log`: look for ERROR, FATAL, OOM, timeout
- `openshell-gateway.log`: look for TLS errors, connection failures

Clean up: `rm -rf "$TMPDIR"` after reading.

If artifact expired or missing, note it and skip. If the run is still `in_progress`, artifacts won't be available yet — note this.

### 6. Report

Output a structured report:

```
## Fullsend Run Inspection: <run-id>

### Overview
| Field | Value |
|-------|-------|
| Run | [<run-id>](<url>) |
| Trigger | issue_comment on #<N> |
| Status | <status> / <conclusion> |
| Duration | <Xm Ys> |
| Agent | <agent-name> |

### Jobs
| Job | Status | Duration |
|-----|--------|----------|
| Route | success | 12s |
| Code | success | 2m 42s |
| Review | skipped | — |
| ... | ... | ... |

### Agent Output
- Commit: `<sha>` — <commit message>
- Branch: <branch-name>
- PR: #<N> (<state>) / none
- Status comment: ✅ Success / ❌ Failure

### Artifact Summary
- Turns: <N> | Tool calls: <N> | Errors: <N>
- Model: <model-id>
- Sandbox logs: clean / ⚠️ <issue summary>

### Issues Found
- ⚠️ <any anomalies detected>
```

### Issue detection heuristics

Flag these automatically:

| Condition | Flag |
|-----------|------|
| Run succeeded but no commit SHA in status comment | ⚠️ Success with no output |
| Commit exists but no PR was created | ⚠️ No PR created |
| Run duration > `timeout_minutes` from harness | ⚠️ May have hit timeout |
| Sandbox log contains ERROR/FATAL | ⚠️ Sandbox errors (show excerpts) |
| Artifact is expired | ℹ️ Artifact expired, no transcript available |
| Run is still in progress | ℹ️ Run still in progress, partial data |
| Multiple agent jobs ran (not just one + Route) | ℹ️ Multiple agents dispatched |

If no issues found, end with: **No anomalies detected.**
