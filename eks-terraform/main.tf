provider "aws" {
  region = "us-east-1"
}

/*
# ALL CUSTOM IAM CREATION IS COMMENTED OUT
# AWS Academy does not allow iam:CreateRole
*/

# ----------------------------
# VPC and Subnet Data Sources (from your Jumphost VPC)
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
# Use the AWS-managed EKS service-linked role (pre-created, allowed in labs)
# ----------------------------
data "aws_iam_role" "eks_service_role" {
  name = "AWSServiceRoleForAmazonEKS"
}

# ----------------------------
# EKS Cluster - uses default service-linked role
# ----------------------------
resource "aws_eks_cluster" "eks" {
  name     = "project-eks"
  role_arn = data.aws_iam_role.eks_service_role.arn

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
# EKS Node Group - uses launch template to avoid needing custom node role
# ----------------------------
resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "eks-node-"
  image_id      = data.aws_ssm_parameter.amzn2_ami.value
  instance_type = "t2.large"

  vpc_security_group_ids = [data.aws_security_group.selected.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    /etc/eks/bootstrap.sh project-eks
  EOF
  )

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "project-eks-node"
    }
  }
}

# Get latest Amazon Linux 2 AMI for EKS (recommended)
data "aws_ssm_parameter" "amzn2_ami" {
  name = "/aws/service/eks/optimized-ami/amazon-linux-2/recommended/image_id"
}

# Node group using launch template (no custom IAM role needed)
resource "aws_eks_node_group" "node-grp" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "project-node-group"
  node_role_arn   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AmazonEKSNodeRole"  # fallback if needed, but usually not required

  subnet_ids = [data.aws_subnet.subnet-1.id, data.aws_subnet.subnet-2.id]

  scaling_config {
    desired_size = 3
    max_size     = 10
    min_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$LatestVersion"
  }

  # Optional: remove node_role_arn if it causes issues
  # (EKS can sometimes use default permissions)
  lifecycle {
    ignore_changes = [node_role_arn]
  }

  tags = {
    Name = "project-eks-node-group"
  }

  depends_on = [aws_eks_cluster.eks]
}

# For OIDC (optional, safe)
data "aws_caller_identity" "current" {}

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