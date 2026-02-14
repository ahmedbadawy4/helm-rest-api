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
helm upgrade --install helm-rest-api-dev ./charts/helm-rest-api \
  -n dev --create-namespace \
  --values ./charts/helm-rest-api/values-dev.yml
```

For quick local access (no ingress), you can port-forward:

```bash
kubectl -n dev port-forward svc/helm-rest-api-dev 8080:80
curl -fsSL http://localhost:8080/health
```

### Container Image (GHCR)

This repo includes a GitHub Action that publishes the image to GitHub Container Registry on pushes to `main`:

Update `charts/helm-rest-api/values.yaml` (or pass `--set image.repository=... --set image.tag=...`) to point to your GHCR image.

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
