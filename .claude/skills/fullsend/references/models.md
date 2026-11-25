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
| Fleet manifest | `repos.yaml` → `github.repos[].config.models.aliases` (`opus`, `sonnet`, `haiku`) | Every `model: opus\|sonnet\|haiku` the repo's agents ask for. The upstream base harnesses (code, fix, review, triage, retro, prioritize) all say `model: opus` |
| Fleet manifest | `repos.yaml` → `agents[].subagents` on the review agent (e.g. `default: inherit`) | Turns on persona resolution: fullsend runs each upstream review persona's alias (`opus`/`sonnet`/`haiku`) through `models.aliases` and writes the model id into the persona file before the sandbox starts |
| Target repo | `.fullsend/<org>/harness/*.yaml` `model:` | Custom agents with no upstream base. Use the alias (`model: opus`) so the manifest stays the one source |
| Target repo | Agent / skill text such as "pass `model: \"claude-opus-5-5\"`" | Ad-hoc sub-agents the agent spawns itself (not upstream personas). `models.aliases` cannot reach these; they carry the id literally |

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

A pinned id never moves on its own. A new fullsend release can change the
built-in defaults, but `models.aliases` overrides them. The fleet moves only
when someone changes `repos.yaml` and runs install.

`FULLSEND_FALLBACK_MODELS` sets an explicit fallback chain, but it is a
runner environment variable. Neither `repos.yaml` nor the shim sets it, so do
not count on it.

## Procedure: move to a new model

### 1. Check enablement first

All WIF-enabled repos in both orgs (including `rhdh-parasol`) use one GCP
project, `rhdh-sidekick-167988`. A model must be enabled there before any
repo pins it. Check the "Enabled partner models" table in
`docs/gcp-infrastructure.md`. If it is missing, run `/fullsend enable-model <id>`
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
time with a repo filter. Since v0.57, installs write `config.trace_context`
back to `repos.yaml`, so run them from a writable checkout of this repo and
commit the write-backs. Re-apply the shim customizations (`upgrade.md`,
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
4. **`subagents.default` applies only to personas that name no model.** All
   upstream personas name one, so `default: inherit` turns resolution on
   without changing any persona's model.
5. **A live `subagents:` entry limits the agent to persona sub-agents.** With it
   on, the review agent starts only the registered personas. On parasol it
   skipped an ad-hoc "label-conventions" sub-agent ("sub-agents may only be
   started from the persona files"). Check review output for anything you
   relied on that is not a persona.
