#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/argocd-values.yaml"

echo "==> [Task 3.1] Adding and updating Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update argo

echo "==> Deploying Argo CD via Helm..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  -f "${VALUES_FILE}"

echo "==> Waiting for Argo CD core components rollout..."
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo "==> Argo CD successfully deployed!"
echo "==> UI Endpoint: http://argocd.localhost (or curl -H 'Host: argocd.localhost' http://localhost)"

# Retrieve initial admin password
if kubectl -n argocd get secret argocd-initial-admin-secret &>/dev/null; then
  ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  echo "==> Admin Username: admin"
  echo "==> Admin Password: ${ADMIN_PASSWORD}"
fi
