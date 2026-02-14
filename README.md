# helm-rest-api

[![CI](https://github.com/ahmedbadawy4/helm-rest-api/actions/workflows/ci.yml/badge.svg)](https://github.com/ahmedbadawy4/helm-rest-api/actions/workflows/ci.yml)

A Helm chart to deploy a stateless REST API publicly on Kubernetes.

## Local (Docker via Make)

```bash
make docker-run
```

In another terminal:

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

### Autoscaling (HPA)

HPA is available (disabled by default). To enable it, you must set CPU requests.

### Traefik TLS (Ingress)

The chart supports a standard Kubernetes Ingress.

- `ingress.className: traefik`
- `ingress.tls` referencing a secret (`helm-rest-api-tls`)

Traefik can be installed using the repo tools:

```bash
make traefik-install
```

For a quick demo, a self-signed cert secret named `helm-rest-api-tls` in the `dev` namespace can be created.

In real environments, typically use A company-issued certificate for the company domain, stored as a Kubernetes TLS secret, or cert-manager (recommended) to issue/renew certificates automatically.

Traefik can also be configured with a default certificate (fallback). For production, we should still use a valid cert for the real company domain.

### Container Image (GHCR)

This repo includes a GitHub Action that publishes the image to GitHub Container Registry on `push` (not PRs):

Dev defaults are set in `charts/helm-rest-api/values-dev.yml` (repository + tag).
```

**Notes: If the GHCR package is private, create an image pull secret and set it via Helm values:**

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
