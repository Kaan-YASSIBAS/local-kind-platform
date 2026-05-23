# Local Kind Platform Engineering Demo

A fully local multi-cluster Kubernetes GitOps platform demo for Windows using **kind**, **Sveltos** and **ArgoCD**.

This project simulates a platform engineering workflow with one management cluster and two workload clusters. Everything runs locally on Docker Desktop, so no cloud account or cloud cost is required.

## Architecture

```text
GitHub Repository
        |
        v
ArgoCD on mgmt cluster
        |
        v
Sveltos ClusterProfiles on mgmt cluster
        |
        v
+----------------------+----------------------+
|                                             |
v                                             v
dev cluster                                  staging cluster
podinfo DEV                                 podinfo STAGING
```

## What This Project Demonstrates

- Running multiple local Kubernetes clusters with kind
- Using a dedicated management cluster
- Registering workload clusters into Sveltos
- Managing deployments across clusters with Sveltos ClusterProfiles
- Targeting clusters with labels such as `env=dev` and `env=staging`
- Installing ArgoCD on the management cluster
- Creating a GitOps loop where ArgoCD syncs Sveltos manifests from Git
- Deploying the same application with different configurations per environment
- Running the full setup locally on Windows with Docker Desktop

## Cluster Layout

| Cluster | Role | Description |
| --- | --- | --- |
| `mgmt` | Management cluster | Runs Sveltos and ArgoCD |
| `dev` | Workload cluster | Receives the development version of `podinfo` |
| `staging` | Workload cluster | Receives the staging version of `podinfo` |

## Tools Used

