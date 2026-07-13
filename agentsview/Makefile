.DEFAULT_GOAL := help

COMPOSE := $(if $(shell command -v podman 2>/dev/null),podman compose,docker compose)
AGENTSVIEW_HOST ?= $(shell hostname).local
AGENTSVIEW_PORT ?= 8081
export AGENTSVIEW_HOST AGENTSVIEW_PORT

.PHONY: artifacts convert fetch up down local viewer reconvert help

# Auto-recover Podman VM if it died (macOS libkrun drops on sleep)
define ensure-podman
	$(if $(shell command -v podman 2>/dev/null),\
		podman info >/dev/null 2>&1 || podman machine start 2>/dev/null || true)
endef

define start-viewer
	$(ensure-podman)
	$(COMPOSE) -f docker-compose.fullsend.yaml up -d
	@echo "AgentsView: http://$${AGENTSVIEW_HOST}:$${AGENTSVIEW_PORT}"
endef

# Download artifact ZIPs from GitHub Actions into ./artifacts (cached)
artifacts:
	./scripts/fetch-artifacts.sh

# Convert cached artifacts into AgentsView layout in ./runs
convert:
	./scripts/convert-artifacts.sh

# Download + convert (replaces old fetch-fullsend-runs.sh)
fetch: artifacts convert

# Re-convert all artifacts from scratch (clears ./runs first)
reconvert:
	./scripts/convert-artifacts.sh --force

# Fetch + start AgentsView container (Podman preferred, Docker fallback)
up: fetch
	$(start-viewer)

# Import local fullsend run(s) + start AgentsView (only local runs shown)
# Usage: make local              (auto-discovers from $TMPDIR/fullsend)
#        make local DIR=/path    (explicit path)
local:
	./scripts/import-local-run.sh $(if $(DIR),"$(DIR)",)
	AGENTSVIEW_RUNS=./runs-local $(start-viewer)

# Start AgentsView without fetching (use after manual imports)
viewer:
	$(start-viewer)

# Stop AgentsView container
down:
	$(COMPOSE) -f docker-compose.fullsend.yaml down -v

help:
	@echo "AgentsView fullsend integration"
	@echo ""
	@echo "  make artifacts      - Download artifact ZIPs (cached in ./artifacts)"
	@echo "  make convert        - Convert artifacts into AgentsView layout"
	@echo "  make fetch          - Download + convert (artifacts → runs)"
	@echo "  make reconvert      - Re-convert all artifacts (clears runs/ first)"
	@echo "  make up             - Fetch + start AgentsView (all remote runs)"
	@echo "  make local          - Import local run(s) + start AgentsView (auto-discovers)"
	@echo "  make viewer         - Start AgentsView without fetching"
	@echo "  make down           - Stop AgentsView"
	@echo ""
	@echo "Local run examples:"
	@echo "  make local                                                # auto-discover"
	@echo "  make local DIR=/tmp/fullsend                              # explicit --output-dir"
	@echo "  make local DIR=/tmp/fullsend/agent-triage-3705-1234567890 # single run"
	@echo ""
	@echo "Environment variables:"
	@echo "  AGENTSVIEW_PORT           - Host port (default: 8081)"
	@echo "  AGENTSVIEW_HOST           - Public hostname (default: <hostname>.local)"
