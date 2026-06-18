.DEFAULT_GOAL := help

COMPOSE := $(if $(shell command -v podman 2>/dev/null),podman compose,docker compose)

.PHONY: fetch up down local viewer help

define start-viewer
	$(COMPOSE) -f docker-compose.fullsend.yaml up -d
	@echo "AgentsView: http://$$(hostname).local:$${AGENTSVIEW_PORT:-8081}"
endef

# Fetch fullsend agent runs from GitHub Actions into ./runs
fetch:
	./scripts/fetch-fullsend-runs.sh

# Fetch runs + start AgentsView container (Podman preferred, Docker fallback)
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
	@echo "  make fetch          - Download fullsend runs from GitHub Actions"
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
	@echo "  AGENTSVIEW_PORT  - Host port (default: 8081)"
	@echo "  AGENTSVIEW_HOST  - Public hostname for remote access (default: localhost)"
