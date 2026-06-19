# Blueprints

Canonical source of truth for shared fullsend customization files used across
multiple RHDH repositories. Fix bugs and evolve files here first, then
propagate to each consuming repo.

## Consuming repos

| Blueprint | rhdh-plugins | rhdh-overlays | rhdh-agentic |
|-----------|:---:|:---:|:---:|
| `scripts/pre-fix-rebase.sh` | yes | yes | - |
| `env/rhdh-toolchain.env` | yes | - | yes |
| `policies/code.yaml` | yes | - | yes |

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

## Rules

1. **Edit here first.** Never fix a shared file directly in a consuming repo
   without updating the blueprint.
2. **Propagate promptly.** After changing a blueprint, update every consuming
   repo listed in the table above.
3. **Intentional divergence is fine** — if a repo needs a repo-specific
   variant, note it in this table (replace "yes" with a short explanation).
