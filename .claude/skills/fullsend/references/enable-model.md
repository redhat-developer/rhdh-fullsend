# enable-model

Enable a partner model in the GCP Model Garden for `rhdh-sidekick-167988`.

## Usage

```
/fullsend enable-model <model-id>
```

- `model-id`: e.g. `claude-opus-5`, `claude-sonnet-5`, `grok-4.6`

## Prerequisites

| Gate | Check | If fail |
|------|-------|---------|
| GCP Owner | `gcloud projects get-iam-policy rhdh-sidekick-167988` | Need Owner via `rhdh-sidekick@redhat.com` group |
| Browser | `agent-browser --version` | `npm install -g agent-browser && agent-browser install` |

## Procedure

### 1. Verify current status

Check if the model is already enabled by visiting its Model Garden card.
An enabled model shows **Open in Agent Studio**; a not-enabled model shows
a grayed-out **Enable** button.

```bash
agent-browser --headed --session gcp-model-garden \
  open "https://console.cloud.google.com/agent-platform/model-garden?project=rhdh-sidekick-167988"
```

The user must log in to GCP interactively. Wait for confirmation.

### 2. Navigate and enable

1. Apply the provider filter (e.g. "Anthropic") in the left sidebar
2. Click the model card
3. Click **Enable** → opens the publisher questionnaire

### 3. Fill the questionnaire

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

### 4. Agree to terms

Click **Next** → review pricing → check the **Terms and agreements**
checkbox → click **Agree**.

Enablement is instant — no approval queue. Confirmation dialog:
"Successfully purchased \<model\>"

### 5. Update documentation

After enabling, update `docs/gcp-infrastructure.md`:
- Move the model from "Available but not enabled" to "Enabled partner models"
- Add the date and verification method

### 6. Smoke test

```bash
gh issue create --repo redhat-developer/rhdh-agentic \
  --title "test: smoke test <model-id> after Model Garden enablement" \
  --body "Smoke test — verify inference works with <model-id>.
Close this issue if triage succeeds."
```

## Known gotchas

1. **No "Haiku 4.6" exists.** The model is `claude-haiku-4-5` (Haiku 4.5).
   Model Garden names don't always match the version numbering you'd expect.
2. **Dropdowns are Material UI comboboxes.** The `select` command often
   doesn't work — click the parent `generic` element to open the listbox,
   then click the option.
3. **Browser session expiry.** GCP sessions expire; the user may need to
   re-authenticate. The `agent-browser` daemon can also relaunch and lose
   auth state.
4. **Google models don't need enablement.** All 129 Google models (Gemini
   family etc.) are available by default.
5. **Enablement is per-publisher, not per-model.** Once you fill the
   Anthropic form for one model, subsequent Anthropic models still require
   the form but the values are the same.
