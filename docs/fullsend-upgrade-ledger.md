# Fullsend Upgrade Ledger

Tracks upgrades of the fullsend CLI, scaffold files, and sandbox images
across our repos. Each upgrade is a dated section with what changed, what
we did, and what broke.

---

## 2026-06-16 — v0.15.0 → v0.17.0

### Scope

| Component | From | To |
|-----------|------|----|
| CLI binary | v0.15.0 | v0.17.0 |
| Scaffold (harness, agents, scripts) | v0.15.0 | v0.17.0 |
| Sandbox image | rhdh-fullsend-code:latest | rebuild |

### Repos affected

| Repo | Customization | Agents | PR |
|------|---------------|--------|----|
| rhdh-agentic | Heavy — agents, harness, env, policies, scripts, skills | code, debug, review | [#75](https://github.com/redhat-developer/rhdh-agentic/pull/75) ✅ merged, [#77](https://github.com/redhat-developer/rhdh-agentic/pull/77) open |
| rhdh-plugins | Medium — code+fix agents, harness, policies, skills | code, fix | [#3421](https://github.com/redhat-developer/rhdh-plugins/pull/3421) ✅ merged, [#3424](https://github.com/redhat-developer/rhdh-plugins/pull/3424) open |
| rhdh-plugin-export-overlays | Minimal — mostly .gitkeep defaults | (defaults) | n/a |

### Upstream changes v0.15→v0.17 (notable)

**v0.16.0 (2026-06-09):**

- **Harness paths**: `/tmp/workspace/` → `/sandbox/workspace/` (already adopted in our files)
- **New harness field**: `doc:` for agent documentation reference
- **New harness field**: `plugins:` section (gopls-lsp for code agent)
- **Workflow shim**: added YAML front-matter and `fullsend managed` comment
- **Security review agent**: extracted challenger sub-agent, added GHA injection checks
- **Review agent**: variable verification, security heuristics
- **Code agent sandbox**: Go 1.26, gopls 0.22.0, openshell 0.0.54
- **Scripts**: merge-base-aware diff in post-code/post-fix, protected-path fixes
- **Scripts**: stale-head re-dispatch in post-review.sh (exit code 10 handling)
- **Scripts**: force-override logging in pre-code.sh, COMMENT_BODY→SKIP_COMMENT rename
- **Mint**: PEM secrets role-only naming, public hosted mint URL default

**v0.17.0 (2026-06-11):**

- **Harness struct**: new optional `role` and `slug` fields, `ForgeConfig` (ADR-0045)
- **Skills**: modeled as directories instead of single files
- **CLI**: `fullsend lock` command for dependency pinning
- **CLI**: binary vendoring refactored, OIDC HTTP timeout fixed
- **Scaffold actions removed**: mint-token, setup-gcp, validate-enrollment composites deleted (moved to CLI)
- **Security**: tirith bumped 0.2.12→0.3.1, fail-open paths closed
- **Skills**: code-review and docs-review got rename/deprecation bare-word grep guidance

### Step 1: Upgrade CLI binary ✅

```bash
# 1. Download release asset (adjust version as needed)
VERSION=0.17.0
gh release download "v${VERSION}" --repo fullsend-ai/fullsend \
  --pattern "fullsend_${VERSION}_darwin_arm64.tar.gz" -D /tmp

# 2. Back up old binary
OLD_VERSION=$(fullsend --version | awk '{print $3}')
cp ~/.local/bin/fullsend ~/.local/bin/fullsend.${OLD_VERSION}.bak

# 3. Extract and install
tar xzf "/tmp/fullsend_${VERSION}_darwin_arm64.tar.gz" -C ~/.local/bin/ fullsend
chmod +x ~/.local/bin/fullsend

# 4. Verify
fullsend --version  # → fullsend version 0.17.0
```

- [x] Download v0.17.0 binary
- [x] Back up old: `fullsend.0.15.0.bak`
- [x] Replace ~/.local/bin/fullsend
- [x] Verify: `fullsend --version` → `0.17.0`

### Step 2: Upgrade rhdh-agentic ✅

Single PR: https://github.com/redhat-developer/rhdh-agentic/pull/75 (merged)

| File | Change |
|------|--------|
| harness/code.yaml | added `doc:`, `plugins:` fields + version stamp |
| harness/debug.yaml | version stamp (custom agent, no upstream) |
| harness/review.yaml | version stamp (intentional diffs only) |
| agents/code.md | version stamp (heavily customized Phase 1/2) |
| agents/debug.md | version stamp (custom, no upstream) |
| agents/review.md | fixed `/tmp/workspace/` → `/sandbox/workspace/` (4 occurrences) + stamp |
| policies/code.yaml | version stamp (upstream unchanged; our additions intentional) |

Dispatch workflow: https://github.com/redhat-developer/rhdh-agentic/pull/77 (open — `fullsend_ai_ref: v0`)

### Step 3: Upgrade rhdh-plugins ✅

Version stamps on code agent/harness: https://github.com/redhat-developer/rhdh-plugins/pull/3421 (merged by fs-code agent)

Remaining changes in single PR: https://github.com/redhat-developer/rhdh-plugins/pull/3424 (open)

| File | Change |
|------|--------|
| `.github/workflows/fullsend.yaml` | `fullsend_ai_ref: v0` input |
| harness/fix.yaml | version stamp |
| policies/code.yaml | version stamp |
| policies/fix.yaml | version stamp |

Path fixes (`/tmp/workspace/` → `/sandbox/workspace/`) were already on upstream main.

### Step 4: Rebuild sandbox image

- [ ] Update Containerfile if needed (Go version, gopls, openshell)
- [ ] Build and push rhdh-fullsend-code:latest
- [ ] Verify corepack/yarn still work

### Step 5: Test

- [ ] Local sandbox run with code agent
- [ ] Local sandbox run with review agent
- [ ] CI dispatch test

### Step 6: Document in /fullsend skill

- [ ] Add `upgrade` subcommand to /fullsend skill
- [ ] Include version-stamp pattern for customized files

---

## Version stamp convention

Every customized file should carry a comment header recording which
upstream scaffold version it was forked from:

```yaml
# forked-from: fullsend v0.17.0 scaffold
# last-synced: 2026-06-16
```

This enables future upgrades to generate a targeted diff:
```bash
git diff <old-version>..<new-version> -- internal/scaffold/fullsend-repo/<path>
```

## Upgrade protocol (for `/fullsend upgrade`)

### Principles

1. **One PR per repo per upgrade.** Collect all scaffold, workflow, and
   version-stamp changes into a single PR. Avoids review fatigue and
   ensures the upgrade is atomic.
2. **Workflow files need human push.** GitHub blocks App tokens from
   modifying `.github/workflows/` without `workflows` permission.
   The fs-code agent cannot push these — include them in the manual PR.
3. **Sync fork before branching.** Always fast-forward your fork's main
   to upstream before creating the upgrade branch.

### Pre-flight

```bash
# 1. Sync fork with upstream (BEFORE branching!)
git fetch upstream
git checkout main
git merge upstream/main --ff-only
git push origin main

# 2. Fetch fullsend repo tags
cd <fullsend-repo>
git fetch --tags

# 3. Check versions
fullsend --version                              # current CLI
git tag --sort=-v:refname | head -3             # latest upstream
```

### Per-repo upgrade

```bash
# 4. Diff ALL customized files against upstream scaffold
UPSTREAM="<fullsend-repo>/internal/scaffold/fullsend-repo"
OURS="<target-repo>/.fullsend/customized"
for f in $(find "$OURS" -type f ! -name ".gitkeep"); do
  rel="${f#$OURS/}"
  echo "--- $rel ---"
  diff -u "$UPSTREAM/$rel" "$f" 2>/dev/null || echo "(custom)"
done

# 5. Diff scaffold changes between versions
OLD=v0.17.0  # from forked-from stamp in customized files
NEW=v0.18.0  # target version
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/harness/
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/agents/
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/scripts/
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/policies/

# 6. Also diff the workflow shim template
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/templates/shim-per-repo.yaml

# 7. Apply changes, update ALL version stamps, commit as single PR
```

## Gotchas learned

1. **Local checkout can be stale**: always `git fetch --tags` the fullsend
   repo before diffing — the submodule pin may lag behind releases.
2. **Silent path breakage**: the `/tmp/workspace/` → `/sandbox/workspace/`
   migration silently fails — files mount fine, agent can't find them.
3. **Agent prompts reference harness paths**: when `host_files[].dest` paths
   change, agent `.md` files that hardcode those paths must be updated too.
4. **Concurrency group bumps pending runs**: `cancel-in-progress: false` only
   protects *running* jobs. Pending runs get replaced by newer ones in the same
   group. If triage triggers a bot comment while `/fs-code` is queued, the code
   run gets cancelled. Re-trigger after the storm passes.
5. **Agent skips branch creation on trivial changes**: the code agent may
   shortcut the `code-implementation` skill for simple edits and commit directly
   on main. Post-script then exits with "nothing to do." Workaround: add explicit
   branch-creation instructions in the `/fs-code` comment.
6. **Fork sync before branching**: always sync fork main with upstream before
   creating a PR branch. A stale fork causes GitHub to show unrelated commits
   in the PR diff, and rebasing later can silently drop path fixes that were
   already applied upstream.
7. **Workflow files need `workflows` token scope**: GitHub blocks App tokens
   from pushing `.github/workflows/` changes. The fs-code agent cannot push
   these — always include workflow changes in the manual upgrade PR.
