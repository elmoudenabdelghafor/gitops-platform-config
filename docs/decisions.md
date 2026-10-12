# Architecture Decision Records (ADRs)

## ADR 001: Selection of Calico CNI over Kindnet

### Status
Accepted

### Context
`kind` clusters default to using `kindnet`, a lightweight CNI providing simple pod-to-pod networking and host-local IPAM. However, kindnet has significant limitations:
- No native support for Kubernetes `NetworkPolicy` enforcement.
- Limited IPAM customization and network observability.

Phase 5 of this project specifically targets DevSecOps and network security, requiring granular micro-segmentation and egress/ingress policy enforcement.

### Decision
We disabled default kindnet (`disableDefaultCNI: true`) and deployed **Project Calico CNI** (v3.28.2).
- Pod CIDR is configured to `192.168.0.0/16` across kind and Calico IP pool configuration.
- Calico provides full Kubernetes NetworkPolicy compliance and advanced GlobalNetworkPolicies.

### Consequences
- **Positive:** Full zero-trust network policy enforcement capability for Phase 5.
- **Trade-off:** Initial cluster provisioning takes slightly longer as nodes transition to `Ready` only after the Calico daemonset is deployed.

---

## ADR 002: Traefik Ingress Controller over Ingress-NGINX

### Status
Accepted

### Context
`ingress-nginx` has historically been the default ingress controller for Kubernetes. However:
- The Kubernetes community is shifting toward Gateway API and modern ingress controllers.
- `ingress-nginx` maintenance status and vulnerability exposure have pushed teams toward alternatives.
- Traefik provides native CRDs (IngressRoute), dynamic configuration, built-in Let's Encrypt / TLS management, and first-class Gateway API support.

### Decision
Deploy **Traefik** as the cluster's ingress controller via its official Helm chart.

### Consequences
- **Positive:** Modern architecture, active maintenance, future-proof Gateway API support, rich observability.
- **Trade-off:** Requires specific Helm chart configuration for NodePort bindings on Kind.

---

## ADR 003: NodePort Host Port-Forwarding over MetalLB

### Status
Accepted

### Context
For local Kubernetes clusters running in Docker Desktop (especially on Windows WSL2), exposing LoadBalancer services typically requires either:
1. Running MetalLB with ARP/Layer 2 mode and IP address pools allocated from Docker's network subnet.
2. Direct port-mapping via Kind's `extraPortMappings` on the control-plane container to bind host ports `80` and `443` to specific NodePorts.

MetalLB on Windows WSL2 Docker Desktop can suffer from routing limitations, Docker network resets, and IP conflict issues.

### Decision
Use **Kind `extraPortMappings`** to bind host ports `80` and `443` directly to NodePorts `30080` (HTTP) and `30443` (HTTPS) on the control-plane node, paired with Traefik NodePort service configuration.

### Consequences
- **Positive:** Zero additional networking daemonsets; robust across Docker Desktop restarts on Windows; direct access via `http://localhost` and `https://localhost`.
- **Trade-off:** Ingress controller must run on the control-plane node (enforced via `nodeSelector: ingress-ready: "true"` and control-plane tolerations).

---

## ADR 004: GHCR Image Pull Strategy

### Status
Accepted

### Context
GitHub Container Registry (GHCR) packages are private by default. When Kind attempts to schedule pods with private GHCR images, kubelet fails with `ImagePullBackOff` unless `imagePullSecrets` or Docker daemon credentials are provided in every target namespace.

### Decision
1. **Phases 2 through 4:** Set GHCR package visibility for `shop-api` and `shop-frontend` to **Public** in GitHub Package Settings. This unblocks seamless onboarding with zero credential drift.
2. **Phase 5 (DevSecOps):** Switch packages to Private and introduce an automated, encrypted `imagePullSecret` using **Sealed Secrets** with a scoped `read:packages` personal access token.

### Consequences
- **Positive:** Frictionless initial GitOps onboarding without managing ad-hoc registry credentials.
- **Trade-off:** Images are publicly readable until Phase 5.

---

## ADR 005: Config Repository Visibility & Access

### Status
Accepted

### Context
Argo CD requires continuous access to `platform-config` to synchronize cluster state.
- A public configuration repository allows Argo CD to pull manifests without credentials.
- A private repository requires credential registration in Argo CD.

### Decision
Support **Public** visibility for `platform-config` for local development, while enforcing strict exclusion of all plaintext secrets. When operating in **Private** mode, authenticate Argo CD using a dedicated **Read-Only Deploy Key (SSH)** or fine-grained PAT stored as a Sealed Secret with label `argocd.argoproj.io/secret-type: repository`.

### Consequences
- **Positive:** GitOps principles preserved; zero secrets stored in plaintext.
- **Security:** CI token (`CONFIG_REPO_TOKEN`) is strictly scoped as a fine-grained PAT with Contents Write permission limited only to `platform-config`.
