# grillme

General PR grilling agent blueprint. Stress-tests design and architectural
decisions via `/fs-grillme`, one question per turn. Not a code review agent —
decisions and alignment only; correctness/style/security belong to `/fs-review`.

OpenSpec is one useful lens when those artifacts are present — not a requirement.

## Status

Staged in this repo as a blueprint — **not yet wired** into a consuming
fullsend install.

| Location | Path |
|----------|------|
| Blueprint package | `blueprints/agents/grillme/` |
| Install guide | `blueprints/agents/grillme/README.md` |
| Intended consumers | Any RHDH repo with fullsend enabled |

## Usage (after install)

On an open, non-fork PR (plugin code, docs, OpenSpec, etc.):

```
/fs-grillme
```

Continue the session:

```
/fs-grillme <your answer to the last question>
```

### Comment model

- **First turn:** single top-level comment with the opening question.
- **Subsequent turns:** two comments — a short "Recorded" ack, then a new
  top-level comment with the next question.
- **Session close:** summary of decisions reached and remaining gaps.
- **After close:** a new `/fs-grillme` starts a fresh session.

Comments tagged `<!-- fullsend:grillme -->`.

## Architecture

Preferred path: **BYOA + CEL trigger** (no per-agent workflow). Upstream guide:
[Bring Your Own Agent](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/bring-your-own-agent.md).

```
blueprints/agents/grillme/
  agents/grillme.md           ← prompt (read-only, one question/turn)
  harness/grillme.yaml        ← CEL /fs-grillme, review role, base policy
  skills/grilling/SKILL.md    ← general grilling rules (+ OpenSpec when present)
  scripts/pre-grillme.sh      ← validate PR + derive HUMAN_INSTRUCTION
  scripts/post-grillme.sh     ← two-comment split + post as PR comment
  env/grillme.env             ← sandbox env (expand: true)
```

| Piece | Value |
|-------|-------|
| Image | `ghcr.io/fullsend-ai/fullsend-code:latest` (upstream) |
| Policy | `policies/base.yaml` (read-only) |
| Identity | `role: review` / `slug: fullsend-ai-review` (override for other orgs) |
| Dispatch | shim `fullsend.yaml` → harness-dispatch CEL match |

## Propagate to a consuming repo

Follow the copy + `config.yaml` registration steps in
[`blueprints/agents/grillme/README.md`](../../../../blueprints/agents/grillme/README.md).

After merge there, dogfood on any substantial PR — e.g. a new plugin or an
OpenSpec change.

## Related

- Skill source: [agentic-feature-refinement grilling skills](https://github.com/redhat-ai-dev/agentic-feature-refinement/tree/main/.claude/skills)
- Custom agents overview: `references/custom-agents.md`
- Older standalone-workflow example: `references/debug.md`
