# debug

Run sandbox environment diagnostics to verify the agent runtime is healthy.

The debug agent is a **custom fullsend agent** — the first one built outside the built-in dispatch chain. It reuses the code agent's sandbox identity (same image, policy, host_files, coder token) but only performs diagnostics. Results are posted as a comment on the triggering issue.

## Usage

```
/fullsend debug <#issue> [--repo owner/name]
```

This is a shortcut for `/fullsend trigger debug <#issue>`. See `trigger.md` for the full procedure.

### Direct dispatch (fallback)

If the `/fs-debug` slash-command dispatch fails (GITHUB_TOKEN permission issues), trigger directly:

```bash
gh workflow run fullsend-debug.yml --repo <owner/name> --ref main \
  -f issue_key="<N>" -f issue_source="github"
```

## What it checks

| Group | Checks | Why it matters |
|-------|--------|---------------|
| Env vars | COREPACK, YARN, PROXY, NODE, GCP vars | Confirms .env.d files were sourced |
| Yarn & corepack | which, version, readlink | Confirms toolchain is on PATH |
| COREPACK_HOME | Set? Writable? | Must be `/tmp/corepack` (not /usr) |
| Network / proxy | node fetch to npm, yarn config, gh api, curl (expect blocked) | Confirms policy + proxy work |
| Node & tools | node, openspec, gh versions | Confirms image has expected tools |
| Filesystem | /tmp writable, /usr not writable, whoami, disk space | Confirms sandbox isolation |
| .env.d files | List files in /sandbox/workspace/.env.d/ | Confirms host_files delivery |
| GCP credentials | Credential JSON + OIDC token present | Confirms auth will work |

## Output

The agent posts a structured summary as a comment on the triggering issue (via `post-debug.sh`). The comment is tagged with `<!-- fullsend:debug-agent -->` for identification.

The full transcript is also available in the `fullsend-debug` artifact.

## Architecture (template for custom agents)

```
.github/workflows/
  fullsend-debug-dispatch.yml   ← slash-command listener (/fs-debug)
  fullsend-debug.yml            ← standalone agent workflow

.fullsend/customized/
  agents/debug.md               ← agent prompt (diagnostic checks)
  harness/debug.yaml            ← sandbox config (reuses code policy)
  scripts/post-debug.sh         ← posts results to issue (untrusted output!)
```

### Workflow steps (fullsend-debug.yml)

1. Checkout repo + target-repo + upstream defaults (scaffold)
2. Prepare workspace (layer scaffold defaults → customized overrides)
3. Validate enrollment
4. Mint coder token (same GitHub App identity as code agent)
5. Setup GCP via WIF + prepare sandbox credentials
6. Setup agent env (DEBUG_ prefix)
7. Install fullsend CLI
8. `fullsend run debug`
9. Upload artifact (always)

### Security: post-script and untrusted output

The agent runs inside an untrusted sandbox. `post-debug.sh` treats all agent output as untrusted:

- Text extracted via `jq` (no shell eval of agent strings)
- Truncated to 60k chars (GitHub comment limit is 65536)
- Posted via `--body-file -` (piped stdin, no shell interpolation)
- `ISSUE_NUMBER` validated as numeric, `REPO_FULL_NAME` validated as `owner/repo`

### Known issues

- **Dispatch 401**: The `fullsend-debug-dispatch.yml` uses `GITHUB_TOKEN` for `gh workflow run`, which calls GraphQL to resolve the default branch. Some repos restrict `GITHUB_TOKEN` GraphQL access. Workaround: pass `--ref main` explicitly, or use direct `gh workflow run` from the CLI.

- **Only in rhdh-agentic**: The debug agent is currently only set up in rhdh-agentic. To use in rhdh-plugins, port the four files listed above.

## Building more custom agents

The debug agent is the worked example for the custom agents guide. For the full walkthrough — scaffold pattern, harness anatomy, workspace layering, dispatch workflow, post-script security, and limitations — see `references/custom-agents.md`.
