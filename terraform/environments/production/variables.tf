variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "orchestrator"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.29"
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets (EKS nodes)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets (ALB)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

# ── EKS nodes ─────────────────────────────────────────────────────────────────
variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.small"
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

# ── Application secrets (use terraform.tfvars or env vars, never commit) ─────
variable "inventory_db_user" {
  description = "Inventory database username"
  type        = string
  sensitive   = true
}

variable "inventory_db_password" {
  description = "Inventory database password"
  type        = string
  sensitive   = true
}

variable "inventory_db_name" {
  description = "Inventory database name"
  type        = string
  default     = "inventory_db"
}

variable "billing_db_user" {
  description = "Billing database username"
  type        = string
  sensitive   = true
}

variable "billing_db_password" {
  description = "Billing database password"
  type        = string
  sensitive   = true
}

variable "billing_db_name" {
  description = "Billing database name"
  type        = string
  default     = "billing_db"
}

variable "rabbitmq_user" {
  description = "RabbitMQ username"
  type        = string
  sensitive   = true
}

variable "rabbitmq_password" {
  description = "RabbitMQ password"
  type        = string
  sensitive   = true
}

variable "rabbitmq_queue" {
  description = "RabbitMQ queue name"
  type        = string
  default     = "billing_queue"
}
