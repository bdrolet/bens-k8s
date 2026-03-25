# bens-k8s

GKE Autopilot cluster on GCP, managed with Terraform.

## Prerequisites

- [gcloud CLI](https://cloud.google.com/sdk/docs/install) installed and authenticated
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- GCP project `bens-project-462804` with billing enabled

### Authenticate for Terraform

```bash
gcloud auth application-default login
```

## Provision the Cluster

```bash
cd terraform
terraform init
terraform apply
```

This creates a GKE Autopilot cluster in `us-central1`. The Terraform config also enables the required GCP APIs (`compute.googleapis.com`, `container.googleapis.com`).

## Configure kubectl

After `terraform apply` completes, configure `kubectl` to point at the new cluster:

```bash
gcloud container clusters get-credentials bens-k8s --region us-central1 --project bens-project-462804
```

Or copy the command from Terraform output:

```bash
terraform -chdir=terraform output -raw kubeconfig_command | bash
```

## Deploy Workloads

```bash
kubectl apply -f k8s/
```

## Tear Down

To avoid ongoing charges:

```bash
cd terraform
terraform destroy
```

## Cost

GKE provides a $74.40/month credit that covers the cluster management fee for one Autopilot cluster. You pay separately for compute (pod CPU/memory/disk requests), billed per-second. Delete the cluster with `terraform destroy` when not in use to minimize cost.
