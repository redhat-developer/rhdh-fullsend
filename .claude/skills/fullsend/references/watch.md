# watch

Monitor a triggered fullsend run until completion, then auto-inspect it.

## Prerequisites

```bash
gh auth status
```
If this fails, stop and ask the user to install and authenticate `gh`.

## Usage

```
/fullsend watch <#issue|run-id> [--repo owner/name]
```

- `<#issue>`: issue number — find the latest fullsend run triggered by this issue
- `<run-id>`: GitHub Actions run ID (numeric, no `#` prefix)
- `--repo owner/name`: override repo resolution

## Procedure

### 1. Resolve repo

Follow the repo resolution order from the SKILL.md `<repo_resolution>` section.

### 2. Find the run

**If run ID given** (bare number without `#`):
```bash
gh run view <run-id> --repo <owner/name> \
  --json databaseId,status,conclusion,createdAt
```
If not found, abort.

**If `#N` given** (issue number):

Search for the most recent fullsend workflow run associated with this issue:

```bash
gh run list --repo <owner/name> --workflow fullsend --limit 15 \
  --json databaseId,status,conclusion,createdAt,event \
  --jq '[.[] | select(.event == "issue_comment")] | .[0]'
```

If no run found yet (just triggered), tell the user: "No run found yet for #&lt;N&gt;. It may take 10–30 seconds for GitHub Actions to pick it up."

### 3. Check current status

If the run is already `completed`:
- Report the conclusion (success/failure/cancelled).
- Proceed directly to step 5 (auto-inspect).

If the run is `in_progress`, `queued`, or `waiting`:
- Report current status and elapsed time.
- Proceed to step 4 (poll).

### 4. Poll for completion

Use `ScheduleWakeup` to schedule a check in ~90 seconds. The wakeup prompt should:

1. Run `gh run view <run-id> --repo <owner/name> --json status,conclusion`
2. If `completed`: report conclusion, then run the inspect procedure from `references/inspect.md` with this run ID and repo.
3. If still running: report elapsed time, schedule another wakeup.

Inform the user: "Watching run &lt;run-id&gt;. I'll check back in ~90 seconds. You can continue working."

### 5. Auto-inspect

Once the run completes, execute the inspect procedure from `references/inspect.md` with the resolved run ID and repo. This gives the user the full structured report without a second command.

### Timeout

If polling for more than 60 minutes, stop and report: "Run &lt;run-id&gt; has been running for over 60 minutes. It may have stalled. Check manually: &lt;run-url&gt;"
