variable "project_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_oidc_id" {
  type        = string
  description = "OIDC issuer ID from EKS cluster (the hash portion of the OIDC URL)"
}
