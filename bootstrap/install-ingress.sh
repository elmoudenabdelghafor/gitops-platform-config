#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/traefik-values.yaml"

echo "==> [Task 1.4] Adding and updating Traefik Helm repository..."
helm repo add traefik https://traefik.github.io/charts --force-update
helm repo update traefik

echo "==> Deploying Traefik Ingress Controller via Helm..."
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  -f "${VALUES_FILE}"

echo "==> Waiting for Traefik deployment rollout..."
kubectl -n traefik rollout status deployment/traefik --timeout=180s

echo "==> Traefik Ingress deployed successfully. Verifying service..."
kubectl get svc -n traefik
