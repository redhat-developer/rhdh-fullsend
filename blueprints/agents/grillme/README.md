# grillme agent blueprint

BYOA fullsend agent that stress-tests decisions on a PR via `/fs-grillme`.
Works for code, docs, OpenSpec, or any material change — OpenSpec is one useful
lens when those artifacts are present, not a requirement.

Each invocation is one grill turn: the agent posts a single question (with a
recommended answer) or a closing shared-understanding summary. Engineers
continue the session by commenting `/fs-grillme <answer>`.

**This is not a code review agent.** Grillme pursues *decisions and
architectural alignment*; correctness, style, and security belong to
`/fs-review`.

Source skills adapted from
[redhat-ai-dev/agentic-feature-refinement](https://github.com/redhat-ai-dev/agentic-feature-refinement)
(`.claude/skills/grill-me` / `grilling`).

## Package layout

```
blueprints/agents/grillme/
  agents/grillme.md
  harness/grillme.yaml
  skills/grilling/SKILL.md
  scripts/pre-grillme.sh
  scripts/post-grillme.sh
  env/grillme.env
  README.md
```

## Install into an RHDH repo with fullsend

From the `rhdh-fullsend` checkout, with your target repo as a sibling:

```bash
DEST=../my-rhdh-repo/.fullsend/rhdh

mkdir -p "$DEST"/{agents,harness,skills/grilling,scripts,env}

cp blueprints/agents/grillme/agents/grillme.md          "$DEST/agents/"
cp blueprints/agents/grillme/harness/grillme.yaml        "$DEST/harness/"
cp blueprints/agents/grillme/skills/grilling/SKILL.md    "$DEST/skills/grilling/"
cp blueprints/agents/grillme/scripts/pre-grillme.sh      "$DEST/scripts/"
cp blueprints/agents/grillme/scripts/post-grillme.sh     "$DEST/scripts/"
cp blueprints/agents/grillme/env/grillme.env             "$DEST/env/"

chmod +x "$DEST/scripts/pre-grillme.sh" "$DEST/scripts/post-grillme.sh"
```

### RHDH notes

Harness paths use the `rhdh/` prefix (`rhdh/agents/grillme.md`, etc.) because
RHDH repos require that prefix to avoid scaffold overlay collisions — fullsend
layers upstream defaults into top-level dirs on every run.

`env/gcp-vertex.env` comes from the upstream scaffold layering at workflow time
(top-level `.fullsend/env/`). You do not copy it from this blueprint.

Register the agent in `.fullsend/config.yaml`:

```yaml
agents:
  - name: code
    source: rhdh/harness/code.yaml
  - name: fix
    source: rhdh/harness/fix.yaml
  - name: grillme
    source: rhdh/harness/grillme.yaml
```

### Non-RHDH repos

If you install beside scaffold dirs instead of under `rhdh/`, rewrite path
prefixes in `harness/grillme.yaml` from `rhdh/...` to top-level
(`agents/grillme.md`, `skills/grilling`, `scripts/...`, `env/...`).

### Identity

The harness uses `role: review` / `slug: fullsend-ai-review`. If your org
uses a different review App slug, update `harness/grillme.yaml` before
registering.

## Usage

On an open, non-fork PR:

```
/fs-grillme
```

Answer and continue (reply under the question comment):

```
/fs-grillme We chose single-cluster for now; multi-cluster is a follow-up.
```

### Comment model

- **First turn:** one top-level comment with the opening question.
- **Subsequent turns:** two comments — a short "Recorded" ack, then a new
  top-level comment with the next question (one thread per topic).
- **Session close:** a summary of decisions reached and remaining gaps.
- **After close:** a new `/fs-grillme` starts a fresh session.

Comments are tagged with `<!-- fullsend:grillme -->` so later turns can
reconstruct the session thread.

## Local dry-run

After install, with local fullsend setup:

```bash
export FULLSEND_SANDBOX_IMAGE=ghcr.io/fullsend-ai/fullsend-code:latest
# plus your usual gcp-vertex env

fullsend run grillme \
  --fullsend-dir /path/to/repo/.fullsend \
  --target-repo /path/to/repo \
  --env-file ~/.config/fullsend/gcp-vertex.env \
  --no-post-script
```

## Out of scope (v1)

- Auto-trigger on every PR open (slash-command only)
- Mutating the branch from the agent (human or `/fs-fix`)
- Merge gate / required status check (advisory only)
