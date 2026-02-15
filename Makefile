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

# Environment: prod
PROD_RELEASE ?= $(RELEASE)-prod
PROD_NAMESPACE ?= prod
PROD_VALUES ?= -f $(CHART)/values-prod.yml

.PHONY: help docker-build docker-run docker-run-bg docker-logs docker-stop curl-health \
		helm-lint \
	helm-deploy-dev helm-cleanup-dev \
	helm-deploy-prod helm-cleanup-prod \
	helm-urls-dev \
	release-tag \
	release-prod \
	traefik-install traefik-uninstall \



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
	"  helm-deploy-prod  Install/upgrade prod (atomic) using values-prod.yml + HELM_VALUES (optional)" \
	"  helm-cleanup-prod Uninstall prod release" \
	"  helm-urls-dev     Start port-forward (background) and print localhost URLs" \
	"" \
	"  release-tag      Create and push a release tag (TAG=vX.Y.Z)" \
	"  release-prod     Create release/<tag> branch, bump prod values, tag, push (TAG=vX.Y.Z)"
	@printf "%s\n" \
	"" \
	"  traefik-install   Install/upgrade Traefik (namespace: traefik)" \
	"  traefik-uninstall Uninstall Traefik (namespace: traefik)"

docker-build:
	docker build -t $(IMAGE) .

docker-run: docker-build
	@docker rm -f $(CONTAINER) >/dev/null 2>&1 || true
	docker run --name $(CONTAINER) --rm -p $(PORT):$(PORT) \
		-e APP_ENV=local \
		-e APP_IMAGE_TAG=local \
		-e LISTEN_HOST=$(LISTEN_HOST) \
		-e LISTEN_PORT=$(LISTEN_PORT) \
		$(IMAGE)

docker-run-bg: docker-build
	@docker rm -f $(CONTAINER) >/dev/null 2>&1 || true
	docker run --name $(CONTAINER) -d -p $(PORT):$(PORT) \
		-e APP_ENV=local \
		-e APP_IMAGE_TAG=local \
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
	helm upgrade --install --atomic $(DEV_RELEASE) $(CHART) \
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

helm-deploy-prod:
	helm upgrade --install --atomic $(PROD_RELEASE) $(CHART) \
		-n $(PROD_NAMESPACE) --create-namespace \
		$(PROD_VALUES) \
		$(HELM_VALUES)

helm-cleanup-prod:
	@helm uninstall $(PROD_RELEASE) -n $(PROD_NAMESPACE) >/dev/null 2>&1 || true

release-tag:
	@if test -z "$(TAG)"; then echo "TAG is required (example: TAG=v1.2.3)"; exit 1; fi
	@case "$(TAG)" in v*) : ;; *) echo "TAG must start with 'v' (example: v1.2.3)"; exit 1 ;; esac
	git tag -a "$(TAG)" -m "Release $(TAG)"
	git push origin "$(TAG)"

release-prod:
	@if test -z "$(TAG)"; then echo "TAG is required (example: TAG=v1.2.3)"; exit 1; fi
	@case "$(TAG)" in v*) : ;; *) echo "TAG must start with 'v' (example: v1.2.3)"; exit 1 ;; esac
	@if ! git diff --quiet || ! git diff --cached --quiet; then echo "working tree must be clean"; exit 1; fi
	@set -euo pipefail; \
	branch="release/$(TAG)"; \
	prod_file="charts/helm-rest-api/values-prod.yml"; \
	chart_file="charts/helm-rest-api/Chart.yaml"; \
	version="$${TAG#v}"; \
	test -f "$$prod_file"; \
	test -f "$$chart_file"; \
	git checkout -b "$$branch"; \
	sed -i.bak -E "s/^[[:space:]]{2}tag:.*/  tag: $(TAG)/" "$$prod_file"; \
	rm -f "$$prod_file.bak"; \
	sed -i.bak -E "s/^version:.*/version: $${version}/" "$$chart_file"; \
	rm -f "$$chart_file.bak"; \
	sed -i.bak -E "s/^appVersion:.*/appVersion: \\\"$${version}\\\"/" "$$chart_file"; \
	rm -f "$$chart_file.bak"; \
	git add "$$prod_file" "$$chart_file"; \
	if git diff --cached --quiet; then echo "no changes staged (did not update values)"; exit 1; fi; \
	git commit -m "chore(release): $(TAG)"; \
	git tag -a "$(TAG)" -m "Release $(TAG)"; \
	git push -u origin "$$branch"; \
	git push origin "$(TAG)"

TRAEFIK_NS ?= traefik
TRAEFIK_RELEASE ?= traefik
TRAEFIK_VALUES ?= -f ./tools/traefik-values.yaml

traefik-install:
	helm repo add traefik https://traefik.github.io/charts
	helm repo update
	helm upgrade --install --atomic $(TRAEFIK_RELEASE) traefik/traefik \
		-n $(TRAEFIK_NS) --create-namespace \
		$(TRAEFIK_VALUES)

traefik-uninstall:
	@helm uninstall $(TRAEFIK_RELEASE) -n $(TRAEFIK_NS) >/dev/null 2>&1 || true
