# upgrade

Move the fleet to a new fullsend release: CLI, fleet manifest, sandbox image,
then each managed repo, one at a time, through PRs. Never `--direct`.

## Usage

```
/fullsend upgrade [target-version]
```

- `target-version`: e.g. `v0.60.0`. Default: latest release on fullsend-ai/fullsend.

Official path: [Rolling out a new fullsend version](https://fullsend.sh/docs/guides/getting-started/repo-management#rolling-out-a-new-fullsend-version).

## How to think about an upgrade

An upgrade is not "bump the ref and run install". Each fullsend release can
change the manifest schema, the managed `.fullsend/config.yaml`, the shim
workflow and the base harnesses, and `repos install` rewrites the shim
wholesale. The safe shape, learned on v0.45 → v0.57.1:

1. **Read every release note between the current and target versions** and
   turn them into a list of breaking changes for *this* fleet.
2. **Prepare the shared pieces without touching any repo**: CLI, `repos.yaml`
   draft, sandbox image under a version tag. `:latest` stays put.
3. **Rehearse on the `rhdh-parasol/*` mirror** of a repo: pre-PR, install,
   finish the scaffold PR, test with real `/fs-*` runs.
4. **Repeat for the production repo**, then the next repo. Installs run
   one at a time.
5. **Move `:latest` last**, when every repo is on the new version.

Plan for days, not hours: each repo needs a pre-PR merged, an install, a
scaffold PR finished and tested, and a human to merge each one.

## Who runs what

`repos install` writes repo variables and secrets and opens PRs. A human
operator runs it, or explicitly approves each run. The agent prepares the
manifest, files and exact commands, and may run `--dry-run`, `fullsend lint`
and read-only `gh` queries freely. Parasol repos are the place to test; ask
before acting on a production repo.

## Prerequisites

| Gate | Check | If fail |
|------|-------|---------|
| Writable checkout of this repo | `git -C <rhdh-fullsend> status` | Clone it. Install can write back to `repos.yaml` (5d), so a copy loses those edits |
| `gh` CLI | `gh auth status` | Ask the user to authenticate |
| git authenticates to GitHub without prompting | `GIT_TERMINAL_PROMPT=0 git push --dry-run origin HEAD` in the writable checkout (the repo is public, so a fetch proves nothing; a dry-run push needs a working login and changes nothing) | `gh auth setup-git`, then re-check. `fullsend lint` and install shell out to `git fetch`/`git push` and hang or fail on a credential prompt |
| `fullsend` CLI ≥ target | `fullsend --version` | Step 2 |
| Upstream source (optional, for reading code) | a `fullsend-ai/fullsend` checkout with tags | `gh repo clone fullsend-ai/fullsend` |

## Procedure

### 1. Inventory and release notes

Find where every repo is today. Repos drift: during v0.57 prep, some fleet
repos were on v0.43 while others were on v0.45.

```bash
grep -E 'fullsend_ref|^\s*- name: ' repos.yaml
for r in $(grep -E '^\s*- name: [a-z-]+/[a-z-]+' repos.yaml | awk '{print $3}'); do
  v=$(gh api repos/$r/contents/.github/workflows/fullsend.yaml --jq .content | base64 -d)
  echo "$r $(echo "$v" | grep -oE '# *v[0-9.]+' | head -1) $(gh api repos/$r --jq .visibility)"
done
```

Also check, per repo:
- **Release branches with their own shim.** A PR runs the shim from its base
  branch, so `release-x.y` needs the same upgrade if it has
  `.github/workflows/fullsend.yaml`:
  `gh api "repos/<r>/contents/.github/workflows/fullsend.yaml?ref=release-x.y"`.
- **A pilot mirror for every production repo.** Each production entry needs an
  `rhdh-parasol/<repo>` entry in `repos.yaml` to rehearse on (step 5). List
  the gaps:
  ```bash
  for r in $(grep -E '^\s*- name: redhat-developer/' repos.yaml | awk '{print $3}'); do
    m=rhdh-parasol/${r#*/}
    grep -q "name: $m\b" repos.yaml && continue
    gh repo view $m --json name >/dev/null 2>&1 && echo "$m exists, not in repos.yaml" || echo "$m missing"
  done
  ```
  Close the gaps before step 5. See "Repos without a pilot mirror" below.
- **fullsend installs outside `repos.yaml`.** For example,
  `redhat-developer/rhdh` runs fullsend without a manifest entry. Agree with
  its owner before onboarding it.
- **Non-fullsend workflows** that use the same GitHub feature the release
  reacts to. They are out of scope for this skill, but list them.

Read the notes for every release in the range, not just the target:

```bash
gh release list --repo fullsend-ai/fullsend --limit 30
gh release view vX.Y.Z --repo fullsend-ai/fullsend
```

Sort what you find into: manifest schema changes, managed-config keys added
or removed, shim/trigger changes, base harness changes, model defaults, new
repo variables or secrets. Each one becomes a step below.

### 2. CLI

Install the target release's binary the way you normally install CLIs, and
keep the old one until the rollout is done (it is the rollback). For
example, replacing the binary already on your `PATH`:

```bash
VERSION=<target>   # without the leading v
BIN=$(command -v fullsend); OLD=$(fullsend --version | awk '{print $3}')
cp "$BIN" "$BIN.$OLD.bak"
TMP=$(mktemp -d)
gh release download "v${VERSION}" --repo fullsend-ai/fullsend -D "$TMP" \
  --pattern "fullsend_${VERSION}_$(uname -s | tr A-Z a-z)_$(uname -m | sed s/x86_64/amd64/).tar.gz"
tar xzf "$TMP"/fullsend_*.tar.gz -C "$(dirname "$BIN")" fullsend && fullsend --version
```

Asset names can change between releases; check them with
`gh release view v${VERSION} --repo fullsend-ai/fullsend` if the download
finds nothing.

Every operator needs a CLI at least as new as `fullsend_ref` before running
any `fullsend repos` command. Older CLIs refuse newer manifests (for example,
v0.57 moved the managed config schema to v3, and CLIs up to v0.55 reject
`trace_context`). The release notes say when this applies.

`fullsend lint` and install run `git fetch` and `git push` against GitHub, so
the git prerequisite above must pass first.

### 3. Manifest PR (in this repo)

Open a branch in this repo. It merges to `main` **last** (step 7), because a
push to `main` that touches `repos.yaml` or `images/code/**` rebuilds
`:latest` for every repo.

- Set `github.fullsend_ref` to the target tag.
- Apply manifest schema changes from step 1. Examples: v0.46 requires
  `defaults.inference.auth` (we use `vertex-wif`), and newer CLIs reject
  top-level `defaults.runtime` and `defaults.allowed_remote_resources`, which
  move under `defaults.config`.
- Keep `mint_url` as it is unless the release notes change it.
- Check that the new CLI parses it: `fullsend repos install -f repos.yaml --dry-run <one-repo>`.
  A schema error appears before any repo work.

### 4. Sandbox image

`images/code/Containerfile` pins `BASE_IMAGE` to the released upstream image
for `fullsend_ref`, by tag and multi-arch index digest. Upstream `:latest`
tracks fullsend `main` and is not a release.

```bash
skopeo inspect --override-os linux --override-arch amd64 \
  --format '{{.Digest}}' docker://ghcr.io/fullsend-ai/fullsend-code:<X.Y.Z>   # per-arch
skopeo inspect --raw docker://ghcr.io/fullsend-ai/fullsend-code:<X.Y.Z> | shasum -a 256   # index digest
```

On macOS, plain `skopeo inspect` fails with "no image found … darwin"; the
override flags or `--raw` avoid that. Also check whether the upstream
Containerfile changed between versions (`git diff vOLD..vNEW --
images/code/Containerfile` in the fullsend checkout), and whether the Claude
Code version the image pins (`CLAUDE_CODE_VERSION`) moved.

Build without touching `:latest`: push a semver tag (e.g. `v0.57.1`) on the
branch commit. Which tags a tag build publishes is set by the metadata step
in `.github/workflows/sandbox-images.yml`; read it before tagging. Check that
the step sets `flavor: latest=false`: `docker/metadata-action`'s default
`latest=auto` tags semver pushes as `latest` (that moved `:latest` on the
first v0.57.1 tag). After the tag build, confirm `:latest` did not move:

```bash
skopeo inspect --raw docker://ghcr.io/redhat-developer/rhdh-fullsend-code:latest | shasum -a 256
```

If it moved, restore it with `skopeo copy` from the previous `:<sha>` tag.
That needs `gh auth refresh -h github.com -s write:packages`.

Pilot repos point their harness `image:` lines at `:<X.Y.Z>` until step 7.

### 5. Each repo: pilot mirror first, then production

Do the `rhdh-parasol/*` mirror of a repo first, then the production repo.
Run installs one at a time, from one writable checkout, and always with a
repo filter. An install can write back to `repos.yaml` (5d), and a later
install from a checkout without that edit stops.

#### Repos without a pilot mirror

A repo with no `rhdh-parasol` entry has nowhere to rehearse. Fix that first
instead of upgrading production blind:

- **The mirror repo exists but is not in `repos.yaml`:** onboard it with
  `/fullsend onboard rhdh-parasol/<repo>`. Check in
  `docs/gcp-infrastructure.md` whether the org's WIF binding already covers
  it. Its `.fullsend/` should match production's,
  including repo-owned harnesses under `.fullsend/rhdh/`. Sync it from
  production in a mirror PR, and re-point repo references to the mirror.
- **No mirror repo:** create it in the `rhdh-parasol` org (a human with org
  rights does this), sync `.fullsend/` and the shim from production, then
  onboard it as above. Do this before the upgrade window, because onboarding
  needs the operator's `gcloud`/`gh` access and a merged PR.
- **No mirror possible in time:** say so explicitly, and get the repo owner's
  agreement to upgrade production directly. Compensate: diff the repo's
  `.fullsend/` against a mirrored repo of the same shape (stock config vs
  repo-owned harnesses), keep the dry run clean, finish the scaffold PR with
  extra care, and run the 5f tests on production right after merge. Repos
  with repo-owned harnesses (`.fullsend/<org>/harness/`) are the risky ones.
  Do not take this path for those without the owner's explicit OK.

#### 5a. Pre-PR in the target repo (merged before install)

Install's preflight reads the repo's **live** `.fullsend/config.yaml` from the
default branch and refuses keys the target version dropped. But the repo's
current shim still runs the old version until the scaffold PR merges, so the
pre-PR must also stay valid for the old version.

- Remove keys the target dropped, if the old version tolerates their absence.
  v0.57 example: `create_issues`.
- Do not add keys the old version cannot parse. v0.57 example: `tracker:` as a
  mapping breaks v0.45, which parses it as a string, so it goes in with the
  scaffold PR instead.
- Without `fullsend lint` (older than v0.46), check the file with the old
  version's `config.ParsePerRepoConfig` in a tiny Go program in a checkout of
  that tag.

#### 5b. Managed config adoption (ADR-0122, v0.47+)

Install manages `.fullsend/config.yaml`. A hand-written file stops install
with "exists without the managed-configuration ownership marker". To adopt it:

1. Run a dry run (5c). It prints the proposed `repos.yaml` `config:` block and
   a diff of what would be lost.
2. Move every setting you want to keep into that repo's entry in `repos.yaml`
   under `config:`. Check the `inference:` block in particular. A repo-specific
   `inference.project` or `inference.wif_provider` left behind is silently
   dropped by the next install, and every agent in that repo then fails Vertex
   auth. The dry run's loss diff lists what would go; read it line by line.
3. In the pre-PR, put the marker at the top of the file. Copy it exactly
   from the target version, because it carries a schema version: it is the
   `managedConfigMarker` constant (`git grep -n managedConfigMarker vX.Y.Z --
   internal/` in a fullsend checkout). In v0.57.1 it is two comment lines
   starting `# This file is managed by 'fullsend repos': repos-config-v1`.

Do not just delete the file. The old version still needs it for custom agents
until the scaffold PR merges.

From now on the repo's `config.yaml` is rendered from `repos.yaml`. Any change
to it goes through `repos.yaml` plus an install.

#### 5c. Dry run

From the writable checkout, always with a repo filter:

```bash
fullsend repos install -f repos.yaml --dry-run <org>/<repo>
```

Read the whole output: proposed config entry, file diff, effective-config
diff, and the list of what it would write. Fix and repeat until it is clean.

#### 5d. Install (human runs or approves)

```bash
fullsend repos install -f repos.yaml <org>/<repo>
git diff repos.yaml   # commit anything install wrote back to the manifest branch
```

Write-backs depend on the version and on the repo's state. In v0.57.1, a
first install or a `--rotate-trace-signing-key` run records
`config.trace_context`. Upgrading an already-installed repo wrote nothing on
parasol. Whatever `git diff` shows, commit it before the next install.

Then set `FULLSEND_REVIEW_CLIENT_ID` if it is missing. The review workflow
uses it to recognise its own earlier review comment. Without it, runs log
"Prior review comment … wrong app — discarding", every re-review starts from
scratch, and an unchanged-diff push is reviewed again. Install writes it only
when it first sets up a repo's variables. Up to at least v0.57.1 it does not
add it to an already-installed repo, so expect to set it once per repo:

```bash
gh variable list --repo <org>/<repo> | grep FULLSEND_REVIEW_CLIENT_ID
id=$(gh api /apps/<app_set>-review --jq .client_id)   # app_set: repos.yaml github.app_set, default fullsend-ai
gh variable set FULLSEND_REVIEW_CLIENT_ID --repo <org>/<repo> --body "$id"
```

The value is the review GitHub App's public client ID, not a secret. Once
present, later installs keep it correct.

#### 5e. Finish the scaffold PR immediately

Install opens a PR on branch `fullsend/scaffold-install`, or a bump branch.
From v0.57 the shim triggers on `pull_request`, which runs the PR's own copy
of the shim, with every stock auto-trigger. Push the customizations below
before anything labels the PR. An unfinished scaffold PR has started a review
on itself.

1. **Re-apply the shim customizations** (table below). Install rewrites the
   shim from the template every time.
2. **Bump repo-owned harness `base:` pins** to the `fullsend-ai/agents`
   commit that matches the release, with the `#sha256=` of each file.
   Install does not touch them. The agents repo tags its releases with the
   same version: `gh api repos/fullsend-ai/agents/git/ref/tags/vX.Y.Z --jq
   .object.sha` (if the tag is missing, check the release notes for the
   agents commit). Keep fix/review as repo harness files with
   pinned bases, not inline `harness:` blocks in `repos.yaml`. Inline blocks
   fall back to the unpinned agents tag at run time, and move policy out of
   the repo's CODEOWNERS.
   ```bash
   curl -fsSL https://raw.githubusercontent.com/fullsend-ai/agents/<sha>/harness/<agent>.yaml | shasum -a 256
   ```
3. **Point harness `image:` lines at `:<X.Y.Z>`**, and update version
   comments in the harness files.
4. **Models** come from `repos.yaml` `models.aliases`. See `/fullsend models`.
   Search for literal model ids in agent and skill text: `git grep -n "claude-"`.
5. **Lint** with the new CLI, then delete the cache it leaves in the repo
   before `git add` (it is not gitignored):
   ```bash
   fullsend lint && rm -rf .fullsend/.fullsend-cache
   ```
6. **Remove leftovers**: empty `.fullsend/customized/` trees (ADR 0064), and
   symlinks whose target is missing. v0.57 drops dangling symlinks when it
   copies the repo into the sandbox, and the code post-script then fails with
   "Agent left uncommitted changes — not a no-op":
   ```bash
   find . -type l ! -exec test -e {} \; -print
   ```

Install generates more than we use, such as Jira, OpenAI and gateway secrets
in the shim. Unset secrets pass as empty strings. Leave them, so the next
install's diff stays small. Up to v0.57.1 there was no install option to
omit them; check `fullsend repos install --help` on newer versions.

#### 5f. Test (mirror before merge, production right after)

`/fs-*` comments run the shim from the default branch, which stays on the old
version until the scaffold PR merges. So the real test of the new version
happens on the **mirror**: merge its scaffold PR, then run the checks below
before touching production. On **production**, merge only after the mirror
passed, and run the same checks right after merge.

Run the agents the repo uses, in parallel:

| Run | Exercises |
|-----|-----------|
| `/fs-review` on a same-repo PR | new trigger path, review personas, image |
| `/fs-diagnose` on a PR with a failed check | ci-diagnose, Vertex host files |
| `/fs-code` on a small fresh issue | image, toolchain, sandbox git checks, post-script |
| e2e-triage label on an issue (overlay) | Playwright in the sandbox, Vertex credentials |
| `/fs-review` on a fork PR | the fork path (v0.57: fork PRs need `/fs-*`, labels are skipped) |

Pick a fresh issue for `/fs-code`. On an issue that already has an agent PR,
the agent correctly does nothing, which tests nothing.

Check each run's log and artifacts. The log lines below are the v0.57.1
wording; if a grep finds nothing on a newer version, read the log around the
agent start instead of assuming the setting was ignored:

```bash
gh run view <id> --repo <r> --log | grep -E 'remapped|Agent: claude|subagents:|##\[error\]|Runtime:'
gh run download <id> --repo <r> -D /tmp/run
find /tmp/run -path '*transcripts*' -name '*.jsonl' \
  -exec jq -r 'select(.type=="assistant")|.message.model' {} + | sort | uniq -c
```

Once the mirror passes, repeat 5a–5f for the production repo.

### 6. Release branches

For every `release-x.y` that has its own `fullsend.yaml` (step 1), bring the
shim to the new version with the same customizations. Otherwise PRs against
that branch keep running the old shim.

### 7. Finish the fleet

When every repo is on the new version:
- Merge the manifest PR to `main`. This rebuilds and moves `:latest` and
  `:dev`.
- Move harness `image:` lines back to `:latest`, or keep the version tag.
  Decide once, for the whole fleet.
- `fullsend repos status -f repos.yaml` per repo. The shim always differs,
  because of the customizations.

## Shim customizations (re-apply after every install)

The shim's `on:` block decides which GitHub events reach fullsend at all, and
install resets it to the template every time. What config can control on
top of that changes between releases. For example, v0.57.1 added a per-agent
`trigger:` (CEL) that can gate some built-in agents, but not code or fix,
whose routing lives in `reusable-dispatch.yml`. Before dropping a shim edit
in favour of config, check the target version's docs and dispatch workflow.

| Repo | Keep |
|------|------|
| All managed repos (baseline) | `issue_comment: [created]` and the PR event with `[labeled, unlabeled]`: `pull_request_target` up to v0.56, `pull_request` from v0.57. Remove the `issues` and `pull_request_review` blocks and the other PR event types |
| `*/rhdh-plugin-export-overlays` | Baseline plus `issues: [labeled]`. E2E triage and the coder run on issue labels (#3823); the dispatch `if:` also gates `ready-to-code` on `e2e-failure` |
| `redhat-developer/rhdh-plugins` | Baseline plus the workspace `paths:` filter on the PR event. Copy the list from the current shim before installing |

Also keep:
- the `/fs-*` non-bot filter in the dispatch `if:`;
- the header comment, which tells the next person to re-apply:
  ```yaml
  # Based on fullsend scaffold; customized to disable all agent auto-triggers.
  # Only label-based triggers and /fs-* slash commands remain active.
  # `fullsend repos install` regenerates this file and restores the
  # auto-trigger events — re-apply after every upgrade.
  # Upstream: https://github.com/fullsend-ai/fullsend/blob/main/internal/scaffold/fullsend-repo/templates/shim-per-repo.yaml
  ```

In v0.57.1 the installer writes an `# Upstream:` link that 404s. Check that
the template path above still exists at the target tag (`git ls-tree vX.Y.Z
internal/scaffold/fullsend-repo/templates/` in a fullsend checkout) and fix
the link if it moved. Diff against the template, not the old shim, to see
what the new version changed.

## Known gotchas

| Symptom | Cause | Fix |
|---------|-------|-----|
| `defaults.runtime is no longer supported` | manifest schema moved | nest under `defaults.config` |
| Dry run: `<key> is no longer supported` | preflight reads the live default-branch config | merge the 5a pre-PR first |
| `cannot unmarshal !!map into string` on old-version runs | new mapping key (e.g. `tracker:`) in the live config | add it only with the scaffold PR |
| `exists without the managed-configuration ownership marker` | ADR-0122 adoption | 5b |
| `:latest` moved on a tag build | metadata-action `latest=auto` | `flavor: latest=false`; restore with `skopeo copy` |
| A review starts on the scaffold PR | `pull_request` runs the PR's own shim | push the 5e customizations immediately |
| Code post-script: "uncommitted changes — not a no-op" | dangling symlinks dropped in the sandbox copy, or real leftover edits | `find . -type l ! -exec test -e {} \; -print` |
| "Prior review comment … wrong app — discarding" | `FULLSEND_REVIEW_CLIENT_ID` repo var missing; install does not add it to existing repos | set it once per repo (5d) |
| Lint: "installing named symlink: rename … .fullsend-cache" | stale cache copied from elsewhere | `rm -rf .fullsend/.fullsend-cache`, re-run |
| `fullsend lint` or install hangs on `git fetch`, or `git push` says "could not read Username" | git is waiting for a credential prompt | `gh auth setup-git` (Prerequisites) |
| `skopeo inspect` "no image found … darwin" | multi-arch image inspected on macOS | `--override-os linux --override-arch amd64` or `--raw` |
| Later install stops on missing `trace_context` | an earlier install wrote it back from another copy | install from the one writable checkout and commit write-backs |

Also: **`--direct` is never used.** Every scaffold and manifest change lands
as a PR.
