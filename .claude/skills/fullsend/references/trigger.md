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

- `<agent>`: one of `code`, `fix`, `triage`, `review`, `retro`, `prioritize`, `debug`
- `<#issue|#PR>`: issue or PR number (with or without `#` prefix)
- `--repo owner/name`: override repo resolution
- `--force`: append `--force` to the comment body (only meaningful for `code`)

## Procedure

### 1. Resolve repo

Follow the repo resolution order from the SKILL.md `<repo_resolution>` section.

### 2. Validate agent name

Map the agent argument to the slash command:

| Agent | Slash command | Dispatch |
|-------|---------------|----------|
| `triage` | `/fs-triage` | built-in |
| `code` | `/fs-code` | built-in |
| `review` | `/fs-review` | built-in |
| `fix` | `/fs-fix` | built-in |
| `retro` | `/fs-retro` | built-in |
| `prioritize` | `/fs-prioritize` | built-in |
| `debug` | `/fs-debug` | custom workflow |

**Built-in agents** are routed through `reusable-dispatch.yml`. **Custom agents** (like `debug`) use their own dispatch workflow — `/fs-debug` triggers `fullsend-debug-dispatch.yml`, which dispatches `fullsend-debug.yml` via `gh workflow run`.

If the `/fs-debug` dispatch fails (common with `GITHUB_TOKEN` permission issues), fall back to direct dispatch:
```bash
gh workflow run fullsend-debug.yml --repo <owner/name> --ref main \
  -f issue_key="<N>" -f issue_source="github"
```

If the agent name is not in this list, abort with "Unknown agent: &lt;name&gt;. Valid agents: code, fix, triage, review, retro, prioritize, debug."

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

**Agent-specific composition:** Each agent has different visibility into the issue/PR context. Use the guidance below to help users write effective instructions.

#### Agent visibility reference

| Agent | Reads | Does NOT read |
|-------|-------|---------------|
| **triage** | Issue title + body + attachments only | Issue comments, PR data, CI logs |
| **code** | Issue body + all issue comments (incl. triage output) + labels + CLAUDE.md + codebase | PR inline review comments, CI logs |
| **review** | PR diff + file contents + linked issue body & comments (for intent) + own prior review body (re-reviews) | PR inline review comments, CI logs, other reviewers' comments |
| **fix** | `HUMAN_INSTRUCTION` text + pre-fetched review body (`review-body.txt`) | CI logs, PR inline comments, issue comments, PR conversation |
| **retro** | PR body + diff + review comments (post-merge) | CI logs |
| **prioritize** | Issue metadata across the repo | Individual issue comments |

No agent reads PR inline review comments (the `pulls/N/comments` API). The review agent *writes* inline comments via the post-script, but never reads existing ones — not even its own from a prior run. On re-reviews, it receives its previous review body as `prior-review.txt`, not the individual inline comments.

#### Composition prompts

**`fix` (instruction required):**
The fix agent is the most context-limited — its only inputs are the text after `/fs-fix` and the pre-fetched review body. If the user has not provided a specific instruction, **ask before posting**:

> "The fix agent can only see what you write after `/fs-fix` — it has no access to CI logs, PR comments, or issue threads. What should it fix?"

Good fix instructions name the failure and the expected fix:
- `CI fails because report.api.md is missing. Run yarn build:api-reports from workspaces/boost/ and commit the generated file.`
- `TypeScript error in src/api.ts:42 — argument type mismatch after the upstream API changed. Update the call to match the new signature.`
- `Prettier check fails. Run yarn prettier --write on the changed files.`

Append their instruction: `BODY = "/fs-fix <instruction>"`. Never post bare `/fs-fix` unless the user explicitly insists.

**`code` (optional focus hints):**
The code agent reads the issue body AND all issue comments (including triage output). If the user provides additional context beyond the issue number, offer to include it as a focus hint:

> "The code agent reads the full issue thread including triage comments. Want to add a focus hint? (e.g., 'focus on the backend plugin only', 'use the existing FooClient class', 'this only affects workspaces/bar'). Or press Enter to post bare `/fs-code`."

If they provide a hint: `BODY = "/fs-code <hint>"`. Bare `/fs-code` is valid — do not block on this.

**`review` (optional focus area):**
The review agent reads the full PR diff, file contents, and linked issue context (body + comments). It does NOT read CI logs or existing PR inline review comments. If the user wants to focus the review, offer:

> "The review agent checks correctness, security, style, and docs by default. Want to narrow the focus? (e.g., 'focus on security', 'check backward compatibility of the API changes', 'ignore formatting'). Or press Enter for a full review."

If they provide a focus: `BODY = "/fs-review <focus>"`. Bare `/fs-review` is valid.

**`triage`, `retro`, `prioritize` (fire-and-forget):**
These agents are fully automatic — they don't accept instructions. Post the bare slash command directly, no prompt needed.

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
