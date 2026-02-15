# helm-rest-api

[![CI](https://github.com/ahmedbadawy4/helm-rest-api/actions/workflows/pr-checks.yml/badge.svg)](https://github.com/ahmedbadawy4/helm-rest-api/actions/workflows/pr-checks.yml)

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

### Install (prod)

`charts/helm-rest-api/values-prod.yml` is an example production overlay. It is intended to be customized with:

- a real company domain hostname
- a real TLS secret name
- an immutable image tag (`vX.Y.Z` or `sha-<gitsha>`)

```bash
make helm-deploy-prod
```

Release flow:

- Pushes to `main` publish `ghcr.io/<owner>/<repo>:main`.
- Pushing a release tag `vX.Y.Z` publishes `ghcr.io/<owner>/<repo>:vX.Y.Z`.

Recommended release (release branch between `main` and the tag):

```bash
make release-prod TAG=v1.2.3
```

This creates `release/v1.2.3`, bumps `charts/helm-rest-api/values-prod.yml` to `v1.2.3`, creates the `v1.2.3` tag on that commit, and pushes both branch and tag.

Optionally open a PR to merge `release/v1.2.3` back into `main` to keep `main` aligned with the latest production release.

The API `GET /` response includes both the environment name and the image tag (`APP_ENV` + `APP_IMAGE_TAG`).

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

### Network Policy

An optional `NetworkPolicy` is available. When enabled, it restricts ingress to the application Pods to only the namespaces listed in `networkPolicy.allowIngressFromNamespaces` (e.g., `traefik` and `monitoring`) and allows DNS egress if `networkPolicy.allowEgressDNS=true`.

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

### Traffic Control (Traefik Middlewares)

For "Istio-like" traffic controls at the edge (without a full service mesh), the chart can create Traefik `Middleware` resources (rate limiting, retries, and security headers) and attach them to the Ingress via annotations.

Enable in values:

```yaml
traefik:
  middlewares:
    enabled: true
```

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
