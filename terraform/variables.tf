variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "bens-project-462804"
}

variable "region" {
  description = "GCP region for the cluster"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Name of the GKE Autopilot cluster"
  type        = string
  default     = "bens-k8s"
}
