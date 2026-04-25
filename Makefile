# network-security-lab — Makefile
# All Docker operations run from the docker/ directory.
# Run `make help` to see available targets.

COMPOSE_DIR := docker
COMPOSE_FILE := $(COMPOSE_DIR)/docker-compose.yml
ENV_FILE     := $(COMPOSE_DIR)/.env

.PHONY: help up down restart status logs lint test-rules test-injection \
        test-all backup certs-generate clean llm-logs ollama-pull

# ── Help ──────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "network-security-lab"
	@echo "────────────────────────────────────────────────────────"
	@echo "  make up              Start the full stack (Wazuh + Ollama + LLM service)"
	@echo "  make down            Stop the stack (volumes preserved)"
	@echo "  make restart         Restart all services"
	@echo "  make status          Show container health status"
	@echo "  make logs            Tail logs from all containers"
	@echo "  make logs s=<name>   Tail logs from a specific service"
	@echo "  make llm-logs        Tail logs from llm-service only"
	@echo "  make ollama-pull     Re-pull the Ollama model"
	@echo ""
	@echo "  make test-rules      Run rule regression tests"
	@echo "  make test-injection  Run prompt injection safety tests"
	@echo "  make test-all        Run all tests"
	@echo "  make lint            Lint XML, YAML, shell scripts, Python"
	@echo ""
	@echo "  make backup          Run backup script"
	@echo "  make certs-generate  Generate self-signed certs for dev"
	@echo "  make clean           Remove stopped containers and dangling images"
	@echo ""

# ── Stack lifecycle ───────────────────────────────────────────────────────────
up: _check-env
	@echo "→ Starting Wazuh stack..."
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) up -d
	@echo "→ Stack started. Dashboard: https://localhost"
	@echo "→ Run 'make status' to check health."

down:
	@echo "→ Stopping Wazuh stack (volumes preserved)..."
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) down

restart:
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) restart

status:
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) ps

logs:
ifdef s
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) logs -f $(s)
else
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) logs -f
endif

# ── Tests ─────────────────────────────────────────────────────────────────────
test-rules:
	@echo "→ Running rule regression tests..."
	@bash tests/rules/run-all.sh

test-injection:
	@echo "→ Running prompt injection safety tests..."
	@bash tests/security/run-injection-tests.sh

test-all: test-rules test-injection
	@echo "→ All tests complete."

# ── LLM service helpers ───────────────────────────────────────────────────────
llm-logs:
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) logs -f llm-service

ollama-pull: _check-env
	@echo "→ Pulling Ollama model $$(grep OLLAMA_MODEL $(ENV_FILE) | cut -d= -f2)..."
	docker exec ollama ollama pull $$(grep OLLAMA_MODEL $(ENV_FILE) | cut -d= -f2)

# ── Lint ──────────────────────────────────────────────────────────────────────
lint:
	@echo "→ Linting XML..."
	@find wazuh/ -name "*.xml" -exec xmllint --noout {} \; && echo "  XML OK" || echo "  xmllint not installed — skipping"
	@echo "→ Linting YAML..."
	@find . -name "*.yml" -o -name "*.yaml" | grep -v ".git" | xargs -I{} sh -c 'python3 -c "import yaml,sys; yaml.safe_load(open(\"{}\")); print(\"  OK: {}\")" 2>/dev/null || true'
	@echo "→ Linting shell scripts..."
	@find scripts/ -name "*.sh" -exec bash -n {} \; && echo "  Shell OK"
	@echo "→ Linting Python..."
	@if command -v flake8 >/dev/null 2>&1; then \
		flake8 llm/service/ --max-line-length=100 --exclude=__pycache__ && echo "  Python OK"; \
	else \
		echo "  flake8 not installed — skipping Python lint"; \
	fi
	@echo "→ Lint complete."

# ── Backup ────────────────────────────────────────────────────────────────────
backup:
	@echo "→ Running backup..."
	@bash scripts/backup.sh

# ── Certificate generation (dev only) ────────────────────────────────────────
certs-generate:
	@echo "→ Generating self-signed certificates for development..."
	@bash scripts/generate-certs.sh
	@echo "→ Certs written to docker/certs/"
	@echo "⚠  These are for development only. Use proper PKI in production."

# ── Cleanup ───────────────────────────────────────────────────────────────────
clean:
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) down --remove-orphans
	docker image prune -f

# ── Internal helpers ──────────────────────────────────────────────────────────
_check-env:
	@if [ ! -f $(ENV_FILE) ]; then \
		echo ""; \
		echo "ERROR: $(ENV_FILE) not found."; \
		echo "  cp docker/.env.example docker/.env"; \
		echo "  Then edit docker/.env and set all passwords."; \
		echo ""; \
		exit 1; \
	fi
