provider "aws" {
  region = "us-east-1"
}

/*
# ----------------------------
# ALL CUSTOM IAM ROLES AND POLICIES ARE COMMENTED OUT
# (AWS Academy does not allow creating IAM roles)
# ----------------------------
# (Keep this entire block commented)
resource "aws_iam_role" "master" { ... }
resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" { ... }
# ... all other IAM resources you had ...
resource "aws_iam_instance_profile" "worker" { ... }
*/

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
# EKS Cluster (no custom role_arn → uses default service-linked role)
# ----------------------------
resource "aws_eks_cluster" "eks" {
  name = "project-eks"

  vpc_config {
    subnet_ids              = [data.aws_subnet.subnet-1.id, data.aws_subnet.subnet-2.id]
    security_group_ids      = [data.aws_security_group.selected.id]
    endpoint_private_access = false
    endpoint_public_access  = true
  }

  tags = {
    Name        = "yaswanth-eks-cluster"
    Environment = "dev"
    Terraform   = "true"
  }

  # Removed: role_arn and depends_on (not needed in restricted labs)
}

# ----------------------------
# EKS Node Group (no custom node_role_arn → uses default)
# ----------------------------
resource "aws_eks_node_group" "node-grp" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = var.node_group_name
  subnet_ids      = [data.aws_subnet.subnet-1.id, data.aws_subnet.subnet-2.id]

  capacity_type  = "ON_DEMAND"
  disk_size      = 20
  instance_types = ["t2.large"]

  labels = {
    env = "dev"
  }

  tags = {
    Name = "project-eks-node-group"
  }

  scaling_config {
    desired_size = 3
    max_size     = 10
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  # Removed: node_role_arn and depends_on
}

# ----------------------------
# OIDC Provider for IRSA (optional but useful for later)
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