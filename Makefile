SHELL := /bin/sh

APP_NAME ?= helm-rest-api
IMAGE ?= $(APP_NAME):local
CONTAINER ?= $(APP_NAME)-local
PORT ?= 8080

LISTEN_HOST ?= 0.0.0.0
LISTEN_PORT ?= $(PORT)

.PHONY: help docker-build docker-run docker-run-bg docker-logs docker-stop curl-health \
	

help:
	@printf "%s\n" \
	"Targets:" \
	"  docker-build     Build image ($(IMAGE))" \
	"  docker-run       Run container in foreground on :$(PORT) (Ctrl+C to stop)" \
	"  docker-run-bg    Run container in background on :$(PORT)" \
	"  docker-logs      Tail background container logs" \
	"  docker-stop      Stop background container" \
	"  curl-health      Call http://localhost:$(PORT)/health"

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
