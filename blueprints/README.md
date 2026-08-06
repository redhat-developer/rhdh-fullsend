# Blueprints

Canonical source of truth for shared fullsend customization files used across
multiple RHDH repositories. Fix bugs and evolve files here first, then
propagate to each consuming repo.

## Consuming repos

| Blueprint | rhdh-plugins | rhdh-overlays | rhdh-agentic |
|-----------|:---:|:---:|:---:|
| `scripts/pre-fix-rebase.sh` | yes | yes | yes |
| `env/rhdh-toolchain.env` | yes | - | yes |
| `env/yarn-proxy.env` | yes | - | yes |
| `policies/code.yaml` | yes | - | yes |
| `agents/grillme/` | — (intended first install) | - | - |

## Agent blueprints

Full agent packages (prompt, harness, skills, pre/post scripts) live under
`agents/<name>/`. Stage them here, then copy into a consuming repo's
`.fullsend/` tree and register in `config.yaml`.

| Agent | Slash command | Purpose | Install guide |
|-------|---------------|---------|---------------|
| [`agents/grillme/`](agents/grillme/) | `/fs-grillme` | One-question-per-turn grilling on PRs (code, docs, OpenSpec, …) | [agents/grillme/README.md](agents/grillme/README.md) |

## How to sync

Compare a repo's installed copy against the blueprint:

```bash
diff blueprints/scripts/pre-fix-rebase.sh \
  ../rhdh-plugins/.fullsend/customized/scripts/pre-fix-rebase.sh
```

If the diff is non-empty, copy the blueprint into the repo:

```bash
cp blueprints/scripts/pre-fix-rebase.sh \
  ../rhdh-plugins/.fullsend/customized/scripts/pre-fix-rebase.sh
```

For agent packages, follow the package README (path layout differs from flat
script/env blueprints).

## Rules

1. **Edit here first.** Never fix a shared file directly in a consuming repo
   without updating the blueprint.
2. **Propagate promptly.** After changing a blueprint, update every consuming
   repo listed in the table above.
3. **Intentional divergence is fine** — if a repo needs a repo-specific
   variant, note it in this table (replace "yes" with a short explanation).
