# Sandbox Networking

DNS and networking inside OpenShell sandboxes — why `yarn install` (and any
tool that resolves DNS directly) fails, and how to work around it.

## Two-layer network namespace architecture

OpenShell sandboxes are **not** plain containers. Each sandbox is a
**nested network namespace** inside a container. The agent process runs one
layer deeper than the container's network.

```
┌─── Host (macOS / CI runner) ────────────────────────────────────┐
│                                                                 │
│  Podman network "openshell" (10.89.0.0/24)                      │
│    aardvark-dns on bridge interface (10.89.0.1:53) ✅            │
│                                                                 │
│  ┌─── Container (10.89.0.3 on "openshell" network) ──────────┐ │
│  │  /etc/resolv.conf → nameserver 10.89.0.1  (works here)    │ │
│  │  openshell-sandbox process (PID 1 = supervisor)            │ │
│  │                                                            │ │
│  │  veth-h-* (10.200.0.1)  ← host side of veth pair          │ │
│  │    └── :3128  L7 transparent proxy ✅ (only listener)       │ │
│  │    └── :53    ❌ nothing listening                          │ │
│  │         │                                                  │ │
│  │  ┌──── │ ──── Inner netns (sandbox-*) ──────────────────┐  │ │
│  │  │  veth-s-* (10.200.0.2)  ← sandbox side              │  │ │
│  │  │  default route → 10.200.0.1                          │  │ │
│  │  │  /etc/resolv.conf → nameserver 10.89.0.1 (INHERITED) │  │ │
│  │  │                     ^^^^^^^^^^^^^^^^^^^               │  │ │
│  │  │                     UNREACHABLE from 10.200.0.0/24    │  │ │
│  │  │                                                       │  │ │
│  │  │  Agent (Claude Code), yarn, node, git run here        │  │ │
│  │  └───────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Why DNS fails

1. **HTTP/HTTPS traffic works.** The supervisor sets up iptables rules that
   intercept all outbound TCP from the inner netns and redirect it to the
   L7 proxy at `10.200.0.1:3128`. The proxy resolves DNS from the container
   netns (where `10.89.0.1` IS reachable), applies policy, and forwards.

2. **DNS does NOT work.** The inner netns inherits `/etc/resolv.conf` from
   the container, pointing to `10.89.0.1` (Podman's aardvark-dns). But the
   inner netns only has a route to `10.200.0.0/24` — it cannot reach
   `10.89.0.0/24`. All direct DNS queries fail with `getaddrinfo EAI_AGAIN`.

3. **This is by design.** OpenShell deliberately provides no DNS inside the
   sandbox. The security model requires all network access to go through
   the L7 proxy, which resolves DNS on behalf of the client. DNS is a
   separate channel that would bypass policy enforcement (DNS exfiltration).

## What works vs. what doesn't

| Tool | Works? | Why |
|------|--------|-----|
| `curl https://...` | ✅ | Intercepted by transparent proxy |
| `node -e "fetch('https://...')"` | ✅ | Node's fetch connects to IP; proxy intercepts TCP |
| `gh api ...` | ✅ | Uses HTTPS |
| `yarn install` | ❌ | Yarn Berry calls `getaddrinfo` before `fetch` |
| `pip install` | ❌ | Same — resolves DNS first |
| `go get` | ❌ | Same |
| `git clone` (HTTPS) | ❌ | libcurl resolves DNS first |
| `nslookup`, `dig` | ❌ | Direct DNS queries |
| `dns.resolve()` (Node.js) | ❌ | Direct DNS queries |

## Workaround: explicit proxy in .yarnrc.yml

Set `httpProxy`/`httpsProxy` pointing to the L7 proxy. Yarn sends HTTP
CONNECT to the proxy, which resolves DNS and forwards the request.

**Tested approach:** Use an env file that maps OpenShell's `HTTP_PROXY` to
Yarn's proxy config (no hardcoded IPs):

```
# .fullsend/customized/env/yarn-proxy.env
YARN_HTTP_PROXY=${HTTP_PROXY:-http://10.200.0.1:3128}
YARN_HTTPS_PROXY=${HTTPS_PROXY:-http://10.200.0.1:3128}
```

Smoke test result (`yarn add is-odd` with proxy config):
```
➤ YN0000: · Yarn 4.6.0
➤ YN0085: │ + is-odd@npm:3.0.1, is-number@npm:6.0.0
➤ YN0000: └ Completed in 0s 226ms
➤ YN0013: │ 2 packages were added to the project (+ 16.65 KiB).
➤ YN0000: └ Completed in 0s 497ms
```

**Not yet validated:** Full `yarn install` on the rhdh-plugins monorepo
(hundreds of packages). The smoke test covered a single package.

## Upstream issue tracking

| Issue | Status | Relevance |
|-------|--------|-----------|
| [OpenShell#364](https://github.com/NVIDIA/OpenShell/issues/364) | Closed wontfix | DNS resolution fails — maintainer: "DNS is incidental. Tools should use HTTPS_PROXY." |
| [OpenShell#1107](https://github.com/NVIDIA/OpenShell/issues/1107) | Open, assigned | Proposes `/etc/hosts` injection for policy-allowed hostnames at sandbox creation. Would fix this cleanly. |
| [OpenShell#1169](https://github.com/NVIDIA/OpenShell/issues/1169) | Closed (fixed) | Why DNS is intentionally blocked — DNS exfiltration bypass vector |

The OpenShell team's position: the sandbox intentionally has no DNS. All
network access must go through the L7 proxy. This is a security design
decision, not a bug.

## Why it seems to work in CI

CI (GitHub Actions) uses the same stack — Podman + OpenShell + same
`action.yml`. The inner netns is identical. `yarn install` works in CI
because Node.js's `undici` (used by yarn's fetch) handles connections in a
way that gets intercepted by the transparent proxy before DNS resolution
is needed.

## Verified facts (2026-06-09)

Captured from a live running sandbox:

```
# Container netns (supervisor)
$ ip addr → eth0: 10.89.0.3/24, veth-h-*: 10.200.0.1/24
$ nslookup registry.npmjs.org 10.89.0.1 → ✅ 104.16.x.34
$ ss -tlnp → 10.200.0.1:3128 (proxy)

# Inner sandbox netns (agent)
$ ip addr → veth-s-*: 10.200.0.2/24
$ nslookup registry.npmjs.org 10.89.0.1 → ❌ connection refused
$ nslookup registry.npmjs.org 10.200.0.1 → ❌ connection refused
```
