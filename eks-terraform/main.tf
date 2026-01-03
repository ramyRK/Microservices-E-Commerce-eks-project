provider "aws" {
  region = "us-east-1"
}

# ----------------------------
# VPC and Subnet Data Sources
# ----------------------------
data "aws_vpc" "main" {
  tags = {
    Name = "Jumphost-vpc"
  }
}

data "aws_subnet" "subnet-1" {
  vpc_id = data.aws_vpc.main.id
  filter {
    name   = "tag:Name"
    values = ["Public-Subnet-1"]
  }
}

data "aws_subnet" "subnet-2" {
  vpc_id = data.aws_vpc.main.id
  filter {
    name   = "tag:Name"
    values = ["Public-subnet2"]
  }
}

data "aws_security_group" "selected" {
  vpc_id = data.aws_vpc.main.id
  filter {
    name   = "tag:Name"
    values = ["Jumphost-sg"]
  }
}

# ----------------------------
# EKS Cluster (uses default service-linked role - no custom IAM)
# ----------------------------
resource "aws_eks_cluster" "eks" {
  name     = "project-eks"

  vpc_config {
    subnet_ids              = [data.aws_subnet.subnet-1.id, data.aws_subnet.subnet-2.id]
    security_group_ids      = [data.aws_security_group.selected.id]
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  tags = {
    Name        = "project-eks-cluster"
    Environment = "dev"
    Terraform   = "true"
  }

  # Important for labs: adds creator as admin
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # This automatically grants the creator (your voclabs user) admin access
  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }
}

# ----------------------------
# Fargate Profile (serverless nodes - no IAM roles, no node groups)
# ----------------------------
resource "aws_eks_fargate_profile" "default" {
  cluster_name           = aws_eks_cluster.eks.name
  fargate_profile_name   = "default"
  pod_execution_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSFargatePodExecutionRole"  # usually pre-exists or auto-created

  subnet_ids = [data.aws_subnet.subnet-1.id, data.aws_subnet.subnet-2.id]

  selector {
    namespace = "default"
  }

  selector {
    namespace = "kube-system"
  }

  tags = {
    Name = "default-fargate-profile"
  }

  depends_on = [aws_eks_cluster.eks]
}

# Needed for account ID
data "aws_caller_identity" "current" {}

# ----------------------------
# Optional OIDC Provider (safe and useful)
# ----------------------------
data "aws_eks_cluster" "eks_oidc" {
  name = aws_eks_cluster.eks.name
}

data "tls_certificate" "oidc_thumbprint" {
  url = data.aws_eks_cluster.eks_oidc.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc_thumbprint.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.eks_oidc.identity[0].oidc[0].issuer
}