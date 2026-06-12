# inspect

Investigate a fullsend agent run — pull together status, timing, agent output, and logs into a single report.

## Prerequisites

Before running any steps, verify `gh` is installed and authenticated:
```bash
gh auth status
```
If this fails, stop and ask the user to install and authenticate `gh`. Every step below depends on it.

## Usage

```
/fullsend inspect <run-id>
/fullsend inspect #<issue-number>
/fullsend inspect
```

- `<run-id>`: GitHub Actions run ID (numeric)
- `#<issue-number>`: find the latest fullsend run triggered by this issue
- No argument: inspect the most recent fullsend run

Repo is resolved using the shared repo resolution order from the SKILL.md `<repo_resolution>` section. Override with `--repo <owner/name>`.

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
git -C <repo-path> fetch --quiet && git -C <repo-path> branch -r --contains <sha> 2>/dev/null
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

**Do NOT clean up `$TMPDIR` yet** — step 5b may need it.

If artifact expired or missing, note it and skip. If the run is still `in_progress`, artifacts won't be available yet — note this.

### 5b. Render transcript in browser (optional)

If `claude-code-transcripts` is installed, offer to render the agent transcript as a browsable HTML page:

```bash
command -v claude-code-transcripts >/dev/null 2>&1 && echo "available" || echo "not installed"
```

If available, find the main transcript JSONL (the full conversation, not `output.jsonl`):

```bash
TRANSCRIPT=$(find "$TMPDIR" -path "*/transcripts/*.jsonl" -type f | head -1)
```

Render and open in the browser:

```bash
claude-code-transcripts json "$TRANSCRIPT" --open
```

The fullsend agent transcripts use the same JSONL format as local Claude Code sessions, so `claude-code-transcripts` renders them without conversion.

If not installed, mention: "Install `pipx install claude-code-transcripts` to render agent transcripts as browsable HTML."

Clean up after rendering (or after step 5c if skipping): `rm -rf "$TMPDIR"`

### 5c. Diagnose agent behavior (when investigating failures)

When the user wants to understand *why* a run failed or produced the wrong result, parse the transcript JSONL for diagnostic signals. Use `output.jsonl` (not the transcript — it's smaller and has the same tool calls).

```bash
OUTPUT=$(find "$TMPDIR" -name "output.jsonl" -path "*/iteration-1/*" | head -1)
```

Run this diagnostic script to extract key signals:

```python
python3 -c "
import json, sys
with open('$OUTPUT') as f:
    lines = [json.loads(l) for l in f]

# --- Extract signals ---
yarn_installs = 0; gh_api_calls = 0; retries = {}; errors = []
human_instruction = None; total_bash = 0; total_turns = 0
for msg in lines:
    if msg.get('type') == 'assistant':
        total_turns += 1
        for c in msg['message'].get('content', []):
            if c.get('type') == 'tool_use' and c.get('name') == 'Bash':
                cmd = c.get('input',{}).get('command','')
                total_bash += 1
                if 'yarn install' in cmd: yarn_installs += 1
                if 'gh api' in cmd: gh_api_calls += 1
                # Track repeated commands (retry detection)
                key = cmd.split('&&')[0].strip()[:60]
                retries[key] = retries.get(key, 0) + 1
    if msg.get('type') == 'user':
        for c in msg['message'].get('content', []):
            text = str(c.get('content',''))
            if 'HUMAN_INSTRUCTION=' in text:
                human_instruction = text.split('HUMAN_INSTRUCTION=')[1].split('\n')[0]
            if any(kw in text.lower() for kw in ['eacces','eai_again','connection refused','permission denied','getaddrinfo','403 forbidden']):
                errors.append(text[:150])

# --- Report ---
print(f'Turns: {total_turns} | Bash calls: {total_bash}')
print(f'HUMAN_INSTRUCTION: {human_instruction}')
print(f'yarn install attempts: {yarn_installs}')
print(f'gh api calls: {gh_api_calls}')
if yarn_installs > 2: print('⚠️  YARN RETRY LOOP: agent retried yarn install {0}x'.format(yarn_installs))
if gh_api_calls > 1 and human_instruction in (None,'none'): print('⚠️  IMPROVISATION: agent scanning comments because inputs were empty')
repeated = [(k,v) for k,v in retries.items() if v > 2]
if repeated: print('⚠️  RETRY LOOPS: ' + ', '.join(f'{k} ({v}x)' for k,v in repeated))
if errors: print('⚠️  SANDBOX ERRORS:'); [print(f'  - {e}') for e in errors[:5]]
if not errors and not repeated and yarn_installs <= 1: print('✅ No diagnostic issues detected')
"
```

#### Diagnostic signals and what they mean

| Signal | What it means | Root cause |
|--------|--------------|------------|
| `yarn install` > 2x | Agent retrying package install in a loop | Sandbox image missing deps or corepack misconfigured. See issue #3362 |
| `gh api` calls + `HUMAN_INSTRUCTION=none` | Agent scanning PR comments because both inputs were empty | Bare `/fs-fix` was posted — always include an instruction |
| `EACCES` in tool results | File permission denied in sandbox | Sandbox policy or image permissions. Check `read_write` paths in policy |
| `EAI_AGAIN` / `getaddrinfo` | DNS resolution failed | Expected in sandbox — see HANDOFF-local-sandbox-dns.md. Use proxy-aware tools |
| `connection refused` on port 53 | Direct DNS query from inner netns | Same DNS issue — tool must go through L7 proxy at `:3128` |
| `403 Forbidden` from proxy | Sandbox policy blocked the request | Binary not in allowlist for that endpoint group. Check policy YAML |
| `permission denied` on `/usr/*` | Write to read-only filesystem path | Sandbox `read_only` policy. Redirect to `/tmp/` or `/sandbox/` |
| Repeated command > 3x | Agent stuck in retry loop | Usually a env/toolchain issue the agent can't fix by retrying |
| High turn count (>80) with no commit | Agent thrashing without progress | Underspecified task or blocked by env issue |

#### Sandbox log patterns

```bash
SANDBOX_LOG=$(find "$TMPDIR" -name "openshell-sandbox.log" | head -1)
```

| grep pattern | Meaning |
|-------------|---------|
| `BLOCKED` | Sandbox policy denied a network request — shows host, binary, policy group |
| `DENIED` | Filesystem or process policy denial |
| `OOM\|Killed\|signal 9` | Agent or subprocess killed — memory limit hit |
| `timeout\|TIMEOUT` | Sandbox or process timeout |
| `ALLOWED.*error` | Request allowed by policy but failed upstream (e.g., registry down) |

```bash
grep -iE 'BLOCKED|DENIED|OOM|Killed|signal 9|TIMEOUT' "$SANDBOX_LOG" | grep -v 'ALLOWED' | head -10
```

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