- [kind](https://kind.sigs.k8s.io/)
- [Kubernetes](https://kubernetes.io/)
- [Sveltos](https://projectsveltos.github.io/sveltos/)
- [ArgoCD](https://argo-cd.readthedocs.io/)
- [Helm](https://helm.sh/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- PowerShell

## Repository Structure

```text
local-kind-platform/
│
├── clusters/
│   ├── mgmt.yaml
│   ├── dev.yaml
│   └── staging.yaml
│
├── sveltos/
│   ├── mgmt/
│   │   ├── clusterprofile-argocd.yaml
│   │   ├── argocd-app-sveltos.yaml
│   │   ├── dev-sveltoscluster.yaml
│   │   └── staging-sveltoscluster.yaml
│   │
│   └── clusters/
│       ├── podinfo-dev.yaml
│       └── podinfo-staging.yaml
│
├── scripts/
│
├── .gitignore
├── LICENSE
└── README.md
```

## Prerequisites

Make sure the following tools are installed on Windows:

```powershell
docker --version
kubectl version --client
kind version
helm version
git --version
```

Required tools:

- Docker Desktop
- kubectl
- kind
- Helm
- Git
- PowerShell

## 1. Create the Local Clusters

Create three local Kubernetes clusters with kind:

```powershell
kind create cluster --config .\clusters\mgmt.yaml
kind create cluster --config .\clusters\dev.yaml
kind create cluster --config .\clusters\staging.yaml
```

Verify the clusters:

```powershell
kind get clusters
```

Expected output:

```text
dev
mgmt
staging
```

Check the Docker containers:

```powershell
docker ps
```

You should see:

```text
mgmt-control-plane
dev-control-plane
staging-control-plane
```

## 2. Install Sveltos on the Management Cluster

Switch to the management cluster:

```powershell
kubectl config use-context kind-mgmt
```

Add the Sveltos Helm repository:

```powershell
helm repo add projectsveltos https://projectsveltos.github.io/helm-charts
helm repo update
```

Install Sveltos:

```powershell
helm install projectsveltos projectsveltos/projectsveltos `
  -n projectsveltos `
  --create-namespace `
  --version 1.10.0
```

Verify the installation:

```powershell
kubectl get pods -n projectsveltos
```

## 3. Label the Management Cluster

Sveltos selects clusters by labels. The management cluster is labeled as `type=mgmt` so ArgoCD can be installed only there.

```powershell
kubectl label sveltoscluster mgmt -n mgmt type=mgmt --overwrite
```

Verify:

```powershell
kubectl get sveltoscluster -A --show-labels
```

## 4. Register Dev and Staging Clusters in Sveltos

Sveltos needs kubeconfig credentials to manage the `dev` and `staging` clusters.

Generate host kubeconfigs:

```powershell
kind get kubeconfig --name dev > .\kubeconfigs\dev-host.yaml
kind get kubeconfig --name staging > .\kubeconfigs\staging-host.yaml
```

The default kubeconfigs use `127.0.0.1`, which works from Windows but not from inside the management cluster.

Replace the server addresses with Docker network reachable addresses:

```powershell
(Get-Content .\kubeconfigs\dev-host.yaml) `
  -replace 'server: https://127\.0\.0\.1:\d+', 'server: https://dev-control-plane:6443' |
  Set-Content .\kubeconfigs\dev-sveltos.yaml

(Get-Content .\kubeconfigs\staging-host.yaml) `
  -replace 'server: https://127\.0\.0\.1:\d+', 'server: https://staging-control-plane:6443' |
  Set-Content .\kubeconfigs\staging-sveltos.yaml
```

Create namespaces:

```powershell
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -
```

Create kubeconfig secrets:

```powershell
kubectl create secret generic dev-sveltos-kubeconfig `
  -n dev `
  --from-file=kubeconfig=.\kubeconfigs\dev-sveltos.yaml `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic staging-sveltos-kubeconfig `
  -n staging `
  --from-file=kubeconfig=.\kubeconfigs\staging-sveltos.yaml `
  --dry-run=client -o yaml | kubectl apply -f -
```

Apply the SveltosCluster resources:

```powershell
kubectl apply -f .\sveltos\mgmt\dev-sveltoscluster.yaml
kubectl apply -f .\sveltos\mgmt\staging-sveltoscluster.yaml
```

Verify:

```powershell
kubectl get sveltoscluster -A --show-labels
```

Expected result:

```text
dev       READY true   env=dev
mgmt      READY true   type=mgmt
staging   READY true   env=staging
```

## 5. Deploy Podinfo with Sveltos

Apply the ClusterProfiles:

```powershell
kubectl apply -f .\sveltos\clusters\podinfo-dev.yaml
kubectl apply -f .\sveltos\clusters\podinfo-staging.yaml
```

Verify the ClusterProfiles:

```powershell
kubectl get clusterprofile
```

Check Sveltos deployment summaries:

```powershell
kubectl get clustersummary -A
```

## 6. Verify the Dev Deployment

Switch to the dev cluster:

```powershell
kubectl config use-context kind-dev
```

Check the deployed app:

```powershell
kubectl get pods -n podinfo
kubectl get svc -n podinfo
```

Port-forward the service:

```powershell
kubectl port-forward svc/podinfo 9898:9898 -n podinfo
```

Open:

```text
http://localhost:9898
```

## 7. Verify the Staging Deployment

Switch to the staging cluster:

```powershell
kubectl config use-context kind-staging
```

Check the deployed app:

```powershell
kubectl get pods -n podinfo
kubectl get svc -n podinfo
```

Port-forward the service:

```powershell
kubectl port-forward svc/podinfo 9899:9898 -n podinfo
```

Open:

```text
http://localhost:9899
```

## 8. Install ArgoCD Through Sveltos

Switch back to the management cluster:

```powershell
kubectl config use-context kind-mgmt
```

Apply the ArgoCD ClusterProfile:

```powershell
kubectl apply -f .\sveltos\mgmt\clusterprofile-argocd.yaml
```

Verify ArgoCD pods:

```powershell
kubectl get pods -n argocd
```

Get the initial admin password:

```powershell
$passwordBase64 = kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($passwordBase64))
```

Port-forward ArgoCD:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open:

```text
https://localhost:8080
```

Login:

```text
username: admin
password: <decoded-password>
```

## 9. Enable the GitOps Loop

ArgoCD tracks the `sveltos/clusters` directory in this repository.

Apply the ArgoCD Application:

```powershell
kubectl apply -f .\sveltos\mgmt\argocd-app-sveltos.yaml
```

Verify:

```powershell
kubectl get applications -n argocd
```

From this point on, changes pushed to the `sveltos/clusters` directory are synced by ArgoCD to the management cluster. Sveltos then deploys those changes to the matching workload clusters.

## GitOps Flow

```text
Developer pushes change to GitHub
        |
        v
ArgoCD syncs sveltos/clusters manifests
        |
        v
ClusterProfiles are updated on mgmt cluster
        |
        v
Sveltos detects the changes
        |
        v
dev and staging clusters are updated
```

## Example GitOps Test

Update the message in:

```text
sveltos/clusters/podinfo-dev.yaml
```

For example:

```yaml
message: "DEV v2 - synced by ArgoCD and deployed by Sveltos"
```

Commit and push:

```powershell
git add .
git commit -m "Update dev podinfo message"
git push
```

ArgoCD syncs the change, and Sveltos applies it to the `dev` cluster.

## Important Notes

### Localhost vs Docker Network

A kubeconfig generated by kind usually contains a server address like this:

```text
https://127.0.0.1:<port>
```

This works from the Windows host, but it does not work from inside the management cluster. For Sveltos, the server address must be reachable from inside the Docker network:

```text
https://dev-control-plane:6443
https://staging-control-plane:6443
```

This is one of the most important parts of the project.

### Kubeconfigs Should Not Be Committed

The `kubeconfigs/` directory contains local cluster credentials and should not be committed to Git.

Make sure `.gitignore` contains:

```gitignore
kubeconfigs/
```

## Cleanup

Delete the local kind clusters:

```powershell
kind delete cluster --name mgmt
kind delete cluster --name dev
kind delete cluster --name staging
```

Verify:

```powershell
kind get clusters
```

## Learning Goals

This project was built to understand:

- How local Kubernetes clusters can simulate real multi-cluster environments
- How a management cluster controls workload clusters
- How Sveltos performs label-based multi-cluster deployment
- How ArgoCD enables GitOps synchronization
- Why kubeconfig server addresses matter in multi-cluster setups
- How GitOps and platform engineering workflows fit together

## License

This project is licensed under the MIT License.
