# Repo Onboarding Guide

How to install fullsend on a new repo in the `redhat-developer` GitHub org.

## Architecture

The RHDH team uses a **hybrid model**:

- **Inference** — own GCP project `rhdh-sidekick-167988` (cost accounting
  goes to the RHDH cost center)
- **Token mint** — shared service at `fullsend-mint-gljhbkcloq-uc.a.run.app`
  (managed by the fullsend team, heading toward fully public managed service)

```
redhat-developer/<repo>
  └── .github/workflows/fullsend.yaml (shim)
        └── calls fullsend-ai/fullsend reusable workflows @v0
              └── authenticates via WIF
                    ├── rhdh-sidekick-167988 (inference, cost accounting)
                    └── fullsend-mint (shared mint — GitHub App tokens)
```

Each repo gets its own WIF provider scoped to that single repo. The fullsend
GitHub Apps are the public `fullsend-ai-*` app set (shared across orgs).

## Method 1: Standard install (`fullsend admin install`)

Use this for repos that need no customization — the installer creates a
default shim workflow and scaffold.

```bash
fullsend admin install <org>/<repo> \
  --inference-project rhdh-sidekick-167988 \
  --mint-url https://fullsend-mint-gljhbkcloq-uc.a.run.app \
  --skip-mint-check
```

The installer auto-provisions:
- WIF pool + provider in `rhdh-sidekick-167988`
- IAM binding (`aiplatform.user`) for the repo
- `.fullsend/config.yaml` and scaffold directories
- `.github/workflows/fullsend.yaml` shim workflow
- GitHub repository variables and secrets

### What `--skip-mint-check` does

Skips GCP API calls to the mint project. Required because we don't have
access to the fullsend team's mint project (`it-gcp-konflux-dev-fullsend`).

## Method 2: Manual install (customized shim)

Use this for repos that need a **customized shim workflow** — auth gate for
public repos, `paths` filter for monorepo workspace scoping, or custom
agents/skills. The installer would overwrite these customizations.

### Prerequisites

- `gcloud` CLI authenticated with a user in the `rhdh-sidekick@redhat.com`
  group (needs `iam.workloadIdentityPoolAdmin` on `rhdh-sidekick-167988`)
- `gh` CLI authenticated with `repo` + `workflow` scopes and admin access
  to the target repo
- WIF pool `fullsend-pool` already exists on `rhdh-sidekick-167988`
- fullsend GitHub Apps already installed in `redhat-developer` org with
  access to the target repo

### Step 1: Create WIF provider

See [GCP Infrastructure — WIF Providers](gcp-infrastructure.md#wif-providers)
for the full `gcloud` command and the dual-audience requirement.

Provider name must be max 32 characters, lowercase alphanumeric + dashes.

### Step 2: Set GitHub variables and secrets

```bash
gh variable set FULLSEND_MINT_URL --repo <org>/<repo> \
  --body "https://fullsend-mint-gljhbkcloq-uc.a.run.app"
gh variable set FULLSEND_GCP_REGION --repo <org>/<repo> \
  --body "global"
gh secret set FULLSEND_GCP_WIF_PROVIDER --repo <org>/<repo> \
  --body "<wif-provider-path>"
gh secret set FULLSEND_GCP_PROJECT_ID --repo <org>/<repo> \
  --body "rhdh-sidekick-167988"
```

### Step 3: Commit fullsend files via PR

Create a PR with:

| File | Purpose |
|------|---------|
| `.fullsend/config.yaml` | Enabled roles (triage, coder, review, fix) |
| `.github/workflows/fullsend.yaml` | Customized shim (auth gate, paths filter) |
| `.fullsend/customized/` | Scaffold dirs + custom agents/skills/harness overrides |
| `.github/CODEOWNERS` | Protect `.fullsend/` and `.github/workflows/fullsend.yaml` |

**For public repos**, add an `author_association` auth gate to the dispatch
job's `if` condition. Without it, any GitHub user can post `/fs-review` and
burn Vertex AI tokens on your GCP project. Gate to
`OWNER/MEMBER/COLLABORATOR`:

```yaml
# In the dispatch job
if: >-
  github.event.comment &&
  contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'),
    github.event.comment.author_association)
```

**For monorepos**, add a `paths` filter on `pull_request_target` to scope
auto-review to a specific workspace:

```yaml
on:
  pull_request_target:
    paths:
      - 'workspaces/<pilot-workspace>/**'
```

### Step 4: Grant fullsend GitHub Apps access

Ensure the target repo is added to the repository access list for each
fullsend-ai GitHub App. Manage via org settings → Installed GitHub Apps.

The 5 per-repo apps:

| App | Roles |
|-----|-------|
| `fullsend-ai-triage` | triage |
| `fullsend-ai-coder` | coder, fix |
| `fullsend-ai-review` | review |
| `fullsend-ai-retro` | retro |
| `fullsend-ai-prioritize` | prioritize |

### Step 5: Verify

After merge, post `/fs-review` on a PR to trigger the review agent:

```bash
gh run list --workflow=fullsend.yaml --repo <org>/<repo> --limit 3
gh run view <run-id> --repo <org>/<repo> --log
```

## Current repo status

| Repo | Status | Install method | Notes |
|------|--------|----------------|-------|
| `rhdh-agentic` | Live (2026-05-20) | `fullsend admin install` | Custom review agent with OpenSpec skill |
| `rhdh-plugins` | Live (2026-06-02) | Manual | Review scoped to `workspaces/scorecard/`, auth-gated slash commands |
| `rhdh-plugin-export-overlays` | WIF configured, PR pending | Manual | Custom workspace-review skill, scoped to `backstage-plugins-for-aws` |

## Key learnings

1. **Use per-repo mode** — simpler than org mode, works for private repos,
   no org-wide config repo needed.

2. **Use the shared mint** — don't self-host unless you have a strong
   reason. The fullsend team manages it and is heading toward a public
   managed service.

3. **Get your own GCP project for inference** — even if you start on the
   shared project, switch early for cost tracking.

4. **Pre-install GitHub Apps before running the CLI** — smoother than the
   interactive flow that opens browser windows.

5. **Add CODEOWNERS immediately** — protect `.fullsend/` and
   `.github/workflows/` from agent modifications.

6. **Expect slash commands, not automation** — most agents need manual
   triggering via `/fs-*`. Only Review auto-triggers reliably on PR
   open/update.

7. **Budget 3-5 days for GCP/IT coordination** — the biggest time sink is
   permissions, not the install itself. IT sandbox projects use conditional
   IAM that prevents self-service.

8. **Add an auth gate on slash commands for public repos** — fullsend
   doesn't check `author_association` on `issue_comment` events.

9. **WIF providers need two allowed audiences** — `fullsend-mint` for the
   mint token step, and the full provider URL for `google-github-actions/auth`.
   Omitting either causes auth failures. See
   [GCP Infrastructure](gcp-infrastructure.md#wif-providers).
