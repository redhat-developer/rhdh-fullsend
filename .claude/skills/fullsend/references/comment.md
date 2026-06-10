# comment

Post a comment on a GitHub issue or PR.

## Prerequisites

```bash
gh auth status
```
If this fails, stop and ask the user to install and authenticate `gh`.

## Usage

```
/fullsend comment <#issue> <message> [--repo owner/name]
```

- `<#issue>`: issue or PR number (with or without `#` prefix)
- `<message>`: the comment body text — everything after the issue number (excluding `--repo` flag)
- `--repo owner/name`: override repo resolution

## Procedure

### 1. Resolve repo

Follow the repo resolution order from the SKILL.md `<repo_resolution>` section.

### 2. Parse the message

Extract the issue number and the message body from the arguments. If the message is empty, ask the user what they want to post.

### 3. Verify the issue exists

```bash
gh issue view <N> --repo <owner/name> --json number,title,state \
  -q '"\(.number) \(.state) \(.title)"'
```

Display the title and state.

### 4. Confirm with user

Present:
```
About to comment on <owner/name>#<N> (<title>):

  <message>

Proceed?
```

Do NOT proceed without explicit confirmation.

### 5. Post the comment

```bash
gh issue comment <N> --repo <owner/name> --body "<message>"
```

### 6. Report

Display the comment URL from the output.
