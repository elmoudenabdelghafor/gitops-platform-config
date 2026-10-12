# Platform Config (`platform-config`)

[![platform-smoke](https://github.com/OWNER/platform-config/actions/workflows/platform-smoke.yaml/badge.svg)](https://github.com/OWNER/platform-config/actions/workflows/platform-smoke.yaml)

Declarative cluster bootstrap and platform configuration repository for the GitOps & DevSecOps Platform.

## Architecture & Layout

```
platform-config/
├── .github/
│   └── workflows/
│       └── platform-smoke.yaml   # CI smoke test verifying cluster reproducibility
├── bootstrap/
│   ├── kind.yaml                 # 3-node Kind cluster definition + port mappings
│   ├── install-cni.sh            # Calico CNI v3.28.2 bootstrap
│   ├── install-metrics.sh        # Metrics Server deployment & patch
│   ├── traefik-values.yaml       # Traefik Helm values (NodePort 30080/30443)
│   └── install-ingress.sh        # Traefik Ingress Controller bootstrap
├── docs/
│   └── decisions.md              # Architecture Decision Records (ADRs)
├── scripts/
│   └── cluster.ps1               # Native PowerShell automation script
├── Makefile                      # Cross-platform lifecycle entry point
└── .gitattributes                # Enforces LF line endings for shell scripts and YAML
```

## Quick Start

### Windows (PowerShell)
```powershell
# Provision cluster, Calico, Metrics Server, and Traefik
.\scripts\cluster.ps1 -Action up

# Check status across all namespaces
.\scripts\cluster.ps1 -Action status

# Run acceptance tests
.\scripts\cluster.ps1 -Action test

# Teardown
.\scripts\cluster.ps1 -Action down
```

### Linux / macOS / WSL (Make)
```bash
make up
make status
make test
make down
```

## Architecture Decisions
See [Architecture Decision Records](docs/decisions.md) for technical choices regarding Calico CNI, Traefik, NodePorts, and GHCR registry integration.
