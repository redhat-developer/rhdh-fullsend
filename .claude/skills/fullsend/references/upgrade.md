# upgrade

Upgrade customized scaffold files, dispatch workflows, and the CLI binary
to a new fullsend release. Produces one PR per repo with all changes.

Full upgrade history is in `docs/fullsend-upgrade-ledger.md`.

## Usage

```
/fullsend upgrade [target-version]
```

- `target-version`: e.g. `v0.18.0`. Default: latest release on fullsend-ai/fullsend.

## Prerequisites

| Gate | Check | If fail |
|------|-------|---------|
| Scaffold dir | `$FULLSEND_SCAFFOLD_DIR` or `../asdlc-lab/resources/fullsend-ai/fullsend/` | Ask user to clone `asdlc-lab` |
| `gh` CLI | `gh auth status` | Ask user to authenticate |
| `fullsend` CLI | `fullsend --version` | Suggest downloading from GitHub releases |

## Procedure

### 1. Determine versions

```bash
# Current CLI version
fullsend --version

# Fetch latest tags from upstream
cd <fullsend-repo> && git fetch --tags

# Latest upstream release
gh release list --repo fullsend-ai/fullsend --limit 3

# Current version from our customized files (read forked-from stamp)
head -5 <target-repo>/.fullsend/customized/harness/code.yaml
```

Show the user: current CLI version, current forked-from version (from stamps),
and target version. Confirm before proceeding.

### 2. Upgrade CLI binary

```bash
VERSION=<target>
gh release download "v${VERSION}" --repo fullsend-ai/fullsend \
  --pattern "fullsend_${VERSION}_darwin_arm64.tar.gz" -D /tmp

OLD_VERSION=$(fullsend --version | awk '{print $3}')
cp ~/.local/bin/fullsend ~/.local/bin/fullsend.${OLD_VERSION}.bak

tar xzf "/tmp/fullsend_${VERSION}_darwin_arm64.tar.gz" -C ~/.local/bin/ fullsend
chmod +x ~/.local/bin/fullsend
fullsend --version
```

### 3. Generate upstream changelog

Diff the scaffold between the old and new versions to understand what changed:

```bash
OLD=v0.17.0  # from forked-from stamps
NEW=v0.18.0  # target

cd <fullsend-repo>
git log --oneline $OLD..$NEW --no-merges | head -30

# Scaffold-specific changes
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/harness/
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/agents/
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/scripts/
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/policies/
git diff $OLD..$NEW -- internal/scaffold/fullsend-repo/templates/shim-per-repo.yaml
```

Present a summary of changes to the user. Classify each as:
- **Must adopt**: path changes, new required fields, security fixes
- **Should adopt**: new optional fields, improved defaults
- **Informational**: script changes (inherited automatically if not customized)

### 4. Per-repo upgrade

For each repo with `.fullsend/customized/`:

#### 4a. Sync fork

```bash
git fetch upstream
git checkout main
git merge upstream/main --ff-only
git push origin main
```

If ff-merge fails, the fork has diverged. Investigate before proceeding.

#### 4b. Diff all customized files

```bash
UPSTREAM="<fullsend-repo>/internal/scaffold/fullsend-repo"
OURS="<target-repo>/.fullsend/customized"

for f in $(find "$OURS" -type f ! -name ".gitkeep" | sort); do
  rel="${f#$OURS/}"
  upstream_file="$UPSTREAM/$rel"
  echo "--- $rel ---"
  if [ -f "$upstream_file" ]; then
    diff -u "$upstream_file" "$f" | head -40
  else
    echo "(custom — no upstream equivalent)"
  fi
done
```

For each file, record a decision:
- **ADOPT**: apply upstream change to our customized file
- **SKIP**: upstream changed but our customization is intentional — no action
- **STAMP**: no changes needed — just update the version stamp

Present the decision table to the user before making changes.

#### 4c. Apply changes

Create a single branch per repo. Include ALL changes in one PR:
- Scaffold file updates (harness, agents, policies)
- Dispatch workflow sync (`.github/workflows/fullsend.yaml`)
- Version stamp updates on every customized file

**Important constraints:**
- Workflow files (`.github/workflows/`) need human push — the fs-code agent
  token lacks `workflows` permission. Always include these in the manual PR.
- Agent prompt `.md` files may reference harness paths (e.g.,
  `/sandbox/workspace/prior-review.txt`). When harness `host_files[].dest`
  paths change, grep agent prompts for the old paths.

#### 4d. Update version stamps

Every customized file gets updated stamps:
```yaml
# forked-from: fullsend v0.18.0 scaffold
# last-synced: 2026-07-15
```

For custom files with no upstream equivalent:
```yaml
# forked-from: custom (no upstream equivalent)
# last-synced: 2026-07-15
```

### 5. Rebuild sandbox image

Check if the upstream base image versions changed:
```bash
git diff $OLD..$NEW -- images/code/Containerfile
git diff $OLD..$NEW -- images/sandbox/Containerfile
```

Our Containerfile extends `ghcr.io/fullsend-ai/fullsend-code:latest`.
Tool upgrades (Go, gopls, tirith) come from the base image automatically.

Only change our Containerfile if:
- The pinned yarn version changed in the target repo's `package.json`
- We need to add/remove tools (e.g., openspec)

To rebuild:
```bash
podman build -t rhdh-fullsend-code:local \
  -f images/code/Containerfile images/code/
```

CI auto-builds on push to main when `images/code/**` changes. If no
Containerfile changes are needed, trigger manually via `workflow_dispatch`
on the sandbox-images workflow to pick up the new base.

### 6. Smoke test

After PRs are merged, create a test issue on rhdh-agentic to verify
the agent pipeline works with the upgraded scaffold and image.

```bash
gh issue create --repo redhat-developer/rhdh-agentic \
  --title "test: smoke test after fullsend <version> upgrade" \
  --body "Smoke test — verify triage runs correctly after scaffold upgrade.
Expected: triage agent picks up this issue, classifies it, posts status comment.
Close this issue if triage succeeds."
```

The `issues: opened` event auto-triggers triage. Watch the run:
```bash
/fullsend watch rhdh-agentic issue <N>
```

What to check:
- Route job succeeds (dispatch workflow changes work)
- Triage sandbox starts (image pulls correctly)
- No credential or path errors in logs
- Status comment posted on the issue

If triage succeeds, close the issue:
```bash
gh issue close <N> --repo redhat-developer/rhdh-agentic \
  --comment "Smoke test passed — triage ran successfully on <version>."
```

If it fails, inspect with `/fullsend inspect` and check the logs for
path mismatches, credential delivery failures, or toolchain errors.

### 7. Update ledger

Add a new dated section to `docs/fullsend-upgrade-ledger.md` with:
- Scope (versions, repos)
- Upstream changelog summary
- Per-repo decision tables
- PR links
- Any new gotchas discovered

## Known gotchas

1. **Stale local checkout**: always `git fetch --tags` before diffing.
2. **Silent path breakage**: mount path changes silently fail — files mount
   but the agent can't find them at the old path.
3. **Agent prompts reference harness paths**: grep `.md` files for old paths
   when `host_files[].dest` changes.
4. **Concurrency group cancellation**: `/fs-code` runs can be cancelled by
   triage bot comments. Re-trigger after triage completes.
5. **Agent skips branch creation**: for trivial changes, add explicit branch
   instructions in the `/fs-code` comment.
6. **Fork sync before branching**: stale forks cause phantom diffs in PRs.
7. **Workflow files need `workflows` token scope**: the fs-code agent cannot
   push `.github/workflows/` changes. Include in the manual PR.
