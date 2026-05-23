#!/usr/bin/env bash
set -euo pipefail

info() {
  echo ""
  echo "==> $1"
}

warn() {
  echo ""
  echo "WARN: $1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' was not found. Please install it first."
    exit 1
  fi
}

info "Checking required tools"
require_command docker
require_command kubectl
require_command kind
require_command helm
require_command git

info "Creating kubeconfigs directory"
mkdir -p kubeconfigs

info "Creating kind clusters if they do not already exist"
existing_clusters="$(kind get clusters || true)"

if ! echo "$existing_clusters" | grep -qx "mgmt"; then
  kind create cluster --config ./clusters/mgmt.yaml
else
  warn "kind cluster 'mgmt' already exists. Skipping."
fi

if ! echo "$existing_clusters" | grep -qx "dev"; then
  kind create cluster --config ./clusters/dev.yaml
else
  warn "kind cluster 'dev' already exists. Skipping."
fi

if ! echo "$existing_clusters" | grep -qx "staging"; then
  kind create cluster --config ./clusters/staging.yaml
else
  warn "kind cluster 'staging' already exists. Skipping."
fi

info "Installing Sveltos on mgmt cluster"
kubectl config use-context kind-mgmt

helm repo add projectsveltos https://projectsveltos.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update

if helm status projectsveltos -n projectsveltos >/dev/null 2>&1; then
  warn "Sveltos is already installed. Running helm upgrade."
  helm upgrade projectsveltos projectsveltos/projectsveltos \
    -n projectsveltos \
    --version 1.10.0
else
  helm install projectsveltos projectsveltos/projectsveltos \
    -n projectsveltos \
    --create-namespace \
    --version 1.10.0
fi

info "Waiting for Sveltos pods"
kubectl wait --for=condition=Ready pods --all -n projectsveltos --timeout=180s

info "Labeling mgmt cluster for Sveltos targeting"
kubectl label sveltoscluster mgmt -n mgmt type=mgmt --overwrite

info "Generating kubeconfigs for dev and staging"
kind get kubeconfig --name dev > ./kubeconfigs/dev-host.yaml
kind get kubeconfig --name staging > ./kubeconfigs/staging-host.yaml

info "Creating Sveltos-compatible kubeconfigs"
sed -E 's#server: https://127\.0\.0\.1:[0-9]+#server: https://dev-control-plane:6443#' \
  ./kubeconfigs/dev-host.yaml > ./kubeconfigs/dev-sveltos.yaml

sed -E 's#server: https://127\.0\.0\.1:[0-9]+#server: https://staging-control-plane:6443#' \
  ./kubeconfigs/staging-host.yaml > ./kubeconfigs/staging-sveltos.yaml

info "Creating namespaces for managed clusters"
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -

info "Creating kubeconfig secrets for managed clusters"
kubectl create secret generic dev-sveltos-kubeconfig \
  -n dev \
  --from-file=kubeconfig=./kubeconfigs/dev-sveltos.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic staging-sveltos-kubeconfig \
  -n staging \
  --from-file=kubeconfig=./kubeconfigs/staging-sveltos.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

info "Registering dev and staging clusters in Sveltos"
kubectl apply -f ./sveltos/mgmt/dev-sveltoscluster.yaml
kubectl apply -f ./sveltos/mgmt/staging-sveltoscluster.yaml

info "Waiting for SveltosCluster resources to become ready"
kubectl wait --for=jsonpath='{.status.ready}'=true sveltoscluster/dev -n dev --timeout=180s
kubectl wait --for=jsonpath='{.status.ready}'=true sveltoscluster/staging -n staging --timeout=180s

info "Applying workload ClusterProfiles"
kubectl apply -f ./sveltos/clusters/podinfo-dev.yaml
kubectl apply -f ./sveltos/clusters/podinfo-staging.yaml

info "Installing ArgoCD through Sveltos"
kubectl apply -f ./sveltos/mgmt/clusterprofile-argocd.yaml

info "Waiting for ArgoCD namespace and pods"
for i in {1..60}; do
  if kubectl get namespace argocd >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

info "Applying ArgoCD Application"
kubectl apply -f ./sveltos/mgmt/argocd-app-sveltos.yaml

info "Final status"
kubectl get sveltoscluster -A --show-labels
kubectl get clusterprofile
kubectl get clustersummary -A
kubectl get applications -n argocd

info "Setup completed successfully"

cat <<'EOF'

Access ArgoCD:
kubectl config use-context kind-mgmt
kubectl port-forward svc/argocd-server -n argocd 8080:443
Open: https://localhost:8080

Access dev podinfo:
kubectl config use-context kind-dev
kubectl port-forward svc/podinfo 9898:9898 -n podinfo
Open: http://localhost:9898

Access staging podinfo:
kubectl config use-context kind-staging
kubectl port-forward svc/podinfo 9899:9898 -n podinfo
Open: http://localhost:9899
EOF
