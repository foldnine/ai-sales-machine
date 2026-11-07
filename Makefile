# ai-sales-machine
#
# Every target here is safe to run twice. The two that destroy data
# (clean, db-reset) refuse to run without CONFIRM=yes.

SHELL := /bin/bash
COMPOSE := docker compose
ENV_FILE := .env

.DEFAULT_GOAL := help

.PHONY: help init up down restart logs ps config validate test health \
	    migrate migrate-status env-upgrade seed-demo db db-reset \
	    pull-model models credentials workflows setup backup restore-drill restore-help shell-n8n secrets-scan clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	    | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

$(ENV_FILE):
	@echo "No .env found. Run 'make init' first." && exit 1

init: ## Create .env and Caddyfile from templates, generate secrets
	@./infra/scripts/bootstrap.sh

up: $(ENV_FILE) ## Start the whole stack
	$(COMPOSE) up -d
	@echo
	@echo "Stack starting. Check with: make ps / make health"

down: ## Stop the stack, keep all data
	$(COMPOSE) down

restart: ## Restart the stack (or one service: make restart SERVICE=n8n)
	$(COMPOSE) restart $(SERVICE)

logs: ## Follow logs (or one service: make logs SERVICE=n8n)
	$(COMPOSE) logs -f --tail=200 $(SERVICE)

ps: ## Show container status
	$(COMPOSE) ps

config: $(ENV_FILE) ## Render and validate the resolved compose configuration
	$(COMPOSE) config

validate: ## Validate compose syntax and shell scripts without starting anything
	@echo "==> docker compose config"
	@tmp=$$(mktemp); 	 sed -e 's/^POSTGRES_PASSWORD=$$/POSTGRES_PASSWORD=validate/' 	     -e 's/^N8N_ENCRYPTION_KEY=$$/N8N_ENCRYPTION_KEY=validate/' 	     .env.example > $$tmp; 	 $(COMPOSE) --env-file $$tmp config -q && echo "    compose OK"; 	 rc=$$?; rm -f $$tmp; exit $$rc
	@echo "==> shell scripts"
	@for f in scripts/*.sh infra/scripts/*.sh; do bash -n "$$f" && echo "    $$f OK"; done
	@echo "==> n8n workflows"
	@python3 infra/scripts/validate-workflows.py
	@echo "==> offer catalogue"
	@python3 infra/scripts/check-offers.py

test: ## Apply all migrations to a throwaway database and run postgres/tests (needs Docker, not the stack)
	@./infra/scripts/sql-test.sh

health: ## Run the full stack health check
	@./scripts/healthcheck.sh

migrate: $(ENV_FILE) ## Apply pending database migrations
	@./infra/scripts/migrate.sh

env-upgrade: $(ENV_FILE) ## Show how .env differs from the current stack; APPLY=yes to change it
	@./infra/scripts/env-upgrade.sh $(if $(filter yes,$(APPLY)),--apply,)

migrate-status: $(ENV_FILE) ## Show applied and pending migrations
	@./infra/scripts/migrate.sh --status

seed-demo: $(ENV_FILE) ## Load demo rows (example domains only, never in production)
	@echo "Loading postgres/seeds/0002_demo_data.sql"
	@docker exec -i aisales-postgres psql -v ON_ERROR_STOP=1 -q \
	    -U "$$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2)" \
	    -d "$$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2)" \
	    < postgres/seeds/0002_demo_data.sql
	@echo "done"

db: $(ENV_FILE) ## Open a psql shell on the application database
	@docker exec -it aisales-postgres psql \
	    -U "$$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2)" \
	    -d "$$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2)"

shell-n8n: ## Open a shell inside the n8n container
	@docker exec -it aisales-n8n /bin/sh

pull-model: models

models: $(ENV_FILE) ## Pull every Ollama model .env names; build the large-context variants
	@./infra/scripts/n8n-setup.sh models

credentials: $(ENV_FILE) ## Create the n8n credentials the workflows use, from .env (n8n must be up)
	@./infra/scripts/n8n-setup.sh credentials

workflows: $(ENV_FILE) ## Validate and import every workflow into n8n (all inactive)
	@./infra/scripts/n8n-setup.sh workflows

setup: $(ENV_FILE) ## First run after make up && make migrate: models, credentials, workflows
	@./infra/scripts/n8n-setup.sh all

deploy: $(ENV_FILE) ## Deploy origin/main: backup, migrate, import workflows, restart, health
	@./infra/scripts/deploy.sh

osm-refresh: $(ENV_FILE) ## Fill osm_snapshot from Geofabrik (or COUNTRIES=RS,HR); needs osmium-tool
	@./infra/scripts/osm-extract.sh $(COUNTRIES)

minimax-refresh: $(ENV_FILE) ## Fill directory_snapshot from Minimax's accounting directory (or COUNTRIES=RS)
	@./infra/scripts/minimax-directory.sh $(COUNTRIES)

backup: $(ENV_FILE) ## Dump the database to $BACKUP_DIR (encrypted if configured)
	@./scripts/backup.sh

restore-drill: $(ENV_FILE) ## Restore the newest backup (or FILE=...) into a throwaway container and check it
	@./infra/scripts/restore-drill.sh $(FILE)

restore-help: ## Print the restore procedure
	@sed -n '1,30p' scripts/backup.sh | grep -E '^#' | sed 's/^# \{0,1\}//'

secrets-scan: ## Fail if anything that looks like a credential is tracked by git
	@./infra/scripts/secrets-scan.sh

db-reset: ## DESTRUCTIVE: drop and recreate the schema. Needs CONFIRM=yes
ifneq ($(CONFIRM),yes)
	@echo "Refusing to run. This drops every table in the application schema."
	@echo "If you are sure: make db-reset CONFIRM=yes"
	@exit 1
endif
	@docker exec -i aisales-postgres psql -v ON_ERROR_STOP=1 \
	    -U "$$(grep -E '^POSTGRES_USER=' .env | cut -d= -f2)" \
	    -d "$$(grep -E '^POSTGRES_DB=' .env | cut -d= -f2)" \
	    -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
	@$(MAKE) migrate

clean: ## DESTRUCTIVE: remove containers AND all volumes. Needs CONFIRM=yes
ifneq ($(CONFIRM),yes)
	@echo "Refusing to run. This deletes the database, n8n workflows,"
	@echo "n8n credentials and every downloaded Ollama model."
	@echo "Take a backup first: make backup"
	@echo "If you are sure: make clean CONFIRM=yes"
	@exit 1
endif
	$(COMPOSE) down -v --remove-orphans
	@echo "volumes removed"
