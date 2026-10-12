#!/usr/bin/env bash
set -euo pipefail

echo "==> [Task 1.2] Deploying Calico CNI (v3.28.2)..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/calico.yaml

echo "==> Waiting for Calico node daemonset rollout..."
kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s

echo "==> Waiting for Calico kube-controllers deployment rollout..."
kubectl -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s

echo "==> Waiting for all nodes to reach Ready condition..."
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo "==> Calico CNI deployment verified successfully."
kubectl get nodes -o wide
