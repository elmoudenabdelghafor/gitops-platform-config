CLUSTER_NAME ?= platform
BOOTSTRAP_DIR := bootstrap

.PHONY: all up down status test preflight

all: up

preflight:
	@echo "==> Verifying pre-flight tools..."
	@docker info >/dev/null 2>&1 || (echo "ERROR: Docker daemon is not running." && exit 1)
	@command -v kind >/dev/null 2>&1 || (echo "ERROR: kind is not installed." && exit 1)
	@command -v kubectl >/dev/null 2>&1 || (echo "ERROR: kubectl is not installed." && exit 1)
	@command -v helm >/dev/null 2>&1 || (echo "ERROR: helm is not installed." && exit 1)
	@echo "==> Pre-flight check passed."

up: preflight
	@echo "==> Provisioning Kind cluster '$(CLUSTER_NAME)'..."
	@kind get clusters | grep -q "^$(CLUSTER_NAME)$$" || kind create cluster --config $(BOOTSTRAP_DIR)/kind.yaml --name $(CLUSTER_NAME)
	@kubectl config use-context kind-$(CLUSTER_NAME)
	@echo "==> Installing Calico CNI..."
	@bash $(BOOTSTRAP_DIR)/install-cni.sh
	@echo "==> Installing Metrics Server..."
	@bash $(BOOTSTRAP_DIR)/install-metrics.sh
	@echo "==> Installing Traefik Ingress..."
	@bash $(BOOTSTRAP_DIR)/install-ingress.sh
	@echo "==> Cluster setup complete!"
	@$(MAKE) status

down:
	@echo "==> Deleting Kind cluster '$(CLUSTER_NAME)'..."
	@kind delete cluster --name $(CLUSTER_NAME)

status:
	@echo "==> Nodes:"
	@kubectl get nodes -o wide
	@echo ""
	@echo "==> Ingress Service:"
	@kubectl get svc -n traefik
	@echo ""
	@echo "==> Pods across namespaces:"
	@kubectl get pods -A
	@echo ""
	@echo "==> Resource usage (metrics-server):"
	@kubectl top nodes || echo "(Metrics server collecting initial data...)"

test:
	@echo "==> Running Phase 1 Acceptance Verification..."
	@kubectl get nodes
	@kubectl get nodes -l ingress-ready=true
	@kubectl get pods -n kube-system -l k8s-app=calico-node
	@kubectl get svc -n traefik
	@echo "==> Testing http://localhost endpoint (Expect 404):"
	@curl -I -s http://localhost || true
