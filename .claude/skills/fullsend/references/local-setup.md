# local-setup

Guide for running fullsend agents locally on a Mac. Covers only RHDH-specific setup — for the generic fullsend/OpenShell installation, follow the upstream guide first.

## Usage

```
/fullsend help setup
/fullsend help local
```

## Procedure

### 1. Upstream first

Direct the user to the canonical upstream guide for all generic setup:

```
📘 Follow the upstream guide first:
   https://github.com/fullsend-ai/fullsend/blob/main/docs/guides/user/running-agents-locally.md

   It covers: fullsend CLI download, OpenShell install, GCP credentials,
   GitHub token, Podman setup, and running default agents.

   Come back here after completing those steps for the RHDH-specific additions below.
```

### 2. RHDH GCP project

Our agents run on the `rhdh-sidekick-167988` GCP project. If the user's team lead provides a service account key, they save it to `~/.config/fullsend/fullsend-local-credentials.json`. If they need to create a SA themselves, point them to `docs/gcp-infrastructure.md` in this repo.

Present the GCP env file with our project values filled in:

```
# ~/.config/fullsend/gcp-vertex.env
ANTHROPIC_VERTEX_PROJECT_ID=rhdh-sidekick-167988
CLOUD_ML_REGION=us-east5
GOOGLE_CLOUD_PROJECT=rhdh-sidekick-167988
GOOGLE_APPLICATION_CREDENTIALS=/path/to/.config/fullsend/fullsend-local-credentials.json
FULLSEND_SANDBOX_IMAGE=ghcr.io/redhat-developer/rhdh-fullsend-code:latest
```

### 3. RHDH custom sandbox image

Our image extends upstream with corepack + yarn for JS monorepos:

```
ghcr.io/redhat-developer/rhdh-fullsend-code:latest
```

To test a locally built image instead:

```bash
podman build -t rhdh-fullsend-code:local \
  -f images/code/Containerfile images/code/

export FULLSEND_SANDBOX_IMAGE=localhost/rhdh-fullsend-code:local
```

### 4. Managed Mac workaround (macOS application firewall)

On a managed Mac, the macOS application firewall blocks incoming TCP connections to unsigned binaries. Since the OpenShell gateway needs to be reachable from containers inside the Podman VM, we run the gateway **inside** the VM and use an SSH tunnel from the Mac to reach it.

Show this architecture:

```
Mac host                          Podman VM (libkrun)
┌─────────────────┐               ┌──────────────────────────────┐
│ fullsend CLI    │               │ openshell-gateway (Linux)    │
│ openshell CLI   │──SSH tunnel──▶│   └─ port 8080 (gRPC)       │
│                 │  (port 8080)  │   └─ port 8081 (health)     │
│                 │               │                              │
│                 │               │ Podman containers            │
│                 │               │   └─ sandbox container       │
└─────────────────┘               └──────────────────────────────┘
```

#### Required Podman VM configuration

```bash
podman machine ssh -- 'sudo tee /etc/containers/containers.conf > /dev/null << EOF
[containers]
host_containers_internal_ip = "10.89.0.1"
EOF'
```

#### Copy the Linux gateway binary into the VM

After downloading the Linux arm64 gateway binary per upstream instructions:

```bash
cat /path/to/openshell-gateway | podman machine ssh -- \
  "mkdir -p /home/user/bin && cat > /home/user/bin/openshell-gateway && chmod +x /home/user/bin/openshell-gateway"
```

#### Create the OpenShell network

```bash
podman network create openshell
```

#### Generate a handshake secret

```bash
HANDSHAKE_SECRET="local-$(openssl rand -hex 16)"
echo "OPENSHELL_SSH_HANDSHAKE_SECRET=$HANDSHAKE_SECRET" > ~/.config/fullsend/gateway.env
chmod 600 ~/.config/fullsend/gateway.env
```

#### Start the gateway inside the VM

```bash
source ~/.config/fullsend/gateway.env

podman machine ssh -- "OPENSHELL_PODMAN_SOCKET='/run/podman/podman.sock' \
  OPENSHELL_SSH_HANDSHAKE_SECRET='$OPENSHELL_SSH_HANDSHAKE_SECRET' \
  OPENSHELL_SUPERVISOR_IMAGE='ghcr.io/nvidia/openshell/supervisor:dfd47683e7da4f1a4a8fa5d77f92d3696e6a41f9' \
  OPENSHELL_GRPC_ENDPOINT='http://10.89.0.1:8080' \
  nohup /home/user/bin/openshell-gateway \
    --bind-address 0.0.0.0 --health-port 8081 --drivers podman --disable-tls \
    --db-url 'sqlite:/home/user/gateway.db?mode=rwc' \
    > /tmp/openshell-gateway.log 2>&1 &"
```

#### SSH tunnel from Mac to VM

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

#### Register and verify

```bash
openshell gateway add http://127.0.0.1:8080 --local --name local
openshell gateway select local
curl -sf http://127.0.0.1:8081/healthz && echo "Gateway healthy"
```

### 5. Quick-start script

Offer this as `~/.config/fullsend/start-gateway.sh` for one-command gateway startup:

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

### 6. Running an RHDH agent

After gateway is running, show a typical triage run:

```bash
# Agent-specific env
# ~/.config/fullsend/triage.env
GH_TOKEN=<your-github-pat>
GITHUB_ISSUE_URL=https://github.com/<org>/<repo>/issues/<number>
```

```bash
fullsend run triage \
  --fullsend-dir /path/to/fullsend/internal/scaffold/fullsend-repo/ \
  --target-repo /path/to/your/target-repo/ \
  --env-file ~/.config/fullsend/gcp-vertex.env \
  --env-file ~/.config/fullsend/triage.env \
  --no-post-script
```

`--no-post-script` prevents the agent from modifying the GitHub issue. Remove it when you want the agent to act on its triage result.

Refer to the upstream guide's per-agent env var tables for `code`, `review`, and `fix` agents.

### 7. What to expect

| Metric | Value |
|--------|-------|
| Sandbox creation | ~2-8 seconds |
| Bootstrap | ~7 seconds |
| Agent inference | ~30-60 seconds per iteration |
| Total (triage) | ~2 minutes |
| Estimated cost (triage) | ~$2.00 |

Output: `/tmp/fullsend/agent-triage-*/iteration-*/output/agent-result.json`

### 8. Troubleshooting (RHDH-specific)

For generic troubleshooting (sandbox creation, missing env vars, arm64 image pulls), see the upstream guide.

RHDH-specific issues:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Gateway unreachable from container | macOS firewall blocks unsigned binaries | Run gateway inside Podman VM (see step 4) |
| `OPENSHELL_GRPC_ENDPOINT` wrong | Containers use bridge IP, not `host.containers.internal` | Set to `http://10.89.0.1:8080` |
| SSH tunnel dropped | Terminal closed or sleep/wake cycle | Re-run the SSH command from step 4 |
| `openshell` network missing | Pruned by `podman system prune` | `podman network create openshell` |
| `host containers internal IP address is empty` | `containers.conf` not set in VM | See step 4 (Podman VM configuration) |
| `attempt to write a readonly database` | Gateway SQLite in read-only location | Use `/home/user/gateway.db` inside VM |
