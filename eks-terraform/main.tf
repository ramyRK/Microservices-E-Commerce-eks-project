provider "aws" {
  region = "us-east-1"
}

# ----------------------------
# ✅ LAB PROVIDED IAM ROLE ARNs (DO NOT CREATE IAM)
# ----------------------------
variable "lab_eks_cluster_role_arn" {
  type        = string
  description = "EKS Cluster Role provided by Learner Lab"
  default     = "arn:aws:iam::992382587855:role/c191399a4934151l13165692t1w992382-LabEksClusterRole-GqAZ5sHBdNfo"
}

variable "lab_eks_node_role_arn" {
  type        = string
  description = "EKS Node Role provided by Learner Lab"
  default     = "arn:aws:iam::992382587855:role/c191399a4934151l13165692t1w992382587-LabEksNodeRole-bk1JuSIrlHHD"
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
# ✅ EKS Cluster (uses LAB Role)
# ----------------------------
resource "aws_eks_cluster" "eks" {
  name     = "project-eks"
  role_arn = var.lab_eks_cluster_role_arn

  vpc_config {
    subnet_ids         = [data.aws_subnet.subnet-1.id, data.aws_subnet.subnet-2.id]
    security_group_ids = [data.aws_security_group.selected.id]
  }

  tags = {
    Name        = "project-eks"
    Environment = "dev"
    Terraform   = "true"
  }
}

# ----------------------------
# ✅ Node Group (uses LAB Node Role)
# ----------------------------
resource "aws_eks_node_group" "node-grp" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = var.node_group_name
  node_role_arn   = var.lab_eks_node_role_arn

  subnet_ids     = [data.aws_subnet.subnet-1.id, data.aws_subnet.subnet-2.id]
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

  depends_on = [aws_eks_cluster.eks]
}
