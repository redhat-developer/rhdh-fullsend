# GCP Infrastructure

GCP project, Workload Identity Federation, IAM, and service account reference
for the RHDH fullsend setup.

## Project context

| Field | Value |
|-------|-------|
| GCP project ID | `rhdh-sidekick-167988` |
| GCP project number | `189673402608` |
| Fullsend GCP region | `global` (SDK routing; Vertex AI resolves internally) |
| WIF pool | `fullsend-inference` (ACTIVE) |
| IAM admin group | `rhdh-sidekick@redhat.com` |
| Project role | **Owner** (via `group:rhdh-sidekick@redhat.com`) |

The project lives under `IT Public Cloud > Sandbox > Customers` in the GCP
org hierarchy. The admin group has Owner, which includes all permissions
needed to manage WIF, IAM, and Model Garden.

### IAM incident 2026-09-09

An Ansible/AAP automation (`aap-access-sa@utility-project-468319`) ran
`SetIamPolicy` (full replace, not merge) on `rhdh-sidekick-167988` at
12:59 UTC, overwriting the project policy with only the Owner binding.
This removed `roles/aiplatform.user` from all Fullsend WIF principals.

Bindings were restored on 2026-09-10 using `add-iam-policy-binding`
(which merges, not replaces). To prevent recurrence, IT/AAP must be told
to use `add-iam-policy-binding` or read-modify-write with etag checks
instead of `set-iam-policy`.

## Model Garden

The Model Garden (console path: Agent Platform → Models → Model Garden)
lists models from Google and partner publishers. Google models (129) are
available by default — no enablement step needed. Partner models require
per-publisher enablement via a form.

Once a partner model is enabled, it is available to all principals with
`roles/aiplatform.user` — i.e. all ~52 WIF-enabled repos across both orgs.

### Enabled partner models

