CLUSTER_NAME ?= platform
BOOTSTRAP_DIR := bootstrap

.PHONY: all up down status test argocd preflight

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
	@echo "==> Installing Argo CD..."
	@bash $(BOOTSTRAP_DIR)/install-argocd.sh
	@echo "==> Cluster setup complete!"
	@$(MAKE) status

down:
	@echo "==> Deleting Kind cluster '$(CLUSTER_NAME)'..."
	@kind delete cluster --name $(CLUSTER_NAME)

status:
	@echo "==> Nodes:"
	@kubectl get nodes -o wide
	@echo ""
	@echo "==> Ingress Service & Ingresses:"
	@kubectl get svc -n traefik
	@kubectl get ingress -A
	@echo ""
	@echo "==> Pods across namespaces:"
	@kubectl get pods -A
	@echo ""
	@echo "==> Resource usage (metrics-server):"
	@kubectl top nodes || echo "(Metrics server collecting initial data...)"

argocd:
	@echo "==> Argo CD UI: http://argocd.localhost"
	@echo "==> Admin User: admin"
	@echo -n "==> Password:   "
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
	@echo ""

test:
	@echo "==> Running Acceptance Verification..."
	@kubectl get nodes
	@kubectl get nodes -l ingress-ready=true
	@kubectl get pods -n kube-system -l k8s-app=calico-node
	@kubectl get pods -n argocd
	@kubectl get svc -n traefik
	@$(MAKE) argocd
