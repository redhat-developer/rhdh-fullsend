# label

Add or remove a label on a GitHub issue or PR.

## Prerequisites

```bash
gh auth status
```
If this fails, stop and ask the user to install and authenticate `gh`.

## Usage

```
/fullsend label <#issue> <add|remove> <label> [--repo owner/name]
```

- `<#issue>`: issue or PR number (with or without `#` prefix)
- `<add|remove>`: action to take
- `<label>`: label name (see common labels below)
- `--repo owner/name`: override repo resolution

### Common fullsend labels

| Label | Purpose |
|-------|---------|
| `triaged` | Issue has been triaged by triage agent or human |
| `ready-to-code` | Issue is ready for the code agent |
| `pr-open` | A PR already addresses this issue |
| `fullsend-no-fix` | Disable bot-triggered fix agent on this PR |
| `requires-manual-review` | Review agent flagged protected-path changes |
| `blocked` | Issue is blocked by a dependency |
| `needs-info` | Issue needs more information from the reporter |
| `workspace/<name>` | Route to a specific monorepo workspace |

## Procedure

### 1. Resolve repo

Follow the repo resolution order from the SKILL.md `<repo_resolution>` section.

### 2. Validate the action

Must be `add` or `remove`. Abort if neither.

### 3. Validate the label exists (for `add` only)

```bash
gh label list --repo <owner/name> --limit 200 --json name \
  --jq '.[].name' | grep -qx "<label>"
```

If the label does not exist, ask the user: "Label `<label>` does not exist in &lt;owner/name&gt;. Create it?"

If yes:
```bash
gh label create "<label>" --repo <owner/name>
```

### 4. Verify the issue exists and show current labels

```bash
gh issue view <N> --repo <owner/name> --json number,title,state,labels \
  -q '"\(.number) \(.state) \(.title)\nLabels: \([.labels[].name] | join(", "))"'
```

### 5. Confirm with user

Present:
```
About to <add|remove> label "<label>" on <owner/name>#<N> (<title>)
Current labels: <label1>, <label2>, ...

Proceed?
```

Do NOT proceed without explicit confirmation.

### 6. Apply the label change

For `add`:
```bash
gh issue edit <N> --repo <owner/name> --add-label "<label>"
```

For `remove`:
```bash
gh issue edit <N> --repo <owner/name> --remove-label "<label>"
```

Note: `gh issue edit` works for both issues and PRs.

### 7. Report

Confirm the change and show the updated label list:
```bash
gh issue view <N> --repo <owner/name> --json labels \
  -q '[.labels[].name] | join(", ")'
```