| Model | Model ID | Status | Verified |
|-------|----------|--------|----------|
| Claude Sonnet 5.5 | `claude-sonnet-5-5` | Enabled | 2026-10-08 (Model Garden console) |
| Claude Opus 4.6 | `claude-opus-4-6` | Enabled | 2026-09-10 (triage agent, issue #143) |
| Claude Sonnet 4.6 | `claude-sonnet-4-6` | Enabled | 2026-09-10 (Model Garden console) |
| Claude Haiku 4.5 | `claude-haiku-4-5` | Enabled | 2026-09-10 (Model Garden console) |

### Per-agent model assignments (rhdh-agentic)

| Agent | Model alias | Resolves to | Rationale |
|-------|-------------|-------------|-----------|
| triage | `haiku` | `claude-haiku-4-5` | Fast, cost-efficient for issue classification |
| review | `sonnet` | `claude-sonnet-4-6` | Quality/cost balance for code reviews |
| code, fix, grillme | (default) | `claude-opus-4-6` | Maximum capability for code generation |

Configured via `agents[].model` in `.fullsend/config.yaml`
([per-agent settings](https://fullsend.sh/docs/runtimes#per-agent-runtime-model-and-effort)).
The aliases resolve through fullsend's pinned alias table — no
`models.aliases` override needed.

### Available but not enabled (as of 2026-09-10)

**Anthropic** (12 models in garden):

| Model | Model ID |
|-------|----------|
| Claude Fable 5.1 | `claude-fable-5-1` |
| Claude Opus 5 | `claude-opus-5` |
| Claude Sonnet 5 | `claude-sonnet-5` |
| Claude Fable 5 | `claude-fable-5` |
| Claude Opus 4.8 | `claude-opus-4-8` |
| Claude Opus 4.7 | `claude-opus-4-7` |
| Claude Opus 4.5 | `claude-opus-4-5` |
| Claude Sonnet 4.5 | `claude-sonnet-4-5` |
| Claude Opus 4.1 | `claude-opus-4-1` |

**xAI** (6 models in garden):

| Model | Model ID |
|-------|----------|
| Grok 4.6 | `grok-4.6` |
| Grok 4.3 | `grok-4.3` |
| Grok 4.20 (Reasoning) | `grok-4.20` |
| Grok 4.20 (Non-Reasoning) | `grok-4.20` |
| Grok 4.1 Fast (Reasoning) | `grok-4.1-fast` |
| Grok 4.1 Fast (Non-Reasoning) | `grok-4.1-fast` |

Other partners: Meta (21), Mistral AI (9), NVIDIA (4), Stability.ai (4),
and others. See Model Garden console for the full list.

### Google models (no enablement needed)

129 models available by default, including the Gemini family:
Gemini 3.8 Flash, 3.7 Flash, 3.6 Flash, 3.5 Flash / Flash Lite,
3.1 Pro Preview, and others.

### How to enable a partner model

Requires Owner credentials on `rhdh-sidekick-167988`.

1. Go to [Model Garden](https://console.cloud.google.com/agent-platform/model-garden?project=rhdh-sidekick-167988)
2. Click the model card → click **Enable**
3. Fill in the publisher questionnaire:

   | Field | Value |
   |-------|-------|
   | Business name | `Red Hat` |
   | Business website | `https://www.redhat.com` |
   | Contact email | `rhdh-sidekick@redhat.com` |
   | Headquartered | `United States of America` |
   | Industry | `Telecommunications` |
   | Intended users | `Internal employees` |
   | Use cases | `Agentic software development lifecycle (SDLC) automation for enterprise Backstage plugins` |
   | Additional requirements (AUP) | `No` |

4. Click **Next** → review pricing (usage-based, billed monthly)
5. Check the **Terms and agreements** checkbox
6. Click **Agree** → confirmation dialog appears

An enabled model shows **Open in Agent Studio** instead of **Enable** on
its card. Enablement is instant — no approval queue.

Use a smoke-test issue to confirm end-to-end inference (Model Garden
enablement alone is necessary but the only reliable test is a real agent
run through WIF-federated credentials).

Model access cannot be verified via `gcloud` CLI or raw REST calls with
user credentials — it only works through WIF-federated credentials used by
the Fullsend SDK. Use a smoke-test issue to confirm end-to-end inference.

## Fleet vs. WIF-enabled repos

There are two levels of fullsend integration:

| Level | Count | What it means |
|-------|-------|---------------|
| **WIF-enabled** | ~52 | Has a WIF provider → *can* use Vertex AI. Created by `fullsend admin install`. |
| **Fleet-managed** | 4 | Listed in `repos.yaml` → centrally upgraded, version-pinned, scaffold-synced. |

Fleet-managed repos (see `repos.yaml`):
- `redhat-developer/rhdh-agentic`
- `redhat-developer/rhdh-cli`
- `redhat-developer/rhdh-plugins`
- `redhat-developer/rhdh-plugin-export-overlays`

To onboard a new repo into the fleet, use `/fullsend onboard <org>/<repo>`.

## WIF pool and providers

All repos use a single pool (`fullsend-inference`). Each repo gets its own
OIDC provider scoped via `attribute-condition`. List all providers:

```bash
gcloud iam workload-identity-pools providers list \
  --location=global --workload-identity-pool=fullsend-inference \
  --project=rhdh-sidekick-167988 --format="table(name.basename(), attributeCondition)"
```

A previous `fullsend-pool` (3 manually provisioned providers) was
consolidated into `fullsend-inference` on 2026-09-10 and deleted.

### Creating a new WIF provider

```bash
PROVIDER_NAME="gh-redhat-developer-<repo>"  # max 32 chars
PROVIDER_PATH="projects/189673402608/locations/global/workloadIdentityPools/fullsend-inference/providers/${PROVIDER_NAME}"

gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
  --location=global \
  --workload-identity-pool=fullsend-inference \
  --project=rhdh-sidekick-167988 \
  --issuer-uri=https://token.actions.githubusercontent.com \
  --allowed-audiences="fullsend-mint,https://iam.googleapis.com/${PROVIDER_PATH}" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository == '<org>/<repo>'"
```

### Dual-audience requirement

Two audiences are required in `--allowed-audiences`:

| Audience | Used by | Step |
|----------|---------|------|
| `fullsend-mint` | Mint token exchange | GitHub OIDC → fullsend session token |
| `https://iam.googleapis.com/projects/189673402608/.../providers/<name>` | `google-github-actions/auth` | GCP credential setup for Vertex AI |

Omitting the second audience causes an `audience mismatch` error at the
"Setup GCP" step in the workflow. The `fullsend admin install` CLI sets
both automatically; manual provider creation must include both.

### IAM bindings

Org-level `aiplatform.user` bindings cover all repos in both orgs:

| Org | Principal set |
|-----|---------------|
| `redhat-developer` | `principalSet://.../fullsend-inference/attribute.repository_owner/redhat-developer` |
| `rhdh-parasol` | `principalSet://.../fullsend-inference/attribute.repository_owner/rhdh-parasol` |

No per-repo IAM binding is needed — the org-level principal sets cover all
repos automatically.

## Mint configuration

The mint URL is stored as a GitHub Actions variable (`FULLSEND_MINT_URL`)
on each repo, not hardcoded in the workflow. The workflow references it via
`${{ vars.FULLSEND_MINT_URL }}`.

| Repo | Mint URL |
|------|----------|
| `redhat-developer/rhdh-agentic` | `https://mint.fullsend.sh` |
| `redhat-developer/rhdh-cli` | `https://mint.fullsend.sh` |
| `redhat-developer/rhdh-plugins` | `https://mint.fullsend.sh` |
| `redhat-developer/rhdh-plugin-export-overlays` | `https://mint.fullsend.sh` |

All repos (including ~52 WIF-enabled repos in both `redhat-developer` and
`rhdh-parasol` orgs) use public mint. Switched from private mint
(`https://fullsend-mint-gljhbkcloq-uc.a.run.app`) on 2026-09-10.

To change the mint URL on a repo:

```bash
gh variable set FULLSEND_MINT_URL --body "https://mint.fullsend.sh" --repo <org>/<repo>
```

The `repos.yaml` fleet manifest also stores `mint_url`. When running
`fullsend repos install -f repos.yaml`, it sets this variable on each repo
automatically. Direct `gh variable set` is equivalent and takes effect
immediately.

## Service accounts

For local agent runs (not CI). Run `/fullsend help setup` for the full local setup guide.

### Creating a service account

```bash
gcloud iam service-accounts create fullsend-local \
  --display-name="Fullsend local agent runner" \
  --project=rhdh-sidekick-167988
```

There is a propagation delay of a few seconds before the SA can be used in
IAM bindings.

### Granting Vertex AI access

```bash
gcloud projects add-iam-policy-binding rhdh-sidekick-167988 \
  --member="serviceAccount:fullsend-local@rhdh-sidekick-167988.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user" \
  --condition=None
```

`--condition=None` is required because the project has conditional IAM
bindings. Without it, `gcloud` prompts interactively.

### Creating a JSON key

```bash
gcloud iam service-accounts keys create \
  ~/.config/fullsend/fullsend-local-credentials.json \
  --iam-account=fullsend-local@rhdh-sidekick-167988.iam.gserviceaccount.com

chmod 600 ~/.config/fullsend/fullsend-local-credentials.json
```

The key file contains a private key. Do not commit it to git or share via
Slack. If compromised:

```bash
KEY_ID=$(python3 -c "import json,sys; print(json.load(sys.stdin)['private_key_id'])" \
  < ~/.config/fullsend/fullsend-local-credentials.json)
gcloud iam service-accounts keys delete "$KEY_ID" \
  --iam-account=fullsend-local@rhdh-sidekick-167988.iam.gserviceaccount.com
```

### Per-person service accounts

For individual usage tracking, create per-person SAs:

```bash
NAME="fullsend-local-<name>"  # kebab-case, max 30 chars

gcloud iam service-accounts create "$NAME" \
  --display-name="Fullsend local – <Name>" \
  --project=rhdh-sidekick-167988

gcloud projects add-iam-policy-binding rhdh-sidekick-167988 \
  --member="serviceAccount:${NAME}@rhdh-sidekick-167988.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user" \
  --condition=None

gcloud iam service-accounts keys create "/tmp/${NAME}-credentials.json" \
  --iam-account="${NAME}@rhdh-sidekick-167988.iam.gserviceaccount.com"
```

Share the key file securely (Bitwarden, 1Password — never Slack or email)
and delete the local copy.

### Key rotation

Create a new key before deleting the old one to avoid downtime:

```bash
gcloud iam service-accounts keys create \
  ~/.config/fullsend/fullsend-local-credentials-new.json \
  --iam-account=fullsend-local@rhdh-sidekick-167988.iam.gserviceaccount.com

# Test with the new key, then:
OLD_KEY_ID=$(python3 -c "import json,sys; print(json.load(sys.stdin)['private_key_id'])" \
  < ~/.config/fullsend/fullsend-local-credentials.json)
gcloud iam service-accounts keys delete "$OLD_KEY_ID" \
  --iam-account=fullsend-local@rhdh-sidekick-167988.iam.gserviceaccount.com

mv ~/.config/fullsend/fullsend-local-credentials-new.json \
  ~/.config/fullsend/fullsend-local-credentials.json
```

## IAM troubleshooting

### "Permission 'aiplatform.endpoints.predict' denied"

The WIF principal has no `roles/aiplatform.user` binding. Verify:

```bash
gcloud projects get-iam-policy rhdh-sidekick-167988 \
  --flatten="bindings[].members" \
  --filter="bindings.members:principalSet" \
  --format="table(bindings.role, bindings.members)"
```

If the binding is missing, add it using the org-level principal set (covers
all repos under `redhat-developer`):

```bash
gcloud projects add-iam-policy-binding rhdh-sidekick-167988 \
  --role="roles/aiplatform.user" \
  --member="principalSet://iam.googleapis.com/projects/189673402608/locations/global/workloadIdentityPools/fullsend-inference/attribute.repository_owner/redhat-developer" \
  --condition=None
```

### Installer claims success but binding is missing

The `fullsend admin install` CLI may report "granted roles/aiplatform.user"
even when the conditional `projectIamAdmin` role silently blocks the grant.
Always verify with `gcloud projects get-iam-policy` after install. IAM
propagation can take up to 7 minutes.

### "audience mismatch" at Setup GCP step

The WIF provider was created with only one allowed audience. Update it to
include both:

```bash
gcloud iam workload-identity-pools providers update-oidc <provider-name> \
  --location=global \
  --workload-identity-pool=fullsend-inference \
  --project=rhdh-sidekick-167988 \
  --allowed-audiences="fullsend-mint,https://iam.googleapis.com/<wif-provider-path>"
```

### Monitoring Vertex AI usage

Via GCP Console: Vertex AI → Model Garden → Usage page. Filter by service
account for per-SA token consumption.

Via CLI:

```bash
gcloud logging read \
  'resource.type="aiplatform.googleapis.com/Endpoint" AND
   protoPayload.authenticationInfo.principalEmail="fullsend-local@rhdh-sidekick-167988.iam.gserviceaccount.com"' \
  --project=rhdh-sidekick-167988 \
  --limit=10 \
  --format="table(timestamp, protoPayload.request.model, protoPayload.response.usageMetadata)"
```
