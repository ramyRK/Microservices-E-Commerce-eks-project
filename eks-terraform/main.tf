provider "aws" {
  region = "us-east-1"
}

# ----------------------------
# Use Existing Lab VPC/Subnet/SG (your style)
# ----------------------------
data "aws_vpc" "main" {
  tags = {
    Name = "Jumphost-vpc"
  }
}

data "aws_subnet" "subnet_1" {
  vpc_id = data.aws_vpc.main.id
  filter {
    name   = "tag:Name"
    values = ["Public-Subnet-1"]
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
# Amazon Linux 2023 AMI
# ----------------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ----------------------------
# EC2 Instance: Jenkins + Docker + K3s
# ----------------------------
resource "aws_instance" "cicd_k8s" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.medium" # ✅ recommended for Jenkins + K3s
  subnet_id              = data.aws_subnet.subnet_1.id
  vpc_security_group_ids = [data.aws_security_group.selected.id]

  # If your lab has a keypair, you can enable this:
  # key_name = "vockey"

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Update system
              dnf update -y

              # Install packages
              dnf install -y git wget unzip curl

              # Install Java 17 (needed for Jenkins)
              dnf install -y java-17-amazon-corretto

              # Install Docker
              dnf install -y docker
              systemctl enable docker
              systemctl start docker
              usermod -aG docker ec2-user

              # Install Jenkins
              wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
              rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
              dnf install -y jenkins
              systemctl enable jenkins
              systemctl start jenkins

              # Install K3s (Kubernetes)
              curl -sfL https://get.k3s.io | sh -

              # Allow ec2-user to use kubectl
              mkdir -p /home/ec2-user/.kube
              sudo cp /etc/rancher/k3s/k3s.yaml /home/ec2-user/.kube/config
              sudo chown ec2-user:ec2-user /home/ec2-user/.kube/config
              echo "export KUBECONFIG=/home/ec2-user/.kube/config" >> /home/ec2-user/.bashrc

              # Install kubectl shortcut
              ln -s /usr/local/bin/k3s /usr/local/bin/kubectl

              # Print Jenkins password to a file for easy access
              sleep 20
              cat /var/lib/jenkins/secrets/initialAdminPassword > /home/ec2-user/jenkins_password.txt
              chown ec2-user:ec2-user /home/ec2-user/jenkins_password.txt
              EOF

  tags = {
    Name = "cicd-kubernetes-server"
  }
}

# ----------------------------
# Outputs
# ----------------------------
output "server_public_ip" {
  value = aws_instance.cicd_k8s.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.cicd_k8s.public_ip}:8080"
}

output "ssh_command" {
  value = "ssh ec2-user@${aws_instance.cicd_k8s.public_ip}"
}

output "jenkins_password_hint" {
  value = "After SSH: cat ~/jenkins_password.txt"
}
