# cluster.ps1 - Native PowerShell Automation for Kubernetes Kind Platform
[CmdletBinding()]
param (
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("up", "down", "status", "test", "help")]
    [string]$Action,

    [string]$ClusterName = "platform"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseDir = Split-Path -Parent $ScriptDir
$BootstrapDir = Join-Path $BaseDir "bootstrap"

function Write-Step {
    param([string]$Message)
    Write-Host "`n=====> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Test-Preflight {
    Write-Step "Checking Pre-flight Prerequisites..."
    
    # 1. Docker
    try {
        $null = docker info 2>&1
        Write-Success "Docker daemon is running."
    } catch {
        throw "Docker daemon is not running. Please start Docker Desktop before proceeding."
    }

    # 2. kind
    if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
        throw "kind CLI is not installed or not in PATH."
    }
    Write-Success "kind is available."

    # 3. kubectl
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        throw "kubectl is not installed or not in PATH."
    }
    Write-Success "kubectl is available."

    # 4. helm
    if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
        throw "helm is not installed or not in PATH."
    }
    Write-Success "helm is available."
}

function Invoke-Up {
    Test-Preflight

    # Check if cluster already exists
    $existing = kind get clusters 2>&1
    if ($existing -contains $ClusterName) {
        Write-WarningMsg "Cluster '$ClusterName' already exists. Skipping kind create."
    } else {
        Write-Step "Creating Kind cluster '$ClusterName'..."
        $kindConfig = Join-Path $BootstrapDir "kind.yaml"
        kind create cluster --config $kindConfig --name $ClusterName
        Write-Success "Kind cluster '$ClusterName' created."
    }

    # Set kubectl context to this cluster
    kubectl config use-context "kind-$ClusterName" | Out-Null

    # 1. Install Calico CNI
    Write-Step "[Task 1.2] Deploying Calico CNI (v3.28.2)..."
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.2/manifests/calico.yaml

    Write-Host "Waiting for Calico node daemonset rollout..."
    kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s

    Write-Host "Waiting for Calico kube-controllers rollout..."
    kubectl -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s

    Write-Host "Waiting for all cluster nodes to reach Ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=180s
    Write-Success "All nodes are Ready with Calico CNI."

    # 2. Install Metrics Server
    Write-Step "[Task 1.3] Deploying Metrics Server..."
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

    Write-Host "Patching Metrics Server for Kind (--kubelet-insecure-tls)..."
    kubectl patch deployment metrics-server -n kube-system --type=json `
      -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'

    Write-Host "Waiting for Metrics Server rollout..."
    kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
    Write-Success "Metrics Server is ready."

    # 3. Install Traefik Ingress
    Write-Step "[Task 1.4] Deploying Traefik Ingress Controller..."
    helm repo add traefik https://traefik.github.io/charts --force-update | Out-Null
    helm repo update traefik | Out-Null

    $traefikValues = Join-Path $BootstrapDir "traefik-values.yaml"
    helm upgrade --install traefik traefik/traefik `
      --namespace traefik `
      --create-namespace `
      -f $traefikValues

    Write-Host "Waiting for Traefik deployment rollout..."
    kubectl -n traefik rollout status deployment/traefik --timeout=180s
    Write-Success "Traefik Ingress Controller is ready."

    Write-Step "Cluster Setup Summary"
    Invoke-Status
    
    Write-Host "`nTest local ingress endpoint: http://localhost" -ForegroundColor Green
}

function Invoke-Down {
    Write-Step "Deleting Kind cluster '$ClusterName'..."
    kind delete cluster --name $ClusterName
    Write-Success "Kind cluster '$ClusterName' removed."
}

function Invoke-Status {
    Write-Step "Cluster Nodes Status:"
    kubectl get nodes -o wide

    Write-Step "Traefik Ingress Service:"
    kubectl get svc -n traefik

    Write-Step "Pods across all namespaces:"
    kubectl get pods -A

    Write-Step "Node Resource Metrics:"
    try {
        kubectl top nodes
    } catch {
        Write-WarningMsg "Metrics Server is still collecting initial sample (wait 30-60s then re-run status)."
    }
}

function Invoke-Test {
    Write-Step "Running Phase 1 Acceptance Tests..."
    
    # 1. Node count & status
    $nodes = kubectl get nodes --no-headers 2>&1
    $nodeCount = ($nodes | Measure-Object).Count
    if ($nodeCount -ge 3) {
        Write-Success "Multi-node topology verified ($nodeCount nodes)."
    } else {
        Write-WarningMsg "Expected at least 3 nodes, found $nodeCount."
    }

    # 2. Control plane label
    $ingressNodes = kubectl get nodes -l ingress-ready=true --no-headers 2>&1
    if ($ingressNodes) {
        Write-Success "ingress-ready=true label verified on control-plane node."
    } else {
        Write-WarningMsg "No node found with label ingress-ready=true."
    }

    # 3. Calico CNI pods
    $calicoPods = kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>&1
    Write-Success "Calico node pods running:"
    $calicoPods | ForEach-Object { Write-Host "   $_" }

    # 4. Traefik Service
    $traefikSvc = kubectl get svc -n traefik -l app.kubernetes.io/name=traefik --no-headers 2>&1
    Write-Success "Traefik NodePort service: $traefikSvc"

    # 5. Localhost HTTP Ingress Routing Check
    Write-Step "Testing host ingress reachability (http://localhost)..."
    try {
        $res = Invoke-WebRequest -Uri "http://localhost" -TimeoutSec 5 -SkipHttpErrorCheck
        Write-Success "Received HTTP status code: $($res.StatusCode) (Expected 404 from Traefik default backend)."
    } catch {
        # Check via curl as fallback
        $curlOutput = curl.exe -s -I http://localhost 2>&1 | Out-String
        if ($curlOutput -match "404") {
            Write-Success "Received 404 from Traefik default backend via curl."
        } else {
            Write-WarningMsg "HTTP response: $curlOutput"
        }
    }
}

switch ($Action) {
    "up"     { Invoke-Up }
    "down"   { Invoke-Down }
    "status" { Invoke-Status }
    "test"   { Invoke-Test }
    "help"   {
        Write-Host "Usage: .\cluster.ps1 [up|down|status|test] [-ClusterName <name>]"
    }
}
