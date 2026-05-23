#!/usr/bin/env bash
set -euo pipefail

info() {
  echo ""
  echo "==> $1"
}

info "Deleting local kind clusters"
kind delete cluster --name mgmt || true
kind delete cluster --name dev || true
kind delete cluster --name staging || true

info "Removing generated kubeconfigs"
rm -rf kubeconfigs

info "Remaining kind clusters"
kind get clusters || true

info "Cleanup completed"
