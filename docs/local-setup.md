# Local Setup Guide

Running fullsend agents locally on macOS (Apple Silicon). Tested on macOS 15
with Podman 5.5.1, fullsend 0.13.0, and OpenShell 0.0.38.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| fullsend CLI | 0.13.0+ | `go install` or download from [GitHub Releases](https://github.com/fullsend-ai/fullsend/releases) |
| Podman | 5.5+ | `brew install podman` |
| OpenShell CLI | 0.0.38 | `uv tool install openshell==0.0.38` |
| OpenShell gateway | 0.0.38 | Download from [GitHub Releases](https://github.com/NVIDIA/OpenShell/releases) (see below) |
| GitHub PAT | — | `gh auth token` (must have `repo` scope) |
| GCP SA key | — | Provided by team lead (see [GCP section](#step-3-gcp-credentials)) |

## Architecture

```
Mac host                          Podman VM (libkrun)
┌─────────────────┐               ┌──────────────────────────────┐
│ fullsend CLI    │               │ openshell-gateway (Linux)    │
│ openshell CLI   │──SSH tunnel──▶│   └─ port 8080 (gRPC)       │
│                 │  (port 8080)  │   └─ port 8081 (health)     │
│                 │               │                              │
│                 │               │ Podman containers            │
│                 │               │   └─ sandbox (rhdh-fullsend- │
│                 │               │      code:latest)            │
│                 │               │      └─ supervisor           │
│                 │               │      └─ claude code agent    │
└─────────────────┘               └──────────────────────────────┘
```

On a managed Mac, the macOS application firewall blocks incoming TCP connections
to unsigned binaries. Since the gateway needs to be reachable from containers
inside the Podman VM, we run the gateway *inside* the VM and use an SSH tunnel
from the Mac to reach it.

## Step 1: Install OpenShell

```bash
# CLI (Python package)
uv tool install openshell==0.0.38

# Gateway binary for macOS (needed for --help/version, actual gateway runs in VM)
curl -fsSL https://github.com/NVIDIA/OpenShell/releases/download/v0.0.38/openshell-gateway-aarch64-apple-darwin.tar.gz \
  -o /tmp/openshell-gateway.tar.gz
tar xzf /tmp/openshell-gateway.tar.gz -C ~/.local/bin/

# Gateway binary for Linux arm64 (runs inside Podman VM)
curl -fsSL https://github.com/NVIDIA/OpenShell/releases/download/v0.0.38/openshell-gateway-aarch64-unknown-linux-gnu.tar.gz \
  -o /tmp/openshell-gateway-linux.tar.gz
tar xzf /tmp/openshell-gateway-linux.tar.gz -C /tmp/
```

Verify: `openshell --version` should show `0.0.38`.

## Step 2: Set up Podman

```bash
# Create a Podman machine if you don't have one
podman machine init --cpus 6 --memory 15360 --disk-size 120

# Start it
podman machine start
```

### Required Podman VM configuration

The `host_containers_internal_ip` setting tells Podman what IP to inject for
`host.containers.internal` inside containers. Set it to the bridge gateway IP
so containers can reach services running in the VM:

```bash
podman machine ssh -- 'sudo tee /etc/containers/containers.conf > /dev/null << EOF
[containers]
host_containers_internal_ip = "10.89.0.1"
EOF'
```

### Create the OpenShell network

```bash
podman network create openshell
```

### Copy the Linux gateway binary into the VM

```bash
cat /tmp/openshell-gateway | podman machine ssh -- \
  "mkdir -p /home/user/bin && cat > /home/user/bin/openshell-gateway && chmod +x /home/user/bin/openshell-gateway"
```

## Step 3: GCP Credentials

Fullsend uses **GCP Vertex AI** (not the Anthropic API directly). You need a
service account key for the `rhdh-sidekick-167988` project with the
`roles/aiplatform.user` role.

**If your team lead provides the key file:** save it to
`~/.config/fullsend/fullsend-local-credentials.json` and `chmod 600` it.

**If you need to create the SA yourself:** see
[GCP Infrastructure — Service Accounts](gcp-infrastructure.md#service-accounts)
for the full `gcloud` commands (create SA, grant role, generate key, rotate).

## Step 4: Create env files

```bash
mkdir -p ~/.config/fullsend
```

**`~/.config/fullsend/gcp-vertex.env`**:
```
ANTHROPIC_VERTEX_PROJECT_ID=rhdh-sidekick-167988
CLOUD_ML_REGION=us-east5
GOOGLE_CLOUD_PROJECT=rhdh-sidekick-167988
GOOGLE_APPLICATION_CREDENTIALS=/path/to/.config/fullsend/fullsend-local-credentials.json
FULLSEND_SANDBOX_IMAGE=ghcr.io/redhat-developer/rhdh-fullsend-code:latest
```

**`~/.config/fullsend/triage.env`**:
```
GH_TOKEN=<your-github-pat>
GITHUB_ISSUE_URL=https://github.com/<org>/<repo>/issues/<number>
```

Restrict permissions: `chmod 600 ~/.config/fullsend/*.env`

## Step 5: Start the gateway

### Generate a handshake secret

```bash
HANDSHAKE_SECRET="local-$(openssl rand -hex 16)"
echo "OPENSHELL_SSH_HANDSHAKE_SECRET=$HANDSHAKE_SECRET" > ~/.config/fullsend/gateway.env
chmod 600 ~/.config/fullsend/gateway.env
echo "Secret: $HANDSHAKE_SECRET"
```

### Start the gateway inside the Podman VM

```bash
source ~/.config/fullsend/gateway.env

podman machine ssh -- "OPENSHELL_PODMAN_SOCKET='/run/podman/podman.sock' \
  OPENSHELL_SSH_HANDSHAKE_SECRET='$OPENSHELL_SSH_HANDSHAKE_SECRET' \
  OPENSHELL_SUPERVISOR_IMAGE='ghcr.io/nvidia/openshell/supervisor:dfd47683e7da4f1a4a8fa5d77f92d3696e6a41f9' \
  OPENSHELL_GRPC_ENDPOINT='http://10.89.0.1:8080' \
  nohup /home/user/bin/openshell-gateway \
    --bind-address 0.0.0.0 \
    --health-port 8081 \
    --drivers podman \
    --disable-tls \
    --db-url 'sqlite:/home/user/gateway.db?mode=rwc' \
    > /tmp/openshell-gateway.log 2>&1 &"
```

### Create an SSH tunnel from the Mac to the VM

Find the SSH port: `podman machine inspect --format '{{.SSHConfig.Port}}'`

```bash
SSH_PORT=$(podman machine inspect --format '{{.SSHConfig.Port}}')
SSH_KEY=$(podman machine inspect --format '{{.SSHConfig.IdentityPath}}')

ssh -f -N \
  -L 8080:127.0.0.1:8080 \
  -L 8081:127.0.0.1:8081 \
  -i "$SSH_KEY" -p "$SSH_PORT" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@127.0.0.1
```

### Register the gateway with the CLI

```bash
openshell gateway add http://127.0.0.1:8080 --local --name local
openshell gateway select local
```

### Verify

```bash
curl -sf http://127.0.0.1:8081/healthz && echo "Gateway healthy"
```

## Step 6: Run an agent

Pick a test issue and update `GITHUB_ISSUE_URL` in your triage.env, then:

```bash
export ANTHROPIC_VERTEX_PROJECT_ID=rhdh-sidekick-167988
export CLOUD_ML_REGION=us-east5
export GOOGLE_CLOUD_PROJECT=rhdh-sidekick-167988
export GOOGLE_APPLICATION_CREDENTIALS=~/.config/fullsend/fullsend-local-credentials.json
export FULLSEND_SANDBOX_IMAGE=ghcr.io/redhat-developer/rhdh-fullsend-code:latest

# Source env files for GH_TOKEN and GITHUB_ISSUE_URL
source ~/.config/fullsend/triage.env

fullsend run triage \
  --fullsend-dir /path/to/fullsend/internal/scaffold/fullsend-repo/ \
  --target-repo /path/to/your/target-repo/ \
  --env-file ~/.config/fullsend/gcp-vertex.env \
  --env-file ~/.config/fullsend/triage.env \
  --no-post-script
```

`--no-post-script` prevents the agent from modifying the GitHub issue (labels,
comments). Remove it when you want the agent to act on its triage result.

### Using a locally built image

To test changes to the Containerfile before pushing:

```bash
podman build -t rhdh-fullsend-code:local \
  -f images/code/Containerfile images/code/

export FULLSEND_SANDBOX_IMAGE=localhost/rhdh-fullsend-code:local
```

### What to expect

- Sandbox creation: ~2-8 seconds
- Sandbox bootstrap (downloads fullsend binary): ~7 seconds
- Agent inference: ~30-60 seconds per iteration
- Total: ~2 minutes for a triage run

Output is written to `/tmp/fullsend/agent-triage-*/iteration-*/output/agent-result.json`.

## Token usage and cost

A triage run against a medium-sized repo (rhdh-agentic) uses approximately:

| Metric | Value |
|--------|-------|
| API calls | ~50 |
| Input tokens | ~100 |
| Output tokens | ~5,700 |
| Cache read tokens | ~770,000 |
| Cache create tokens | ~126,000 |
| **Estimated cost** | **~$2.00** |

Cache utilization is high (~85% cache read). Subsequent runs against the same
repo benefit from prompt caching and will cost less.

## Troubleshooting

### "no space left on device" during image pull

The Podman VM disk is full. Prune unused images:

```bash
podman system prune -a -f --volumes
```

### "unable to find network with name or ID openshell"

The openshell network was deleted (e.g., by a prune). Recreate it:

```bash
podman network create openshell
```

### "host containers internal IP address is empty"

The `host_containers_internal_ip` is not set in the VM's containers.conf.
See Step 2 above.

### "failed to connect to OpenShell server" in container logs

The supervisor inside the sandbox container can't reach the gateway. Common causes:

1. **macOS firewall** (managed Mac): Run the gateway inside the VM instead of on
   the Mac. See Step 5.
2. **Wrong GRPC endpoint**: Ensure the gateway is started with
   `OPENSHELL_GRPC_ENDPOINT='http://10.89.0.1:8080'` so containers use the bridge
   IP instead of `host.containers.internal` (which points to the Mac, not the VM).
3. **SSH tunnel down**: Re-establish the tunnel (Step 5).

### "attempt to write a readonly database"

The gateway's SQLite DB is in a read-only location. Use a writable path like
`/home/user/gateway.db` inside the VM.

### Podman machine won't start after months of inactivity

Try starting it directly. If it fails, you may need to recreate it:

```bash
podman machine rm podman-machine-default
podman machine init --cpus 6 --memory 15360 --disk-size 120
podman machine start
```

### Validation fails with "python3 jsonschema package is not installed"

Install jsonschema on the host: `pip install jsonschema`. This only affects the
host-side validation check, not the agent's inference.

### SSH tunnel drops

The SSH tunnel may drop if the terminal session closes or after a sleep/wake
cycle. Re-run the ssh command from Step 5.

## Apple Silicon (arm64) notes

- The custom image (`ghcr.io/redhat-developer/rhdh-fullsend-code`) is multi-arch
  — it works on both amd64 runners and arm64 Macs without overrides
- The supervisor image (`ghcr.io/nvidia/openshell/supervisor:dfd47...`) has arm64 support
- Download `aarch64-unknown-linux-gnu` gateway binary for the VM, `aarch64-apple-darwin` for the Mac

## Quick-start script

Save as `~/.config/fullsend/start-gateway.sh`:

```bash
#!/bin/bash
set -euo pipefail

source ~/.config/fullsend/gateway.env

# Start Podman if needed
podman machine list --format '{{.LastUp}}' | grep -q "Currently" || podman machine start

# Kill old gateway
podman machine ssh -- "pkill -f openshell-gateway 2>/dev/null" || true
sleep 1

# Start gateway in VM
podman machine ssh -- "OPENSHELL_PODMAN_SOCKET='/run/podman/podman.sock' \
  OPENSHELL_SSH_HANDSHAKE_SECRET='$OPENSHELL_SSH_HANDSHAKE_SECRET' \
  OPENSHELL_SUPERVISOR_IMAGE='ghcr.io/nvidia/openshell/supervisor:dfd47683e7da4f1a4a8fa5d77f92d3696e6a41f9' \
  OPENSHELL_GRPC_ENDPOINT='http://10.89.0.1:8080' \
  nohup /home/user/bin/openshell-gateway \
    --bind-address 0.0.0.0 --health-port 8081 --drivers podman --disable-tls \
    --db-url 'sqlite:/home/user/gateway.db?mode=rwc' \
    > /tmp/openshell-gateway.log 2>&1 &"
sleep 3

# SSH tunnel
SSH_PORT=$(podman machine inspect --format '{{.SSHConfig.Port}}')
SSH_KEY=$(podman machine inspect --format '{{.SSHConfig.IdentityPath}}')
pkill -f "ssh.*-L 8080:127.0.0.1:8080" 2>/dev/null || true
sleep 1
ssh -f -N -L 8080:127.0.0.1:8080 -L 8081:127.0.0.1:8081 \
  -i "$SSH_KEY" -p "$SSH_PORT" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  root@127.0.0.1
sleep 2

# Verify
curl -sf http://127.0.0.1:8081/healthz && echo "Gateway ready" || echo "FAILED"
```
