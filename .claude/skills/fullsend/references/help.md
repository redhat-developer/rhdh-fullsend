# help

Context-aware onboarding companion for fullsend. Shows the agent pipeline, inspects the local deployment's customizations, and links to upstream docs.

## Usage

```
/fullsend help [topic]
```

- No argument: show all sections
- `agents`: agent pipeline and catalog
- `setup` or `local`: getting started / running locally
- `customization` or `config`: how to customize agents, skills, harness

## Procedure

### 1. Resolve the target repo

Follow the repo resolution order from the SKILL.md `<repo_resolution>` section to find the repo with `.fullsend/` configuration.

If in a monorepo (e.g., `rhdh-plugins`), note this — the agent operates at repo level, not workspace level.

### 2. Route by topic

| Argument | Sections to show |
|----------|-----------------|
| _(none)_ | All: pipeline → local deployment → upstream links |
| `agents` | Pipeline + agent catalog only |
| `setup` / `local` | Getting started links + prerequisites only |
| `customization` / `config` | Local deployment inspection + customization links |

### 3. Agent pipeline (topic: `agents` or all)

Display this pipeline diagram:

```
┌─────────────────── Fullsend Agent Pipeline ───────────────────┐
│                                                               │
│  issue opened                                                 │
│       │                                                       │
│       ▼                                                       │
│    triage ─── /fs-triage                                      │
│       │                                                       │
│       │ adds `ready-to-code` label (auto for bugs/docs/perf)  │
│       ▼                                                       │
│     code ──── /fs-code                                        │
│       │                                                       │
│       │ pushes branch, creates PR, adds `ready-for-review`    │
│       ▼                                                       │
│    review ─── /fs-review                                      │
│       │                                                       │
│       ├── approved ──────────────────────▶ merge              │
│       │                                      │                │
│       └── changes requested                  ▼                │
│              │                            retro ── /fs-retro  │
│              ▼                                                │
│            fix ──── /fs-fix                                   │
│              │                                                │
│              └── back to review (max iterations capped)       │
│                                                               │
│  Scoring (independent):  prioritize ── /fs-prioritize         │
│  Diagnostics:            debug ──────── /fs-debug             │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

Then show the agent catalog:

| Agent | Trigger | What it does |
|-------|---------|-------------|
| **triage** | New issue opened, `/fs-triage` | Assesses issue, asks clarifying questions, labels `ready-to-code` for bugs/docs/perf |
| **code** | `ready-to-code` label, `/fs-code` | Implements fix/feature in sandbox, commits to feature branch |
| **review** | `ready-for-review` label, `/fs-review` | Multi-dimension code review (correctness, security, style, docs) |
| **fix** | Review requests changes, `/fs-fix` | Addresses specific review findings, pushes fix commit |
| **retro** | PR merged/closed, `/fs-retro` | Retrospective on the full workflow — files improvement issues |
| **prioritize** | Schedule or `/fs-prioritize` | RICE scoring for project board ranking |
| **debug** | `/fs-debug` | Sandbox diagnostics — checks toolchain, network, env |

All agents run in a sandboxed container (OpenShell) with no direct push access. Pre/post scripts on the runner handle git operations and safety gates (secret scanning, protected path checks).

### 4. Local deployment inspection (topic: `customization` or all)

Read the target repo's `.fullsend/` directory and present a deployment summary. This section is dynamic — it reflects the actual state of the repo's configuration.

#### 4a. Read config.yaml

```bash
cat <repo>/.fullsend/config.yaml
```

Show which roles are enabled:
```
Enabled roles: triage, coder, review, fix
```

#### 4b. Scan customized directory

```bash
ls <repo>/.fullsend/customized/harness/*.yaml 2>/dev/null
ls <repo>/.fullsend/customized/agents/*.md 2>/dev/null
ls <repo>/.fullsend/customized/skills/*/SKILL.md 2>/dev/null
ls <repo>/.fullsend/customized/env/*.env 2>/dev/null
ls <repo>/.fullsend/customized/policies/*.yaml 2>/dev/null
```

#### 4c. For each customized harness, read it and summarize the overrides

For each `*.yaml` in `customized/harness/`, read the file and extract:
- `image` — what custom image is used (and why it differs from upstream)
- `skills` — what skills are loaded (especially custom ones)
- `host_files` — what extra env/config files are mounted
- `policy` — which network policy is applied
- `timeout_minutes` — if different from upstream default

Present as a per-agent summary:

```
## Your Deployment

### code agent (customized)
  Image:    ghcr.io/redhat-developer/rhdh-fullsend-code:latest
  Skills:   code-implementation, monorepo-workspace-routing (custom)
  Env:      gcp-vertex.env, code-agent.env, rhdh-toolchain.env (custom), yarn-proxy.env (custom)
  Policy:   policies/code.yaml (custom — adds repo.yarnpkg.com, corepack binary)
  Timeout:  35 min
  Prompt:   agents/code.md (customized — adds monorepo routing, zero-trust principle)

### fix agent (customized)
  Image:    ghcr.io/redhat-developer/rhdh-fullsend-code:latest
  Skills:   fix-review, monorepo-workspace-routing (custom)
  ...

### triage agent (upstream defaults)
### review agent (upstream defaults)
```

Mark items as "(custom)" when they exist in `customized/` and differ from the upstream scaffold default. For agents without customizations, show as "upstream defaults."

#### 4d. Custom skills

For each skill in `customized/skills/`, read the `SKILL.md` and show name + description:

```
### Custom Skills
- monorepo-workspace-routing — Navigate to the correct workspace in a monorepo before starting work
```

#### 4e. Custom env files

For each `.env` in `customized/env/`, show what it sets:

```
### Custom Env Files
- rhdh-toolchain.env — sets COREPACK_HOME=/tmp/corepack (writable dir for corepack)
- yarn-proxy.env — maps HTTP_PROXY → YARN_HTTP_PROXY (yarn ignores standard proxy vars)
```

### 5. Upstream docs (topic: `setup` or all)

Present as a linked reference table. Construct URLs as `https://github.com/fullsend-ai/fullsend/blob/main/<path>`.

```
## Learn More

### Getting Started
- [Installation & setup](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/getting-started/installation.md)
- [GitHub setup](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/getting-started/github-setup.md)
- [Running agents locally](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/running-agents-locally.md)

### Agent Reference
- [Agent catalog](https://github.com/fullsend-ai/fullsend/blob/main/docs/agents/README.md)
- [Code agent](https://github.com/fullsend-ai/fullsend/blob/main/docs/agents/code.md)
- [Triage agent](https://github.com/fullsend-ai/fullsend/blob/main/docs/agents/triage.md)
- [Review agent](https://github.com/fullsend-ai/fullsend/blob/main/docs/agents/review.md)
- [Fix agent](https://github.com/fullsend-ai/fullsend/blob/main/docs/agents/fix.md)
- [Prioritize agent](https://github.com/fullsend-ai/fullsend/blob/main/docs/agents/prioritize.md)
- [Retro agent](https://github.com/fullsend-ai/fullsend/blob/main/docs/agents/retro.md)

### Customization
- [Customizing agents (harness config)](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/customizing-agents.md)
- [Customizing with AGENTS.md](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/customizing-with-agents-md.md)
- [Customizing with skills](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/customizing-with-skills.md)
- [Bugfix workflow](https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/bugfix-workflow.md)

### Architecture
- [Architecture overview](https://github.com/fullsend-ai/fullsend/blob/main/docs/architecture.md)
- [Glossary](https://github.com/fullsend-ai/fullsend/blob/main/docs/glossary.md)
- [Vision](https://github.com/fullsend-ai/fullsend/blob/main/docs/vision.md)
```

### 6. Suggest next steps

Based on the context, suggest relevant `/fullsend` commands:

- "Run `/fullsend validate` to check your customizations against upstream for drift."
- "Run `/fullsend trigger code #<N>` to trigger the code agent on an issue."
- "Run `/fullsend inspect <run-id>` to investigate a specific agent run."
