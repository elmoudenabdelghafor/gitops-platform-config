#!/usr/bin/env bash
set -euo pipefail

echo "==> [Task 1.3] Deploying Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

echo "==> Patching Metrics Server with --kubelet-insecure-tls for Kind..."
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

echo "==> Waiting for Metrics Server deployment rollout..."
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s

echo "==> Metrics Server deployed successfully."
