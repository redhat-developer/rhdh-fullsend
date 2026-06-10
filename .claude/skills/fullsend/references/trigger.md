# trigger

Post a fullsend slash command on a GitHub issue or PR to start an agent run.

## Prerequisites

```bash
gh auth status
```
If this fails, stop and ask the user to install and authenticate `gh`.

## Usage

```
/fullsend trigger <agent> <#issue|#PR> [--repo owner/name] [--force]
```

- `<agent>`: one of `code`, `fix`, `triage`, `review`, `retro`, `prioritize`
- `<#issue|#PR>`: issue or PR number (with or without `#` prefix)
- `--repo owner/name`: override repo resolution
- `--force`: append `--force` to the comment body (only meaningful for `code`)

## Procedure

### 1. Resolve repo

Follow the repo resolution order from the SKILL.md `<repo_resolution>` section.

### 2. Validate agent name

Map the agent argument to the slash command:

| Agent | Slash command |
|-------|---------------|
| `triage` | `/fs-triage` |
| `code` | `/fs-code` |
| `review` | `/fs-review` |
| `fix` | `/fs-fix` |
| `retro` | `/fs-retro` |
| `prioritize` | `/fs-prioritize` |

If the agent name is not in this list, abort with "Unknown agent: &lt;name&gt;. Valid agents: code, fix, triage, review, retro, prioritize."

Also accept the full slash command form (e.g., user types `fs-code` or `/fs-code`); normalize to the agent name.

### 3. Build the comment body

```
BODY = "/fs-<agent>"
```

If `--force` is passed and agent is `code`:
```
BODY = "/fs-code --force"
```

If `--force` is passed for any other agent, warn: "`--force` is only meaningful for the code agent. Ignoring."

### 4. Verify the issue/PR exists

```bash
gh issue view <N> --repo <owner/name> --json number,title,state \
  -q '"\(.number) \(.state) \(.title)"'
```

If it returns nothing, try as a PR:
```bash
gh pr view <N> --repo <owner/name> --json number,title,state \
  -q '"\(.number) \(.state) \(.title)"'
```

Display the title and state to the user for confirmation.

### 5. Confirm with user

Present:
```
About to post on <owner/name>#<N> (<title>):
  <BODY>

Proceed?
```

Do NOT proceed without explicit confirmation. This is a shared-state action visible to the team.

### 6. Post the comment

```bash
gh issue comment <N> --repo <owner/name> --body "<BODY>"
```

Note: `gh issue comment` works for both issues and PRs.

### 7. Report

Display:
- The comment URL (from `gh issue comment` output)
- Suggest: "Use `/fullsend watch #<N>` to monitor the run."
