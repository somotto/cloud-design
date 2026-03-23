terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "orchestrator"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

locals {
  cluster_name = "${var.project_name}-cluster"
}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  private_subnets    = var.private_subnets
  public_subnets     = var.public_subnets
}

# ── IAM base roles (no OIDC dependency — created before EKS) ─────────────────
# These are the cluster and node roles EKS needs to bootstrap.
# The IRSA roles (ebs_csi, alb_controller) are in module.iam below and
# depend on the OIDC provider that EKS creates, so they run after EKS.
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── EKS cluster (needs base IAM roles above) ──────────────────────────────────
module "eks" {
  source = "../../modules/eks"

  project_name       = var.project_name
  cluster_name       = local.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  node_instance_type = var.node_instance_type
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
  node_desired_size  = var.node_desired_size

  eks_cluster_role_arn = aws_iam_role.eks_cluster.arn
  eks_node_role_arn    = aws_iam_role.eks_node.arn
}

# ── IAM IRSA roles (needs OIDC provider from EKS) ────────────────────────────
module "iam" {
  source = "../../modules/iam"

  project_name    = var.project_name
  cluster_name    = local.cluster_name
  cluster_oidc_id = regex(".*/id/(.+)$", module.eks.oidc_issuer_url)[0]
}

# ── EBS CSI addon (needs both EKS cluster and IRSA role) ─────────────────────
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.iam.ebs_csi_role_arn

  depends_on = [module.eks, module.iam]
}

# ── ECR repositories ──────────────────────────────────────────────────────────
module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
  services     = ["api-gateway", "inventory-app", "billing-app", "postgres-db", "rabbitmq"]
}

# ── Secrets Manager ───────────────────────────────────────────────────────────
module "secrets" {
  source = "../../modules/secrets"

  project_name          = var.project_name
  inventory_db_user     = var.inventory_db_user
  inventory_db_password = var.inventory_db_password
  inventory_db_name     = var.inventory_db_name
  billing_db_user       = var.billing_db_user
  billing_db_password   = var.billing_db_password
  billing_db_name       = var.billing_db_name
  rabbitmq_user         = var.rabbitmq_user
  rabbitmq_password     = var.rabbitmq_password
  rabbitmq_queue        = var.rabbitmq_queue
}
