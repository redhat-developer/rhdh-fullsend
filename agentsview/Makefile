.DEFAULT_GOAL := help

COMPOSE := $(if $(shell command -v podman 2>/dev/null),podman compose,docker compose)

.PHONY: fetch up down help

# Fetch fullsend agent runs from GitHub Actions into ./runs
fetch:
	./scripts/fetch-fullsend-runs.sh

# Fetch runs + start AgentsView container (Podman preferred, Docker fallback)
up: fetch
	$(COMPOSE) -f docker-compose.fullsend.yaml up -d
	@echo "AgentsView: http://$$(hostname).local:$${AGENTSVIEW_PORT:-8081}"

# Stop AgentsView container
down:
	$(COMPOSE) -f docker-compose.fullsend.yaml down

help:
	@echo "AgentsView fullsend integration"
	@echo ""
	@echo "  make fetch  - Download fullsend runs from GitHub Actions"
	@echo "  make up     - Fetch + start AgentsView (http://localhost:8081)"
	@echo "  make down   - Stop AgentsView"
	@echo ""
	@echo "Environment variables:"
	@echo "  AGENTSVIEW_PORT  - Host port (default: 8081)"
	@echo "  AGENTSVIEW_HOST  - Public hostname for remote access (default: localhost)"
