# upgrade

Upgrade the fullsend CLI, then roll the scaffold workflow ref through
`repos.yaml`. Every forge change lands as a PR — never `--direct`.

## Usage

```
/fullsend upgrade [target-version]
```

- `target-version`: e.g. `v0.37.0`. Default: latest release on fullsend-ai/fullsend.

## Prerequisites

| Gate | Check | If fail |
|------|-------|---------|
| `repos.yaml` | this repo's fleet manifest | Stop — the file is required |
| `gh` CLI | `gh auth status` | Ask user to authenticate |
| `fullsend` CLI | `fullsend --version` | Download from GitHub releases |

Official path: [Rolling out a new fullsend version](https://fullsend.sh/docs/guides/getting-started/repo-management#rolling-out-a-new-fullsend-version).

## Procedure

### 1. Determine versions

```bash
fullsend --version
gh release list --repo fullsend-ai/fullsend --limit 3
grep fullsend_ref repos.yaml
```

Show the user: current CLI version, current `github.fullsend_ref`, and target
version. Confirm before proceeding.

### 2. Upgrade CLI binary

```bash
VERSION=<target>   # without the leading v, e.g. 0.37.0
gh release download "v${VERSION}" --repo fullsend-ai/fullsend \
  --pattern "fullsend_${VERSION}_darwin_arm64.tar.gz" -D /tmp

OLD_VERSION=$(fullsend --version | awk '{print $3}')
cp ~/.local/bin/fullsend ~/.local/bin/fullsend.${OLD_VERSION}.bak

tar xzf "/tmp/fullsend_${VERSION}_darwin_arm64.tar.gz" -C ~/.local/bin/ fullsend
chmod +x ~/.local/bin/fullsend
fullsend --version
```

### 3. Bump the fleet manifest

In `repos.yaml`, set `github.fullsend_ref` to the target tag (e.g. `v0.37.0`).
Open a PR in **this** repo (`rhdh-fullsend`). Do not push to `main`.

The fleet uses public mint (`https://mint.fullsend.sh`). Verify `mint_url`
in `repos.yaml` stays set to that after the upgrade.

### 4. Converge target repos (PRs only)

Dry-run first, then install **without** `--direct`:

```bash
fullsend repos install -f repos.yaml --dry-run
fullsend repos install -f repos.yaml redhat-developer/rhdh-agentic
```

Omit the repo filter to converge every entry in the manifest.

`repos install` on an already-installed repo:

- Refreshes `.github/workflows/fullsend.yaml` and thin callers (`prioritize.yml`)
- Upgrades the `reusable-dispatch.yml` pin (`@<sha> # vX.Y.Z` stays SHA-pinned)
- Reconciles mint URL / region variables from the manifest
- **Does not rewrite** `.fullsend/config.yaml` (custom `agents:` stay)
- **Does not update** custom `base:` harness URLs under `.fullsend/`; pin
  those to the matching `fullsend-ai/agents` release and verify their SHA-256
  hashes in each affected repo before running the new workflow
- **Does not delete** leftover `.fullsend/customized/` trees — remove those
  in the same scaffold PR if they are empty `.gitkeep` placeholders (ADR 0064)

Review each scaffold PR before merge. Do not use `--direct`.

### 5. Rebuild sandbox image if needed

Check whether the upstream base image changed:

```bash
git -C /Users/mhild/src/fullsend-ai/fullsend diff $OLD..$NEW -- images/code/Containerfile
```

Our Containerfile extends `ghcr.io/fullsend-ai/fullsend-code:latest`. Tool
upgrades come from the base image automatically. Only change our Containerfile
if the pinned yarn version changed or we need to add/remove tools.

CI auto-builds on push to `main` when `images/code/**` **or** `repos.yaml`
changes. Bumping `github.fullsend_ref` is therefore enough to pick up the new
upstream `fullsend-code` base — no Containerfile change and no manual
`workflow_dispatch` required. Keep `workflow_dispatch` for an out-of-band
rebuild (e.g. upstream published a new `:latest` without a ref bump).

### 6. Smoke test

After the rhdh-agentic scaffold PR is merged, create a test issue:

```bash
gh issue create --repo redhat-developer/rhdh-agentic \
  --title "test: smoke test after fullsend <version> upgrade" \
  --body "Smoke test — verify triage runs correctly after scaffold upgrade.
Expected: triage agent picks up this issue, classifies it, posts status comment.
Close this issue if triage succeeds."
```

Watch the run. If triage succeeds, close the issue.

### 6a. Re-apply shim customizations

`repos install` convergence currently only bumps `uses:` SHA pins in
`.github/workflows/fullsend.yaml` — it does NOT regenerate the full shim
from the template. This means shim customizations (event type edits,
`if:` condition changes) survive `repos install`. However, template
improvements (like the v0.43.0 `/fs-` comment filter) must be applied
manually. A future fullsend version may change convergence behavior to
do full template rewrites — do not rely on this.

After the scaffold PR is created, check each repo for shim customizations
that need re-applying. Current fleet customizations:

| Repo | Customization | What to edit |
|------|---------------|--------------|
| All 9 managed repos | All auto-triggers disabled | Remove `issues` event, remove `closed` from `pull_request_target.types`, remove `pull_request_review` event. Keep only `issue_comment` and `pull_request_target: [labeled, unlabeled]` |
| redhat-developer/rhdh-plugins | Above + workspace path filter | Additionally keep `paths:` (boost, scorecard, ai-integrations) on `pull_request_target` |

To re-apply after a scaffold PR lands:

```bash
# In the scaffold PR branch, edit the shim:
# pull_request_target.types: [closed, labeled, unlabeled]
# (remove: opened, synchronize, ready_for_review)
```

Update the header comment to flag the customization:
```yaml
# Based on fullsend scaffold; customized to disable review auto-trigger.
```

**Why no config-based approach:** Built-in agents (triage, code, review, fix,
retro, prioritize) use hardcoded stage routing in the dispatch script. CEL
triggers only work for custom agents. The `roles:` list controls whether an
agent can run at all — there is no per-role auto-trigger toggle. The only
existing per-PR opt-out is `fullsend-no-fix` (label-based, hardcoded).

## Known gotchas

1. **Public mint.** Manifest `mint_url` must stay `https://mint.fullsend.sh`.
   `github setup` without `--mint-url` defaults to this, which is correct.
2. **Config-targeting flags rewrite `config.yaml`.** `--runtime`, `--agents`,
   `--mint-url`, `--inference-*` re-serialize the overlay (comments lost,
   agents kept). Prefer `repos install` over `github setup` for upgrades.
3. **Empty `customized/` dirs are leftover.** ADR 0064 removed the overlay;
   custom agents live under `.fullsend/rhdh/` with `base:` composition.
4. **Workflow files need `workflows` token scope.** The fs-code agent cannot
   push `.github/workflows/` — that is why upgrades go through `repos install` PRs.
5. **Do not `--direct`.** All scaffold and manifest changes land as PRs.
6. **Shim customizations need monitoring.** See step 6a — current convergence
   only bumps SHA pins (customizations survive), but this may change. Keep a
   checklist of per-repo edits and verify after each upgrade. Also manually
   apply upstream template improvements (e.g. new `if:` guards).
