SHELL := /bin/sh

APP_NAME ?= helm-rest-api
IMAGE ?= $(APP_NAME):local
CONTAINER ?= $(APP_NAME)-local
PORT ?= 8080

LISTEN_HOST ?= 0.0.0.0
LISTEN_PORT ?= $(PORT)

CHART ?= ./charts/helm-rest-api
RELEASE ?= helm-rest-api
NAMESPACE ?= default
HELM_VALUES ?=

# Environment: dev (non-prod)
DEV_RELEASE ?= $(RELEASE)-dev
DEV_NAMESPACE ?= dev
DEV_VALUES ?= -f $(CHART)/values-dev.yml
DEV_SVC ?= $(DEV_RELEASE)-helm-rest-api
DEV_PF_PID ?= /tmp/$(DEV_RELEASE)-pf.pid
DEV_PF_LOG ?= /tmp/$(DEV_RELEASE)-pf.log

.PHONY: help docker-build docker-run docker-run-bg docker-logs docker-stop curl-health \
	helm-lint helm-template \
	helm-deploy-dev helm-cleanup-dev \
	helm-urls-dev

help:
	@printf "%s\n" \
	"Targets:" \
	"  docker-build     Build image ($(IMAGE))" \
	"  docker-run       Run container in foreground on :$(PORT) (Ctrl+C to stop)" \
	"  docker-run-bg    Run container in background on :$(PORT)" \
	"  docker-logs      Tail background container logs" \
	"  docker-stop      Stop background container" \
	"  curl-health      Call http://localhost:$(PORT)/health" \
	"" \
	"  helm-lint         Helm lint $(CHART)" \
	"" \
	"  helm-deploy-dev   Install/upgrade dev (atomic) using values-dev.yml + HELM_VALUES (optional)" \
	"  helm-cleanup-dev  Uninstall dev release and stop background port-forward" \
	"  helm-urls-dev     Start port-forward (background) and print localhost URLs"

docker-build:
	docker build -t $(IMAGE) .

docker-run: docker-build
	@docker rm -f $(CONTAINER) >/dev/null 2>&1 || true
	docker run --name $(CONTAINER) --rm -p $(PORT):$(PORT) \
		-e LISTEN_HOST=$(LISTEN_HOST) \
		-e LISTEN_PORT=$(LISTEN_PORT) \
		$(IMAGE)

docker-run-bg: docker-build
	@docker rm -f $(CONTAINER) >/dev/null 2>&1 || true
	docker run --name $(CONTAINER) -d -p $(PORT):$(PORT) \
		-e LISTEN_HOST=$(LISTEN_HOST) \
		-e LISTEN_PORT=$(LISTEN_PORT) \
		$(IMAGE) >/dev/null
	@printf "Container '%s' running. Try: make curl-health\n" "$(CONTAINER)"

docker-logs:
	docker logs -f $(CONTAINER)

docker-stop:
	@docker rm -f $(CONTAINER) >/dev/null 2>&1 || true

curl-health:
	curl -fsSL http://localhost:$(PORT)/health
	@printf "\n"

helm-lint:
	helm lint $(CHART)

helm-deploy-dev:
	helm upgrade --install $(DEV_RELEASE) $(CHART) \
		-n $(DEV_NAMESPACE) --create-namespace \
		$(DEV_VALUES) \
		$(HELM_VALUES)

helm-urls-dev:
	@set -e; \
	if test -f "$(DEV_PF_PID)" && kill -0 "$$(cat "$(DEV_PF_PID)")" >/dev/null 2>&1; then \
		:; \
		else \
			rm -f "$(DEV_PF_PID)" "$(DEV_PF_LOG)"; \
			( kubectl -n "$(DEV_NAMESPACE)" port-forward "svc/$(DEV_SVC)" "$(PORT):80" >"$(DEV_PF_LOG)" 2>&1 & echo $$! > "$(DEV_PF_PID)" ); \
			sleep 1; \
			if ! kill -0 "$$(cat "$(DEV_PF_PID)")" >/dev/null 2>&1; then \
				svc_name="$$(kubectl -n "$(DEV_NAMESPACE)" get svc -l "app.kubernetes.io/instance=$(DEV_RELEASE)" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"; \
				if test -n "$$svc_name"; then \
					rm -f "$(DEV_PF_PID)" "$(DEV_PF_LOG)"; \
				( kubectl -n "$(DEV_NAMESPACE)" port-forward "svc/$$svc_name" "$(PORT):80" >"$(DEV_PF_LOG)" 2>&1 & echo $$! > "$(DEV_PF_PID)" ); \
				sleep 1; \
			fi; \
		fi; \
	fi; \
	for i in 1 2 3 4 5 6 7 8 9 10; do \
		if curl -fsS "http://localhost:$(PORT)/health" >/dev/null 2>&1; then break; fi; \
		sleep 0.5; \
	done; \
	if ! curl -fsS "http://localhost:$(PORT)/health" >/dev/null 2>&1; then \
		printf "%s\n" "Port-forward failed. Recent log:"; \
		test -f "$(DEV_PF_LOG)" && tail -n 50 "$(DEV_PF_LOG)" || true; \
		exit 1; \
	fi
	@printf "%s\n" \
	"Local URLs (dev):" \
	"  http://localhost:$(PORT)/" \
	"  http://localhost:$(PORT)/health"

helm-cleanup-dev:
	@helm uninstall $(DEV_RELEASE) -n $(DEV_NAMESPACE) >/dev/null 2>&1 || true
	@if test -f $(DEV_PF_PID); then kill $$(cat $(DEV_PF_PID)) >/dev/null 2>&1 || true; fi
	@rm -f $(DEV_PF_PID) $(DEV_PF_LOG)
