# custom-agents

RHDH-specific companion to the upstream [Building Custom Agents](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/building-custom-agents.md) guide. Read the upstream guide first for the full 8-step walkthrough (prompt, harness, policy, schemas, scripts, workflows, dispatch). This page covers what's different for RHDH repos and what upstream doesn't address.

## Customize vs build standalone

Two paths to extend fullsend — pick based on what you need:

| Approach | What you change | What you keep | Use when |
|----------|----------------|---------------|----------|
| **Customize a built-in** | Override harness, agent prompt, skills, env, policy in `.fullsend/customized/` | Built-in dispatch, event routing, pre/post scripts | You want the same agent (code, review, fix…) to behave differently |
| **Build a standalone** | Create a new agent with its own workflow + dispatch | Nothing from the built-in chain — you own the full lifecycle | You need an agent that does something the built-ins don't cover |

**Decision tree:**

1. Does a built-in agent already do roughly what you want? → **Customize** (override its harness/prompt/skills)
2. Do you need a new slash command (`/fs-<name>`) for a new capability? → **Build standalone** ([upstream guide](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/building-custom-agents.md))
3. Do you want _only_ custom agents with no built-ins? → **Build standalone** for each, skip the shim workflow. See [Limitations](#limitations).

## RHDH reuse strategy

The upstream guide walks through building everything from scratch. In practice, most RHDH custom agents should **reuse existing infrastructure** rather than creating new images, policies, and env files.

### Reuse the sandbox identity

The debug agent reuses the code agent's sandbox identity — same image, same policy, same host_files. This is deliberate:

```yaml
# harness/debug.yaml — reuses code agent infra
image: ghcr.io/redhat-developer/rhdh-fullsend-code:latest
policy: policies/code.yaml
```

| What to reuse | When to create new |
|---|---|
| **Image** (`rhdh-fullsend-code`) | Only if you need different system packages (e.g., Python toolchain) |
| **Policy** (`policies/code.yaml`) | Only if you need different network endpoints |
| **Env files** (`gcp-vertex.env`, `rhdh-toolchain.env`) | Only if your agent needs different env vars |
| **GCP auth steps** (WIF + credential prep) | Always reuse — same project and provider for all RHDH agents |

### The debug agent as reference

The debug agent (rhdh-agentic) is our canonical worked example. It exercises every piece of the custom agent plumbing while remaining small enough to understand fully:

```
.fullsend/customized/
  agents/debug.md               ← agent prompt (diagnostics only, no mutations)
  harness/debug.yaml            ← reuses code image/policy, 10 min timeout
  scripts/post-debug.sh         ← posts results to issue (untrusted output handling)

.github/workflows/
  fullsend-debug.yml            ← standalone workflow (workspace layering + auth)
  fullsend-debug-dispatch.yml   ← /fs-debug slash-command listener
```

Use this as your starting point. Copy the 5 files, rename `debug` → `<your-agent>`, and modify.

## Custom skills

Skills are the lightest way to extend an agent — no new workflow or dispatch needed.

1. Create `customized/skills/<skill-name>/SKILL.md` with the skill definition
2. Reference it in the agent's harness: `skills: [skills/<skill-name>]`

Example: the `openspec-review` skill adds OpenSpec artifact review to the review agent. It checks artifact sequence (proposal → spec → design → tasks), evaluates quality, and cross-references existing changes — none of which the generic review agent knows about.

Use skills to add domain knowledge to built-in agents. Use standalone agents only when you need a fundamentally different capability.

## Limitations

What custom agents **cannot** do today:

| Limitation | Detail | Workaround |
|------------|--------|------------|
| Can't join the built-in dispatch chain | `reusable-dispatch.yml` hardcodes the 6 built-in agents | Build standalone workflows |
| Can't disable built-in agents | No flag on `fullsend admin install` to suppress built-ins | Skip the shim workflow, use only standalone custom workflows |
| No agent whitelist/blacklist in config | `config.yaml` controls roles (apps), not individual agents | Remove the shim to prevent built-in dispatch; use standalone workflows for customs |
| Slash commands aren't registered | `/fs-<custom>` must be handled by your own dispatch workflow | See upstream guide, Step 8 |

**Custom-only deployments** (no built-in agents): Skip `fullsend admin install` and the `fullsend.yaml` shim. Create standalone workflows for each custom agent. You keep the sandbox infrastructure (image, OpenShell, GCP auth) but own the dispatch plumbing. Trade-off: you lose unified event routing (auto-trigger on PR open, label-based dispatch) and must trigger everything via slash commands or `workflow_dispatch`.

See also: `known-issues.md` → "Custom agent stages not supported in per-repo mode".
