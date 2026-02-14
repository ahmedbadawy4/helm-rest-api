# helm-rest-api

[![CI](https://github.com/ahmedbadawy4/helm-rest-api/actions/workflows/ci.yml/badge.svg)](https://github.com/ahmedbadawy4/helm-rest-api/actions/workflows/ci.yml)

A Helm chart to deploy a stateless REST API publicly on Kubernetes.

## Local (Docker via Make)

```bash
make docker-run
```

In a second terminal:

```bash
make curl-health
```

Background run:

```bash
make docker-run-bg
make curl-health
make docker-logs
make docker-stop
```

## Helm (Kubernetes)

The application exposes `GET /health` and expects:

- `LISTEN_HOST` (defaults to `0.0.0.0` in the chart)
- `LISTEN_PORT` (wired to the container port in the chart)

### Install (dev)

```bash
make helm-deploy-dev
```

Print local URLs (starts a background port-forward and verifies `/health`):

```bash
make helm-urls-dev
```

### Metrics (Prometheus)

The app exposes Prometheus metrics on `GET /metrics`.

Quick check (with port-forward running):

```bash
curl -fsSL http://localhost:8080/metrics | head
```

If Prometheus Operator is used, a `ServiceMonitor` can be enabled:

```bash
HELM_VALUES="--set monitoring.serviceMonitor.enabled=true" make helm-deploy-dev
```
*`ServiceMonitor` is a Prometheus Operator custom resource. When enabled, it instructs Prometheus Operator to discover the chart Service by labels and scrape `GET /metrics` on the `http` port at the configured interval/timeout. If Prometheus Operator (and the `ServiceMonitor` CRD) is not installed in the cluster, this resource will not be used (and may be rejected by the API server).*

### Autoscaling (HPA)

HPA is available (disabled by default). Enabling it requires CPU requests.

### Traefik TLS (Ingress)

The chart supports a standard Kubernetes Ingress.

- `ingress.className: traefik`
- `ingress.tls` referencing a secret (`helm-rest-api-tls`)

Traefik installation (Helm):

```bash
make traefik-install
```

For local demos, a self-signed TLS secret named `helm-rest-api-tls` can be created in the `dev` namespace.

In real environments, a company-issued certificate can be stored as a Kubernetes TLS secret, or cert-manager (recommended) can be used to issue/renew certificates automatically.

Traefik can also be configured with a default certificate (fallback). For production usage, a valid certificate for the company domain should be used.

### Container Image (GHCR)

This repository includes a GitHub Action that publishes the image to GitHub Container Registry on `push` (not PRs).

Dev defaults are set in `charts/helm-rest-api/values-dev.yml` (repository + tag).

If the GHCR package is private, create an image pull secret and reference it via Helm values:

```bash
kubectl -n dev create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-pat-with-read:packages> \
  --docker-email=<email>
```

Then set:

```yaml
imagePullSecrets:
  - name: ghcr-pull
```

### Security Defaults

The chart sets secure defaults for the pod/container (non-root, seccomp `RuntimeDefault`, drop all caps, `readOnlyRootFilesystem`). The container mounts an `emptyDir` at `/tmp` to support read-only root filesystems.

### Monitoring And Alerting (Design)

The app exposes `/health` for probes. For production monitoring/alerting, a typical setup is:

- Prometheus scraping (via ServiceMonitor or annotations) for application metrics (if exposed) and Kubernetes metrics
- Grafana dashboards for latency, error rate, saturation, and pod health
- Alert rules on:
  - elevated 5xx/error rate
  - high latency (p95/p99)
  - HPA at max replicas for sustained periods
  - frequent restarts / CrashLoopBackOff

### Security Measures (Design)

- Run as non-root user, drop Linux capabilities, seccomp RuntimeDefault
- Read-only root filesystem with writable `/tmp`
- Image scanning (Trivy) and Dockerfile linting (Hadolint) in CI
