# custom-agents

RHDH-specific companion to upstream fullsend agent guides. Prefer
[Bring Your Own Agent](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/bring-your-own-agent.md)
(BYOA + CEL triggers) for new slash-command agents. The older
[Building Custom Agents](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/building-custom-agents.md)
standalone-workflow walkthrough still describes the debug-agent pattern.

## Customize vs BYOA vs standalone workflow

| Approach | What you change | What you keep | Use when |
|----------|----------------|---------------|----------|
| **Customize a built-in** | Override harness, agent prompt, skills, env, policy under `.fullsend/rhdh/` (or legacy `customized/`) | Built-in dispatch + stage routing | Same agent (code, review, fix…) should behave differently |
| **BYOA (preferred for new `/fs-*`)** | New harness + agent + scripts; register in `config.yaml` with a CEL `trigger` | Shim `fullsend.yaml` harness-dispatch | New capability with a slash command or label trigger |
| **Standalone workflow** | Dedicated `fullsend-<name>.yml` + `*-dispatch.yml` | Nothing from built-in/CEL chain | You must own the full lifecycle, or BYOA is unavailable |

**Decision tree:**

1. Does a built-in agent already do roughly what you want? → **Customize**
2. Do you need a new `/fs-<name>` (or label) trigger? → **BYOA** (stage under `blueprints/agents/` in rhdh-fullsend first)
3. Is BYOA blocked for your install mode? → **Standalone workflow** (debug pattern)

## RHDH reuse strategy

Most RHDH custom agents should **reuse existing infrastructure** rather than
creating new images, policies, and env files.

### Reuse the sandbox identity

```yaml
image: ghcr.io/redhat-developer/rhdh-fullsend-code:latest
policy: rhdh/policies/code.yaml   # or policies/base.yaml / policies/code.yaml
providers:
  - vertex-ai
  - github
  - package-registries
```

| What to reuse | When to create new |
|---|---|
| **Image** (`rhdh-fullsend-code`) | Only if you need different system packages |
| **Policy** (`policies/code.yaml`) | Only if you need different network endpoints |
| **Env files** (`gcp-vertex.env`, `rhdh-toolchain.env`) | Only if your agent needs different env vars |
| **GCP auth / mint** | Always reuse — same project and provider for all RHDH agents |
| **GitHub App role** | Reuse `review` for comment-only agents; `coder` for pushers |

## Canonical examples

### grillme (BYOA + CEL) — preferred template

Staged in this repo at [`blueprints/agents/grillme/`](../../../../blueprints/agents/grillme/).
General PR grilling via `/fs-grillme`, one question per comment turn (code,
docs, OpenSpec when present, etc.).

```
blueprints/agents/grillme/
  agents/grillme.md
  harness/grillme.yaml          ← trigger on /fs-grillme, role: review
  skills/grilling/SKILL.md
  scripts/pre-grillme.sh
  scripts/post-grillme.sh       ← untrusted-output PR comment
  env/grillme.env
```

CEL trigger shape:

```yaml
trigger: >
  event.transition.kind == "comment_added"
    && has(event.transition.comment.command)
    && event.transition.comment.command == "/fs-grillme"
    && event.state.change_proposal != null
    && !event.state.change_proposal.is_fork
```

Register after copy:

```yaml
# .fullsend/config.yaml
agents:
  - name: grillme
    source: rhdh/harness/grillme.yaml
```

See `references/grillme.md` and the package README for install/dogfood steps.
**Not live in rhdh-plugins until propagated.**

### debug (standalone workflow) — legacy reference

The debug agent (historically on rhdh-agentic) exercises a dedicated workflow +
slash-command dispatch outside CEL harness-dispatch:

```
.fullsend/
  agents/debug.md
  harness/debug.yaml
  scripts/post-debug.sh

.github/workflows/
  fullsend-debug.yml
  fullsend-debug-dispatch.yml   ← /fs-debug listener
```

Use this only when you cannot register a CEL-triggered harness. Details:
`references/debug.md`.

## Custom skills

Skills are the lightest way to extend an agent — no new workflow needed.

1. Create `skills/<skill-name>/SKILL.md` (under `rhdh/` or blueprint package)
2. Reference it in the harness: `skills: [rhdh/skills/<skill-name>]`

Example: an `openspec-review` skill on the built-in review agent adds OpenSpec
artifact sequence/quality checks without a new `/fs-*` command.

Use skills to add domain knowledge to existing agents. Use BYOA when you need a
fundamentally different capability or interaction model (like grillme's
multi-turn PR interview).

### Remote skill URLs need two allowlists

URL skills (e.g. from `redhat-developer/rhdh-skill`) fail with
`URL ... is not in allowed_remote_resources` unless **both** are set:

1. **Harness** `allowed_remote_resources` — used when resolving skill URLs.
   Not inherited from `base:` or from `config.yaml`.
2. **Repo** `.fullsend/config.yaml` `allowed_remote_resources` — org allowlist
   that must cover every harness prefix.

```yaml
# .fullsend/rhdh/harness/code.yaml
skills:
  - https://github.com/redhat-developer/rhdh-skill/tree/<sha>/skills/rhdh-coding#sha256=...
allowed_remote_resources:
  - https://github.com/redhat-developer/rhdh-skill/

# .fullsend/config.yaml
allowed_remote_resources:
  - https://raw.githubusercontent.com/fullsend-ai/fullsend/
  - https://raw.githubusercontent.com/fullsend-ai/agents/
  - https://github.com/redhat-developer/rhdh-skill/
```

`config.yaml` alone is not enough — that was the gap behind the
`rhdh-coding` dispatch failures after #4096.

## Staging in rhdh-fullsend

Shared agent packages land under `blueprints/agents/<name>/` first, then
propagate to consuming repos (see [`blueprints/README.md`](../../../../blueprints/README.md)).

1. Author/fix the blueprint here
2. Copy into the target repo's `.fullsend/rhdh/` (or top-level) layout
3. Register in that repo's `config.yaml`
4. Dogfood with the slash command on a real PR

## Limitations

| Limitation | Detail | Workaround |
|------------|--------|------------|
| Built-in stage table is fixed | `reusable-dispatch.yml` stage jobs are triage/code/review/fix/retro/prioritize | BYOA harness-dispatch coexists via CEL; or standalone workflows |
| Can't disable built-in agents easily | No install flag to suppress built-ins | Skip shim for custom-only; or ignore unused roles |
| Per-org install CEL routing | Custom harness agents are not routed by per-org managed dispatch | Use per-repo install for BYOA customs |
| Mint slug must exist | `role` / `slug` must be mintable | Reuse `review` or `coder`; or standalone mint |

**Custom-only deployments:** Skip `fullsend admin install` and the shim; use
standalone workflows only. Trade-off: no unified event routing.

## Security: post-scripts and untrusted output

Agents run in an untrusted sandbox. Post-scripts on the runner must:

- Extract text via `jq` (no shell eval of agent strings)
- Truncate to ≤60k chars
- Post via `--body-file -`
- Validate `ISSUE_NUMBER` / `PR_NUMBER` as numeric and `REPO_FULL_NAME` as `owner/repo`

See `blueprints/agents/grillme/scripts/post-grillme.sh` and the debug
post-script pattern in `references/debug.md`.
