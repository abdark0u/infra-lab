# Atajos para el día a día con infra-lab, para no tener que acordarme de los comandos
# largos de docker compose. Ejecuta `make` (o `make help`) para verlos todos.

SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose
# Para validar uso la plantilla, así no hace falta un .env con contraseñas de verdad
COMPOSE_LINT := docker compose --env-file .env.example
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.10.0
DASHBOARD := monitoring/grafana/dashboards/infra-lab-overview.json

KEEP ?= 7
FILE ?= latest
YES ?=
S ?=

.PHONY: help env up down restart ps logs health lint scan backup restore clean

help: ## Muestra esta ayuda
	@echo "Uso: make <comando> [VARIABLE=valor]"
	@echo
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-9s %s\n", $$1, $$2}'
	@echo
	@echo "Variables: KEEP=N (backup), FILE=ruta|latest y YES=1 (restore), S=servicio (logs)"

env: ## Crea .env con contrasenas aleatorias (no sobrescribe uno existente)
	@./scripts/init-env.sh

up: env ## Construye y levanta el stack esperando a los healthchecks
	$(COMPOSE) up -d --build --wait --wait-timeout 180

down: ## Para el stack (conserva los datos)
	$(COMPOSE) down

restart: down up ## Reinicia el stack

ps: ## Estado de los servicios
	$(COMPOSE) ps

logs: ## Logs en vivo (S=servicio para ver solo uno)
	$(COMPOSE) logs -f --tail=100 $(S)

health: ## Comprueba proxy, app y Grafana a traves del proxy
	@port="$$(grep -E '^PROXY_HTTP_PORT=' .env 2>/dev/null | cut -d= -f2)"; port="$${port:-8080}"; status=0; \
	for path in /healthz /health /grafana/api/health; do \
		code="$$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$$port$$path")"; \
		if [ "$$code" = "200" ]; then result="OK"; else result="FALLO ($$code)"; status=1; fi; \
		printf '  %-22s %s\n' "$$path" "$$result"; \
	done; \
	exit $$status

lint: ## Valida compose, scripts, Prometheus y el dashboard de Grafana
	@echo "==> docker compose config"
	@$(COMPOSE_LINT) config --quiet
	@echo "==> shellcheck"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck scripts/*.sh; \
	else \
		docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt $(SHELLCHECK_IMAGE) scripts/*.sh; \
	fi
	@echo "==> promtool check config (incluye las reglas de alerta)"
	@prom_image="$$($(COMPOSE_LINT) config --images | grep '^prom/prometheus:')"; \
	docker run --rm -v "$(CURDIR)/monitoring/prometheus:/etc/prometheus:ro" \
		--entrypoint promtool "$$prom_image" check config /etc/prometheus/prometheus.yml
	@echo "==> JSON del dashboard"
	@python3 -m json.tool $(DASHBOARD) > /dev/null
	@echo "lint OK"

scan: ## Escanea con Trivy vulnerabilidades, configuracion y secretos
	./scripts/security-scan.sh

backup: ## Backup de PostgreSQL con rotacion (KEEP=N backups a conservar)
	./scripts/backup.sh -k $(KEEP)

restore: ## Restaura un backup (FILE=ruta o latest; YES=1 sin confirmacion)
	./scripts/restore.sh $(if $(YES),-y) $(FILE)

clean: ## Para el stack y BORRA todos los datos (pide confirmacion)
	@read -r -p "Se borraran la base de datos, las metricas y Grafana. Escribe 'si' para continuar: " answer; \
	[ "$$answer" = "si" ] || { echo "Cancelado"; exit 1; }
	$(COMPOSE) down --volumes --remove-orphans
