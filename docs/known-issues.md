# Known Issues

Active friction points, workarounds, and upstream tracking for the RHDH
fullsend setup. Last updated: 2026-06-09.

## Sandbox and tooling

| Issue | Impact | Workaround | Status |
|-------|--------|------------|--------|
| DNS broken inside sandboxes | `yarn install`, `pip install`, `git clone` fail with `getaddrinfo EAI_AGAIN` | Explicit `httpProxy`/`httpsProxy` in `.yarnrc.yml` pointing to the L7 proxy | By design — see [Sandbox Networking](sandbox-networking.md) |
| `yarn install` takes 10-15 min in sandbox | Monorepo overhead for large workspaces | Custom image with yarn pre-installed eliminates bootstrap; consider pre-installing deps | Open |
| Git hooks (husky) need yarn in PATH | Hooks run in subprocesses without the agent's PATH | Custom image with `/usr/local/bin/yarn` wrapper — see [rhdh-fullsend-code image](../README.md) | Solved |
| Sandbox creation timeout (60s) for large images | Code agent uses `fullsend-code:latest` (larger than triage sandbox) | Upstream fix exists (pre-pull + retry + 120s timeout) but not in `@v0` tag. Set `FULLSEND_SANDBOX_READY_TIMEOUT=180` as env var. | Fixed upstream, pending `@v0` release |
| `/etc/resolv.conf` points to unreachable nameserver | Tools timeout instead of failing fast | None — consider filing OpenShell issue | Open |

## Agent behavior

| Issue | Impact | Workaround | Status |
|-------|--------|------------|--------|
| Triage doesn't auto-trigger on `issues/opened` | Must use `/fs-triage` slash command | Post `/fs-triage` as issue comment | By design — dispatcher only handles `issues/labeled` |
| Coder doesn't auto-trigger from triage | Triage labels `triaged`, not `ready-to-code` | Post `/fs-code` manually after triage | By design |
| Fix only triggers from bot reviews | Human `changes_requested` reviews don't trigger fix agent | Post `/fs-fix` manually | By design |
| Retro dropped by concurrency group collision | Retro job gets cancelled by other dispatch jobs | Post `/fs-retro` manually in a quiet window | Open |
| Custom agent stages not supported in per-repo mode | Cannot register custom `/fs-*` slash commands | Extend existing agents with custom skills instead of building standalone agents | Architectural limitation |

## Monorepo-specific

| Issue | Impact | Workaround | Status |
|-------|--------|------------|--------|
| No workspace awareness | Agent sees full repo context, not just the workspace a PR touches | `paths` filter on `pull_request_target` for workspace-level triggering | Partial — shim-level only |
| Routing skill: label priority | Agent guesses workspace from title/body instead of trusting `workspace/*` label | Improve routing skill to prioritize existing labels | Open |
| Routing skill not in triage harness | Triage has no workspace awareness — can misroute issues | Add routing skill to triage harness | Open |
| `workspace/*` labels not automated | Must manually create labels when adding workspaces | Automate label creation when a new workspace is added | Open |

## Observability

| Issue | Impact | Workaround | Status |
|-------|--------|------------|--------|
| Agent transcript not visible inline in GHA logs | Must download artifact separately | `gh run download <run-id> --name fullsend-code` | Open |
| No summary in GHA step output | Hard to see what the agent did at a glance | Consider post-script step extracting key actions from transcript | Open |

## Upstream harness drift

Customized harness and policy files are **copies** of upstream (baseline
2026-06-05). When upstream changes, our copies need manual sync:

| File | Repo |
|------|------|
| `harness/code.yaml` | rhdh-plugins |
| `harness/fix.yaml` | rhdh-plugins |
| `policies/code.yaml` | rhdh-plugins |
| `policies/fix.yaml` | rhdh-plugins |
| `agents/code.md` | rhdh-plugins |

## Upstream feature requests

| Issue | Description | Status |
|-------|-------------|--------|
| [fullsend#1937](https://github.com/fullsend-ai/fullsend/issues/1937) | Native `working_dir` field in harness schema | Filed |
| `repo.yarnpkg.com` missing from upstream policies | Any JS monorepo using corepack + yarn hits this | Not yet filed |
| `sandbox_init_script` in harness schema | Pre-agent env setup without relying on `.env.d` or skills | Not yet filed |
| [OpenShell#1107](https://github.com/NVIDIA/OpenShell/issues/1107) | `/etc/hosts` injection for policy-allowed hostnames | Open, assigned |

## `@v0` tag regression risk

Commit `709d8af0` (2026-05-15) fixed per-repo retro/prioritize routing by
removing the `retro|prioritize → fullsend` stage-to-role mapping. However,
PR #1187 (`005ac0a1`, 2026-05-19) re-introduced the old mapping on `main`.
The `@v0` tag predates this regression, so per-repo mode is currently safe.

**Risk:** If `@v0` advances past PR #1187, per-repo retro and prioritize
will silently break for all consumer orgs whose config lists
`retro`/`prioritize` instead of `fullsend`.

## Public repo security

Fullsend's `issue_comment` trigger routes to agents without checking
`author_association`. Any external user posting `/fs-review` on a public
repo's PR triggers Vertex AI inference on the repo owner's GCP project.

**Mitigation:** Add an `author_association` check to the dispatch job in
the shim workflow. Applied in rhdh-plugins and rhdh-plugin-export-overlays.
See [Repo Onboarding — Method 2](repo-onboarding.md#method-2-manual-install-customized-shim).
