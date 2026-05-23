# Local Kind Platform Engineering Demo - Windows Setup
# Runs a local multi-cluster GitOps platform with kind, Sveltos and ArgoCD.

$ErrorActionPreference = "Stop"

function Info($message) {
    Write-Host ""
    Write-Host "==> $message" -ForegroundColor Cyan
}

function Warn($message) {
    Write-Host ""
    Write-Host "WARN: $message" -ForegroundColor Yellow
}

function Require-Command($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required command '$name' was not found. Please install it first."
    }
}

Info "Checking required tools"
Require-Command docker
Require-Command kubectl
Require-Command kind
Require-Command helm
Require-Command git

Info "Creating kubeconfigs directory"
New-Item -ItemType Directory -Force -Path ".\kubeconfigs" | Out-Null

Info "Creating kind clusters if they do not already exist"
$clusters = kind get clusters

if ($clusters -notcontains "mgmt") {
    kind create cluster --config .\clusters\mgmt.yaml
} else {
    Warn "kind cluster 'mgmt' already exists. Skipping."
}

if ($clusters -notcontains "dev") {
    kind create cluster --config .\clusters\dev.yaml
} else {
    Warn "kind cluster 'dev' already exists. Skipping."
}

if ($clusters -notcontains "staging") {
    kind create cluster --config .\clusters\staging.yaml
} else {
    Warn "kind cluster 'staging' already exists. Skipping."
}

Info "Installing Sveltos on mgmt cluster"
kubectl config use-context kind-mgmt

helm repo add projectsveltos https://projectsveltos.github.io/helm-charts | Out-Null
helm repo update

$releaseExists = helm list -n projectsveltos -q | Select-String -Pattern "^projectsveltos$"

if (-not $releaseExists) {
    helm install projectsveltos projectsveltos/projectsveltos `
        -n projectsveltos `
        --create-namespace `
        --version 1.10.0
} else {
    Warn "Sveltos is already installed. Running helm upgrade."
    helm upgrade projectsveltos projectsveltos/projectsveltos `
        -n projectsveltos `
        --version 1.10.0
}

Info "Waiting for Sveltos pods"
kubectl wait --for=condition=Ready pods --all -n projectsveltos --timeout=180s

Info "Labeling mgmt cluster for Sveltos targeting"
kubectl label sveltoscluster mgmt -n mgmt type=mgmt --overwrite

Info "Generating kubeconfigs for dev and staging"
kind get kubeconfig --name dev > .\kubeconfigs\dev-host.yaml
kind get kubeconfig --name staging > .\kubeconfigs\staging-host.yaml

Info "Creating Sveltos-compatible kubeconfigs"
(Get-Content .\kubeconfigs\dev-host.yaml) `
  -replace 'server: https://127\.0\.0\.1:\d+', 'server: https://dev-control-plane:6443' |
  Set-Content .\kubeconfigs\dev-sveltos.yaml

(Get-Content .\kubeconfigs\staging-host.yaml) `
  -replace 'server: https://127\.0\.0\.1:\d+', 'server: https://staging-control-plane:6443' |
  Set-Content .\kubeconfigs\staging-sveltos.yaml

Info "Creating namespaces for managed clusters"
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -

Info "Creating kubeconfig secrets for managed clusters"
kubectl create secret generic dev-sveltos-kubeconfig `
  -n dev `
  --from-file=kubeconfig=.\kubeconfigs\dev-sveltos.yaml `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic staging-sveltos-kubeconfig `
  -n staging `
  --from-file=kubeconfig=.\kubeconfigs\staging-sveltos.yaml `
  --dry-run=client -o yaml | kubectl apply -f -

Info "Registering dev and staging clusters in Sveltos"
kubectl apply -f .\sveltos\mgmt\dev-sveltoscluster.yaml
kubectl apply -f .\sveltos\mgmt\staging-sveltoscluster.yaml

Info "Waiting for SveltosCluster resources to become ready"
kubectl wait --for=jsonpath='{.status.ready}'=true sveltoscluster/dev -n dev --timeout=180s
kubectl wait --for=jsonpath='{.status.ready}'=true sveltoscluster/staging -n staging --timeout=180s

Info "Applying workload ClusterProfiles"
kubectl apply -f .\sveltos\clusters\podinfo-dev.yaml
kubectl apply -f .\sveltos\clusters\podinfo-staging.yaml

Info "Waiting for ArgoCD namespace and pods"
$timeout = (Get-Date).AddMinutes(5)

while ((Get-Date) -lt $timeout) {
    $namespace = kubectl get namespace argocd --ignore-not-found -o name

    if ($namespace -eq "namespace/argocd") {
        break
    }

    Start-Sleep -Seconds 5
}

$namespace = kubectl get namespace argocd --ignore-not-found -o name
if ($namespace -ne "namespace/argocd") {
    throw "ArgoCD namespace was not created within the timeout."
}

kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

Info "Applying ArgoCD Application"
kubectl apply -f .\sveltos\mgmt\argocd-app-sveltos.yaml

Info "Final status"
kubectl get sveltoscluster -A --show-labels
kubectl get clusterprofile
kubectl get clustersummary -A
kubectl get applications -n argocd

Info "Setup completed successfully"
Write-Host ""
Write-Host "Access ArgoCD:" -ForegroundColor Green
Write-Host "kubectl config use-context kind-mgmt"
Write-Host "kubectl port-forward svc/argocd-server -n argocd 8080:443"
Write-Host "Open: https://localhost:8080"
Write-Host ""
Write-Host "Access dev podinfo:" -ForegroundColor Green
Write-Host "kubectl config use-context kind-dev"
Write-Host "kubectl port-forward svc/podinfo 9898:9898 -n podinfo"
Write-Host "Open: http://localhost:9898"
Write-Host ""
Write-Host "Access staging podinfo:" -ForegroundColor Green
Write-Host "kubectl config use-context kind-staging"
Write-Host "kubectl port-forward svc/podinfo 9899:9898 -n podinfo"
Write-Host "Open: http://localhost:9899"
