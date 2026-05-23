# Local Kind Platform Engineering Demo - Windows Cleanup

$ErrorActionPreference = "Continue"

function Info($message) {
    Write-Host ""
    Write-Host "==> $message" -ForegroundColor Cyan
}

Info "Deleting local kind clusters"
kind delete cluster --name mgmt
kind delete cluster --name dev
kind delete cluster --name staging

Info "Removing generated kubeconfigs"
if (Test-Path ".\kubeconfigs") {
    Remove-Item -Recurse -Force ".\kubeconfigs"
}

Info "Remaining kind clusters"
kind get clusters

Info "Cleanup completed"
