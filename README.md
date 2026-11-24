# helm-rest-api

[![CI](https://github.com/ahmedbadawy4/helm-rest-api/actions/workflows/pr-checks.yml/badge.svg)](https://github.com/ahmedbadawy4/helm-rest-api/actions/workflows/pr-checks.yml)

A Helm chart to deploy a stateless REST API publicly on Kubernetes. This is a reference setup: a small FastAPI service, a chart with dev and prod values, and GitHub Actions that lint, scan and publish the image. See [Limits](#limits) for what it leaves to the environment.

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

The application exposes `GET /` (environment and image tag), `GET /health` and `GET /metrics`, and expects:

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

This creates `release/v1.2.3`, sets `image.tag` in `charts/helm-rest-api/values-prod.yml` to `v1.2.3`, sets `version` and `appVersion` in `charts/helm-rest-api/Chart.yaml` to `1.2.3`, creates the `v1.2.3` tag on that commit, and pushes both branch and tag. The tag push runs the release workflow, which builds and publishes the image. It does not deploy: run `make helm-deploy-prod` against the cluster afterwards.

Optionally open a PR to merge `release/v1.2.3` back into `main` to keep `main` aligned with the latest production release.

The API `GET /` response includes both the environment name and the image tag (`environment` and `image_tag`, taken from `APP_ENV` and `APP_IMAGE_TAG`).

Print local URLs (starts a background port-forward and verifies `/health`):

```bash
make helm-urls-dev
```

### Metrics (Prometheus)

The app exposes Prometheus metrics on `GET /metrics`. They are the default process and Python runtime metrics from `prometheus_client`; the app does not add request counters.

Quick check (with port-forward running):

```bash
curl -fsSL http://localhost:8080/metrics | head
```

The dev and prod values enable a `ServiceMonitor`. kube-prometheus-stack only selects `ServiceMonitor` resources that carry the label `release: <its Helm release name>`, so pass that label with the release name of the stack (`monitoring` here):

```bash
HELM_VALUES="--set monitoring.serviceMonitor.additionalLabels.release=monitoring" make helm-deploy-dev
```
*`ServiceMonitor` is a Prometheus Operator custom resource. When enabled, it instructs Prometheus Operator to discover the chart Service by labels and scrape `GET /metrics` on the `http` port at the configured interval/timeout. If Prometheus Operator (and the `ServiceMonitor` CRD) is not installed in the cluster, the API server rejects the resource and the install fails.*

### Network Policy

An optional `NetworkPolicy` is available. When enabled, it restricts ingress to the application Pods to only the namespaces listed in `networkPolicy.allowIngressFromNamespaces` (e.g., `traefik` and `monitoring`) and allows DNS egress if `networkPolicy.allowEgressDNS=true`. Namespaces are matched by the `kubernetes.io/metadata.name` label, ingress is limited to the container port, and all other egress is blocked.

### Autoscaling (HPA)

HPA is available (disabled by default; the dev and prod values enable it). Enabling it requires CPU requests. When it is enabled the chart leaves `replicas` out of the Deployment, so a `helm upgrade` does not reset the replica count the HPA chose.

### Traefik TLS (Ingress)

The chart supports a standard Kubernetes Ingress.

- `ingress.className: traefik`
- `ingress.tls` referencing a secret (`helm-rest-api-tls`)

Traefik installation (Helm):

```bash
make traefik-install
```

For local demos, a self-signed TLS secret named `helm-rest-api-tls` can be created in the `dev` namespace (the namespace is created first so the secret can go in before the install):

```bash
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
  -keyout /tmp/helm-rest-api-tls.key -out /tmp/helm-rest-api-tls.crt \
  -subj "/CN=api.dev.company.example" \
  -addext "subjectAltName=DNS:api.dev.company.example"
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl -n dev create secret tls helm-rest-api-tls \
  --cert=/tmp/helm-rest-api-tls.crt --key=/tmp/helm-rest-api-tls.key
```

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

This repository includes GitHub Actions that publish the image (`linux/amd64` and `linux/arm64`) to GitHub Container Registry on `push` to `main` and on release tags (not PRs).

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

The app exposes `/health` for probes and `/metrics` for Prometheus. For production monitoring/alerting, a typical setup is:

- Prometheus scraping (via the chart's ServiceMonitor) for the app's runtime metrics, plus Kubernetes metrics and the ingress controller's request metrics
- Grafana dashboards for latency, error rate, saturation, and pod health
- Alert rules on:
  - elevated 5xx/error rate
  - high latency (p95/p99)
  - HPA at max replicas for sustained periods
  - frequent restarts / CrashLoopBackOff

### Security Measures (Design)

- Run as non-root user, drop Linux capabilities, seccomp RuntimeDefault
- Read-only root filesystem with writable `/tmp`
- Filesystem and image scanning (Trivy), Dockerfile linting (Hadolint), and chart checks (Helm lint, Kubeconform) on every pull request

## Limits

This is a reference setup, not a finished platform. What it leaves to the environment:

- **Placeholders:** the hosts `api.dev.company.example` and `api.prod.company.example` and the TLS secret names are examples. Real DNS names and certificates go into the values files.
- **CRDs first:** the dev and prod values enable the `ServiceMonitor` and the Traefik `Middleware` resources, so the Prometheus Operator and Traefik CRDs must exist before the install. Without them, add `HELM_VALUES="--set monitoring.serviceMonitor.enabled=false --set traefik.middlewares.enabled=false"`.
- **Metrics:** the `ServiceMonitor` needs the label of the Prometheus stack (see Metrics). The app exports runtime metrics only, so error-rate and latency alerts need request metrics from the ingress controller.
- **Release:** a tag push builds and publishes the image. It does not deploy, and it does not change `main`. The `production` environment used by the release workflow has no required reviewers.
- **Image access:** the GHCR package has to be public, or the cluster needs the pull secret shown above.
- **Traefik:** `tools/traefik-values.yaml` uses a `LoadBalancer` Service, and `--atomic` waits for an external address. On a local cluster without a load balancer, install with `make traefik-install TRAEFIK_VALUES="-f ./tools/traefik-values.yaml --set service.type=NodePort"`. The Traefik chart is not pinned unless `TRAEFIK_CHART_VERSION` is set.
- **NetworkPolicy:** it only has an effect on a cluster whose network plugin enforces it.
