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

This stage is dev-focused (no Ingress/TLS in the chart yet).

### Install (dev)

```bash
make helm-deploy-dev
```

Print local URLs (starts a background port-forward and verifies `/health`):

```bash
make helm-urls-dev
```

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
