# rhdh-fullsend

Custom fullsend sandbox images for the RHDH team's agent infrastructure.

## Why this repo exists

The upstream [fullsend-code](https://github.com/fullsend-ai/fullsend) sandbox
image ships with Go, Python, and shell tooling but no JavaScript package
manager. The rhdh-plugins monorepo (23 workspaces, yarn) requires yarn to run
tests, linting, and OpenSpec validation. Without it baked into the image, agents
spend 10-15 minutes bootstrapping corepack/yarn on every run — and the
workaround (a `host_files`-mounted shell script) is fragile.

This repo builds a single image that extends `fullsend-code:latest` with
corepack and yarn pre-activated.

## Image

```
ghcr.io/fullsend-ai/fullsend-code:latest   (upstream)
  └── ghcr.io/redhat-developer/rhdh-fullsend-code:latest   (this repo)
```

| What's added | Why |
|-------------|-----|
| `corepack enable` | `/usr` is read-only in the sandbox — can't enable at runtime |
| `corepack prepare yarn@stable` | Pre-downloads yarn binary, zero cold-start |
| `/usr/local/bin/yarn` wrapper | Git hooks (husky) run in subprocesses without the agent's PATH |

## Tags

| Tag | When | Use |
|-----|------|-----|
| `latest` | Push to `main` | Production — harness configs reference this |
| `dev` | Any non-PR build | Testing and CI |
| `X.Y.Z` | Tag push `v*` | Immutable release pin |
| `X.Y` | Tag push `v*` | Floating minor for auto-patch |
| `<sha>` | Every non-PR build | Debugging and rollback |

PRs build but don't push (validation only).

## Usage

Reference in your fullsend harness config:

```yaml
# .fullsend/customized/harness/code.yaml
image: ghcr.io/redhat-developer/rhdh-fullsend-code:latest
```

This replaces the `sandbox-yarn-setup.sh` + `host_files` workaround.

## Local agent runs

See [docs/local-setup.md](docs/local-setup.md) for the full guide: Podman VM,
OpenShell gateway, GCP credentials, SSH tunnel, and running agents end-to-end.

## Local build

Requires Podman (or Docker). Builds for your native architecture only.

```bash
podman build -t rhdh-fullsend-code:local \
  -f images/code/Containerfile images/code/
```

### Testing locally with fullsend

After building, use the local image for `fullsend run` by setting the
`FULLSEND_SANDBOX_IMAGE` env var:

```bash
export FULLSEND_SANDBOX_IMAGE=localhost/rhdh-fullsend-code:local

fullsend run code \
  --fullsend-dir /path/to/fullsend/internal/scaffold/fullsend-repo/ \
  --target-repo /path/to/rhdh-plugins/ \
  --env-file ~/.config/fullsend/gcp-vertex.env \
  --env-file ~/.config/fullsend/code.env \
  --no-post-script
```

### Verifying the image contents

```bash
# Check yarn is available
podman run --rm rhdh-fullsend-code:local yarn --version

# Check corepack home
podman run --rm rhdh-fullsend-code:local ls -la /usr/local/share/corepack/

# Interactive shell for debugging
podman run --rm -it rhdh-fullsend-code:local bash
```

### Cross-platform build (requires QEMU)

Build for a different architecture (e.g., amd64 on an Apple Silicon Mac):

```bash
podman build --platform linux/amd64 -t rhdh-fullsend-code:amd64 \
  -f images/code/Containerfile images/code/
```

## Adding more tools

Edit `images/code/Containerfile`. Follow the upstream pattern:
- Pin versions via `ARG`
- Verify checksums with `sha256sum -c` for binary downloads
- Keep `USER sandbox` as the last line

## Upstream tracking

This image inherits everything from `fullsend-code:latest`. When upstream
updates their base image (Claude Code, gitleaks, Go, etc.), our image picks
it up automatically on the next rebuild. Pin `BASE_IMAGE` to a specific
digest if you need reproducibility:

```dockerfile
ARG BASE_IMAGE=ghcr.io/fullsend-ai/fullsend-code@sha256:abc123...
```
