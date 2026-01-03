provider "aws" {
  region = "us-east-1"
}

# ----------------------------
# VPC and Subnet Data Sources (your Jumphost VPC)
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
# EKS Cluster (no role_arn - EKS uses default service-linked role)
# ----------------------------
resource "aws_eks_cluster" "eks" {
  name     = "project-eks"
  version  = "1.29"  # Required to allow omitting role_arn

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
}

# ----------------------------
# EKS Managed Node Group (no node_role_arn - EKS uses default)
# ----------------------------
resource "aws_eks_node_group" "node-grp" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "project-node-group"
  subnet_ids      = [data.aws_subnet.subnet-1.id, data.aws_subnet.subnet-2.id]

  instance_types = ["t2.large"]
  disk_size      = 20

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "project-eks-node-group"
  }

  depends_on = [aws_eks_cluster.eks]
}

# ----------------------------
# Optional: OIDC Provider (useful for IRSA later)
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