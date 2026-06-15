# custom-agents

Guide for building custom fullsend agents. Uses the **debug agent** (rhdh-agentic) as a worked example throughout.

## Customize vs build standalone

Two paths to extend fullsend — pick based on what you need:

| Approach | What you change | What you keep | Use when |
|----------|----------------|---------------|----------|
| **Customize a built-in** | Override harness, agent prompt, skills, env, policy in `.fullsend/customized/` | Built-in dispatch, event routing, pre/post scripts | You want the same agent (code, review, fix…) to behave differently |
| **Build a standalone** | Create a new agent with its own workflow + dispatch | Nothing from the built-in chain — you own the full lifecycle | You need an agent that does something the built-ins don't cover |

**Decision tree:**

1. Does a built-in agent already do roughly what you want? → **Customize** (override its harness/prompt/skills)
2. Do you need a new slash command (`/fs-<name>`) for a new capability? → **Build standalone**
3. Do you want _only_ custom agents with no built-ins? → **Build standalone** for each, skip the shim workflow. See [Limitations](#limitations).

## The 5-file scaffold

Every standalone custom agent needs these files:

```
.fullsend/customized/
  agents/<name>.md               ← agent prompt (YAML frontmatter + markdown)
  harness/<name>.yaml            ← sandbox config (image, policy, host_files, timeout)
  scripts/post-<name>.sh         ← (optional) trusted runner post-processing

.github/workflows/
  fullsend-<name>.yml            ← standalone agent workflow
  fullsend-<name>-dispatch.yml   ← slash-command listener (/fs-<name>)
```

No changes to `config.yaml` needed — `fullsend run` does not validate config.yaml roles for standalone workflows.

## Harness config anatomy

Annotated example from the debug agent (`harness/debug.yaml`):

```yaml
# The agent prompt — path relative to .fullsend/ (after layering)
agent: agents/debug.md
model: opus

# Reuse an existing agent's image and policy when possible.
# Building from a proven base avoids re-solving sandbox toolchain issues.
image: ghcr.io/redhat-developer/rhdh-fullsend-code:latest
policy: policies/code.yaml

# Post-script runs on the trusted runner AFTER sandbox cleanup.
# Agent output is untrusted — see "Post-script security" below.
post_script: scripts/post-debug.sh

host_files:
  # expand: true — runner-side env vars (${RUNNER_VAR}) are resolved
  # before the file is copied into the sandbox
  - src: env/gcp-vertex.env
    dest: /sandbox/workspace/.env.d/gcp-vertex.env
    expand: true
  - src: env/code-agent.env
    dest: /sandbox/workspace/.env.d/code-agent.env
    expand: true

  # No expand — hardcoded values that don't reference runner env
  - src: env/rhdh-toolchain.env
    dest: /sandbox/workspace/.env.d/rhdh-toolchain.env

  # Credential files — dest outside /sandbox/workspace/ is fine
  - src: ${GOOGLE_APPLICATION_CREDENTIALS}
    dest: /tmp/.gcp-credentials.json

  # optional: true — file may not exist (e.g., OIDC token in some envs)
  - src: ${GCP_OIDC_TOKEN_FILE}
    dest: /sandbox/workspace/.gcp-oidc-token
    optional: true

# runner_env — available on the GitHub Actions runner only,
# never inside the sandbox. Used by pre/post scripts.
runner_env:
  REPO_FULL_NAME: "${REPO_FULL_NAME}"
  ISSUE_NUMBER: "${ISSUE_NUMBER}"
  RUN_URL: "${RUN_URL}"
  GH_TOKEN: "${GH_TOKEN}"

timeout_minutes: 10
```

### Key decisions

| Decision | Guidance |
|----------|----------|
| **Image** | Reuse an existing custom image when your agent needs the same toolchain. Building a new image is only worth it if you need different system packages. |
| **Policy** | Reuse an existing policy unless your agent needs different network endpoints. |
| **`expand: true`** | Only on files containing `${RUNNER_VAR}` references. Omit for hardcoded values — expanding would replace literal `${PATH}` with the runner's PATH. |
| **`runner_env` vs `host_files`** | `runner_env` stays on the runner (for pre/post scripts). `host_files` enter the sandbox. Never put secrets in `host_files` without `expand: true` gating them behind runner-side env vars. |
| **`optional: true`** | Use for files that may not exist in all environments (OIDC tokens, optional configs). Without it, a missing file fails the sandbox setup. |

## Workspace layering

Standalone workflows don't get the built-in dispatch's workspace layering for free. Every standalone workflow must replicate this pattern in a "Prepare workspace" step:

```yaml
- name: Checkout upstream defaults
  uses: actions/checkout@v6
  with:
    repository: fullsend-ai/fullsend
    ref: v0
    path: .defaults
    sparse-checkout: |
      internal/scaffold/fullsend-repo/
      .github/actions/
      .github/scripts/

- name: Prepare workspace
  run: |
    set -euo pipefail
    SRC=".defaults/internal/scaffold/fullsend-repo"
    LAYERED_DIRS="agents skills schemas harness policies scripts env"
    # Step 1: Copy scaffold defaults
    for dir in ${LAYERED_DIRS}; do
      if [[ -d "${SRC}/${dir}" ]]; then
        mkdir -p ".fullsend/${dir}"
        cp -r "${SRC}/${dir}/." ".fullsend/${dir}/"
      fi
    done
    # Step 2: Overlay customized/ on top (full file replacement)
    for dir in ${LAYERED_DIRS}; do
      if [[ -d ".fullsend/customized/${dir}" ]]; then
        find ".fullsend/customized/${dir}" -type f ! -name '.gitkeep' -print0 \
          | while IFS= read -r -d '' f; do
              rel="${f#".fullsend/customized/"}"
              mkdir -p ".fullsend/$(dirname "${rel}")"
              cp "${f}" ".fullsend/${rel}"
            done
      fi
    done
    # Step 3: Copy shared scripts
    mkdir -p .github/scripts scripts
    cp "${SRC}/.github/scripts/setup-agent-env.sh" \
       .github/scripts/setup-agent-env.sh 2>/dev/null || true
    cp "${SRC}/scripts/prepare-sandbox-credentials.sh" \
       scripts/prepare-sandbox-credentials.sh 2>/dev/null || true
```

**Why this exists:** The `.fullsend/customized/` directory contains only overrides. The scaffold defaults provide the base. The layering step merges them into a flat `.fullsend/` directory that `fullsend run` consumes. Without it, any file you didn't override (like a shared env file or script) would be missing.

## Dispatch workflow pattern

The dispatch workflow listens for `/fs-<name>` comments and triggers the standalone workflow:

```yaml
name: fullsend-<name>-dispatch

permissions:
  actions: write
  contents: read
  issues: write

on:
  issue_comment:
    types: [created]

jobs:
  dispatch:
    if: >-
      github.event.comment.user.type != 'Bot'
      && startsWith(github.event.comment.body, '/fs-<name>')
    runs-on: ubuntu-latest
    steps:
      - name: Dispatch workflow
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          ISSUE_NUMBER: ${{ github.event.issue.number }}
          REPO: ${{ github.repository }}
        run: |
          gh workflow run fullsend-<name>.yml \
            --repo "$REPO" \
            --ref main \
            -f issue_key="$ISSUE_NUMBER" \
            -f issue_source="github"

          # Visual feedback — rocket reaction on the triggering comment
          gh api "repos/${REPO}/issues/comments/${{ github.event.comment.id }}/reactions" \
            -f content="rocket" --silent 2>/dev/null || true
```

### Key details

- **`--ref main`** is required. Without it, `gh workflow run` calls GraphQL to resolve the default branch, which can fail with `GITHUB_TOKEN` permission issues.
- **Bot filter** (`user.type != 'Bot'`) prevents infinite loops if another bot posts the slash command.
- **Rocket reaction** gives immediate visual feedback that the dispatch was received.
- **Concurrency** — add to the standalone workflow (not the dispatch): `concurrency: { group: "<name>-${{ inputs.issue_key }}", cancel-in-progress: true }`.

## Post-script security

Post-scripts run on the trusted runner after sandbox cleanup. The agent's output is **untrusted** — a compromised or confused agent could produce strings that exploit shell expansion. Four rules:

| Rule | Why | How |
|------|-----|-----|
| Extract via `jq` | Prevents shell interpretation of agent strings | `jq -r 'select(.type == "assistant") \| .message.content[]? \| select(.type == "text") \| .text' output.jsonl` |
| Truncate output | GitHub comment limit is 65536 chars; agent may dump unbounded text | `SUMMARY="${SUMMARY:0:60000}"` |
| Post via `--body-file -` | Piped stdin avoids shell interpolation of the content | `printf '%s' "$COMMENT" \| gh issue comment "$N" --repo "$REPO" --body-file -` |
| Validate inputs | Issue number and repo name come from env (attacker-controlled in public repos) | `[[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]` and `[[ "$REPO" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]` |

## Custom skills

Skills add domain-specific capabilities to any agent (built-in or custom). To add a custom skill:

1. Create `customized/skills/<skill-name>/SKILL.md` with the skill definition
2. Reference it in the agent's harness: `skills: [skills/<skill-name>]`

Example: the `openspec-review` skill adds OpenSpec artifact review to the review agent. It checks artifact sequence (proposal → spec → design → tasks), evaluates quality, and cross-references existing changes — none of which the generic review agent knows about.

Skills are the lightest way to extend an agent — no new workflow or dispatch needed.

## Limitations

What custom agents **cannot** do today:

| Limitation | Detail | Workaround |
|------------|--------|------------|
| Can't join the built-in dispatch chain | `reusable-dispatch.yml` hardcodes the 6 built-in agents | Build standalone workflows |
| Can't disable built-in agents | No flag on `fullsend admin install` to suppress built-ins | Skip the shim workflow, use only standalone custom workflows |
| No agent whitelist/blacklist in config | `config.yaml` controls roles (apps), not individual agents | Remove the shim to prevent built-in dispatch; use standalone workflows for customs |
| Slash commands aren't registered | `/fs-<custom>` must be handled by your own dispatch workflow | See [Dispatch workflow pattern](#dispatch-workflow-pattern) |

**Custom-only deployments** (no built-in agents): Skip `fullsend admin install` and the `fullsend.yaml` shim. Create standalone workflows for each custom agent. You keep the sandbox infrastructure (image, OpenShell, GCP auth) but own the dispatch plumbing. Trade-off: you lose unified event routing (auto-trigger on PR open, label-based dispatch) and must trigger everything via slash commands or `workflow_dispatch`.

See also: `known-issues.md` → "Custom agent stages not supported in per-repo mode".
