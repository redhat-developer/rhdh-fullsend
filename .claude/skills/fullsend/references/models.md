# models

How the fleet's agent models are pinned, how a pin reaches each repo, and how
to move to a new model safely.

## Usage

```
/fullsend models [new-model-id]
```

- No argument: show where each managed repo's models come from (step 1 of the procedure).
- `new-model-id`: e.g. `claude-opus-5-6`. Walk through the change procedure.

## Where models are set

| Layer | Where | What it pins |
|-------|-------|--------------|
| Fleet manifest | `repos.yaml` → `github.repos[].config.models.aliases` (`opus`, `sonnet`, `haiku`) | Every `model: opus\|sonnet\|haiku` the repo's agents ask for. At v0.57.1 every upstream base harness asked for `opus`; check the release you pin (below) |
| Fleet manifest | `repos.yaml` → `agents[].subagents` on the review agent (e.g. `default: inherit`) | Turns on persona resolution: fullsend runs each upstream review persona's alias (`opus`/`sonnet`/`haiku`) through `models.aliases` and writes the model id into the persona file before the sandbox starts |
| Target repo | `.fullsend/<org>/harness/*.yaml` `model:` | Custom agents with no upstream base. Use the alias (`model: opus`) so the manifest stays the one source |
| Target repo | Agent / skill text such as "pass `model: \"claude-opus-5-5\"`" | Ad-hoc sub-agents the agent spawns itself (not upstream personas). `models.aliases` cannot reach these; they carry the id literally |

Which aliases the upstream harnesses and review personas ask for can change
with any agents release. Check at the agents commit your harnesses pin:

```bash
SHA=<agents commit from the harness base: pins>
for a in code fix review triage retro prioritize; do
  echo "$a: $(curl -fsSL https://raw.githubusercontent.com/fullsend-ai/agents/$SHA/harness/$a.yaml | grep -m1 '^model:')"
done
# review personas (path at v0.57.1; search the tree for the persona names if it moved)
for p in $(gh api "repos/fullsend-ai/agents/contents/skills/pr-review/sub-agents?ref=$SHA" --jq '.[].name'); do
  echo "$p: $(curl -fsSL https://raw.githubusercontent.com/fullsend-ai/agents/$SHA/skills/pr-review/sub-agents/$p | grep -m1 '^model:')"
done
```

`models.aliases` reaches sub-agents only when the agent has a live
`subagents:` entry. Without one, Claude Code resolves persona aliases with its
own table. Do not add `subagents:` to an agent that has no personas: the run
fails with "no persona was registered".

## How a pin reaches a repo

1. `repos.yaml` is where the decision lives. On its own it changes nothing at run time.
2. `fullsend repos install -f repos.yaml <org>/<repo>` renders the repo's
   `.fullsend/config.yaml` (the managed file, marked "Do not edit") and opens a
   scaffold PR. The pin is live once that PR merges.
3. At run time fullsend reads only the target repo's `.fullsend/config.yaml`
   on its default branch. It never reads this repo.

So:
- `repos.yaml` changed but no install run: the repo keeps its old models.
  `fullsend repos status` shows the drift.
- A hand edit to the managed `config.yaml` is overwritten by the next install.
  If you must change it in a PR first, make it byte-for-byte what install
  would render from `repos.yaml`.

## Pin semantics (fullsend v0.57)

| Setting | Runs on | If Vertex does not serve the model |
|---------|---------|------------------------------------|
| Bare alias, no `models.aliases` entry | fullsend's built-in default (v0.57.1: `opus` → `claude-opus-5-5`, `sonnet` → `claude-sonnet-5-5`, `haiku` → `claude-haiku-5-5`) | Silent fallback to the previous default (`claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5`) |
| Alias remapped with `models.aliases` | The pinned id | **No fallback: the run fails** |
| Explicit model id | That id | **No fallback: the run fails** |

The defaults and fallbacks above are v0.57.1's. Check them for the version
you run in `internal/runtime/model_defaults.go` at that tag.

A pinned id never moves on its own. A new fullsend release can change the
built-in defaults, but `models.aliases` overrides them. The fleet moves only
when someone changes `repos.yaml` and runs install.

`FULLSEND_FALLBACK_MODELS` sets an explicit fallback chain, but it is a
runner environment variable. Neither `repos.yaml` nor the shim sets it, so do
not count on it.

## Procedure: move to a new model

### 1. Check enablement first

A model must be enabled in the GCP project the repos run inference in before
any repo pins it. `docs/gcp-infrastructure.md` names that project (at the
v0.57.1 rollout, one project served every WIF repo in both orgs, so a parasol
pass proved enablement for production too; check that is still true) and
has the "Enabled partner models" table. If it is missing, run `/fullsend enable-model <id>`
first. Do this for every alias you pin, not only `opus`: review personas also
ask for `sonnet` and `haiku`.

### 2. Change `repos.yaml`

In a PR to this repo, set `models.aliases` for the pilot entry (the
`rhdh-parasol/*` mirror of the target repo) to the new id.

### 3. Rehearse on the parasol mirror

1. `fullsend repos install -f repos.yaml rhdh-parasol/<repo>`, then review and merge the scaffold PR.
2. Run the agents that repo uses: `/fs-review` on a same-repo PR, `/fs-diagnose`, and `/fs-code` on a small issue.
3. Check the run logs:
   - `model: alias "opus" remapped to "<id>" from … models.aliases`
   - `→ Agent: <id> (v<claude-code-version>)`
   - `subagents: <persona> → <id> (from …)` for each review persona
4. In the run artifacts, the per-transcript `.message.model` values should
   all be pinned ids:
   ```bash
   gh run download <run-id> --repo rhdh-parasol/<repo> -D /tmp/run
   find /tmp/run -path '*transcripts*' -name '*.jsonl' \
     -exec jq -r 'select(.type=="assistant")|.message.model' {} + | sort | uniq -c
   ```
5. A model that is not enabled fails here, before production.

### 4. Roll out

Update the production entries in `repos.yaml`, then install one repo at a
time with a repo filter, from a writable checkout of this repo. Commit
anything install writes back to `repos.yaml` (see `upgrade.md` 5d). Re-apply the shim customizations (`upgrade.md`,
"Shim customizations") on every scaffold PR.

### 5. Update the literal ids

Search each target repo for the old id (`git grep -n "<old-id>"`) and update
the ad-hoc sub-agent instructions in its agent and skill files.

### 6. Record it

Update the per-agent model table in `docs/gcp-infrastructure.md`.

## Known gotchas

1. **The managed file is per repo.** Changing one entry in `repos.yaml` pins
   only that repo. Production and `rhdh-parasol` entries are separate.
2. **No fallback on pins.** If Google retires or disables a pinned model,
   every agent on it fails until `repos.yaml` changes and install runs.
3. **Review personas are tiered.** Upstream assigns `opus`, `sonnet` and
   `haiku`. Pinning only `opus` leaves the rest on Claude Code's own table.
4. **`subagents.default` applies only to personas that name no model.** At
   v0.57.1 every upstream persona named one, so `default: inherit` turned
   resolution on without changing any persona's model. Re-check the personas
   after an agents bump (command above): a persona without a model would get
   the parent's.
5. **A live `subagents:` entry limits the agent to persona sub-agents.** With it
   on, the review agent starts only the registered personas. On parasol it
   skipped an ad-hoc "label-conventions" sub-agent ("sub-agents may only be
   started from the persona files"). Check review output for anything you
   relied on that is not a persona.
