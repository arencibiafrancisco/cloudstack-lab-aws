terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Generate SSH key pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${var.key_name}.pem"
  file_permission = "0600"

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${var.ssh_private_key_directory}
      mv ${var.key_name}.pem ${var.ssh_private_key_directory}/
      chmod 700 ${var.ssh_private_key_directory}
    EOT
  }
}

resource "aws_key_pair" "generated" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh.public_key_openssh

  depends_on = [local_file.private_key]
}

# VPC and Security Groups
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "cloudstack-vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "cloudstack-subnet"
  }
}

# Additional subnet for cloudbr1
resource "aws_subnet" "cloudbr1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"  # Different range for cloudbr1
  map_public_ip_on_launch = false
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "cloudstack-cloudbr1"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "cloudstack-igw"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "cloudstack-rt"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# Security Groups
resource "aws_security_group" "cloudstack" {
  name        = "cloudstack-sg"
  description = "Security group for CloudStack node"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cloudstack_ui_cidr_blocks
  }

  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cloudstack_ui_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cloudstack-sg"
  }
}

resource "aws_security_group" "kvm" {
  name        = "kvm-sg"
  description = "Security group for KVM node"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.cloudstack.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kvm-sg"
  }
}

# EC2 Instances
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "cloudstack" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"

  subnet_id                   = aws_subnet.main.id
  vpc_security_group_ids      = [aws_security_group.cloudstack.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 50
  }

  key_name = aws_key_pair.generated.key_name

  tags = {
    Name = "cloudstack-node"
  }

  # Install requirements and configure CloudStack
  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -e",
      
      # Instalar solo lo necesario para Ansible
      "sudo apt-get update",
      "sudo apt-get install -y python3-pip git",
      "sudo pip3 install ansible",
      
      # Clonar repositorio
      "git clone https://github.com/arencibiafrancisco/cloudstack-installer.git",
      "cd cloudstack-installer",
      
      # Configurar hosts
      "echo '[acs-manager]' > hosts",
      "echo '127.0.0.1 ansible_connection=local' >> hosts",
      
      # Ejecutar playbook
      "sudo ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook deploy-cloudstack.yml -i hosts -e \"nodetype=master mysql_root_password=${var.mysql_root_password} mysql_cloud_password=${var.mysql_cloud_password} cloudstack_release=4.19 cloudstack_systemvmtemplate=4.19.1 install_local_db=true\""
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ssh.private_key_pem
      host        = self.public_ip
      timeout     = "15m"
    }
  }

  depends_on = [aws_key_pair.generated]
}

# Create network interface for KVM instance
resource "aws_network_interface" "kvm_primary" {
  subnet_id       = aws_subnet.main.id
  security_groups = [aws_security_group.kvm.id]

  tags = {
    Name = "kvm-primary"
  }
}

resource "aws_network_interface" "kvm_cloudbr1" {
  subnet_id       = aws_subnet.cloudbr1.id
  security_groups = [aws_security_group.kvm.id]

  tags = {
    Name = "kvm-cloudbr1"
  }
}

# Attach Elastic IP to primary interface
resource "aws_eip" "kvm" {
  domain            = "vpc"
  network_interface = aws_network_interface.kvm_primary.id

  tags = {
    Name = "kvm-eip"
  }
}

resource "aws_instance" "kvm" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "m5.2xlarge"

  root_block_device {
    volume_size = 100
  }

  key_name = aws_key_pair.generated.key_name

  network_interface {
    network_interface_id = aws_network_interface.kvm_primary.id
    device_index        = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.kvm_cloudbr1.id
    device_index        = 1
  }

  tags = {
    Name = "kvm-node"
  }

  # Install requirements and configure KVM
  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "set -e",
      
      # Instalar solo lo necesario para Ansible
      "sudo apt-get update",
      "sudo apt-get install -y python3-pip git jq",
      "sudo pip3 install ansible",
      
      # Clonar repositorio
      "git clone https://github.com/arencibiafrancisco/kvm-installer.git",
      "cd kvm-installer",
      
      # Configurar hosts
      "echo '[hypervisors]' > hosts.ini",
      "echo '127.0.0.1 ansible_connection=local' >> hosts.ini",
      
      # Obtener información de red
      "PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)",
      "GATEWAY_IP=$(ip route | grep default | awk '{print $3}')",
      "CLOUDBR1_IP=$(ip -j addr show dev ens6 | jq -r '.[0].addr_info[0].local')",
      
      # Ejecutar playbook
      "sudo ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i hosts.ini kvm-playbook.yml -e \"cloudbr0_ip=$PRIVATE_IP/24 cloudbr0_gw=$GATEWAY_IP dns_servers=8.8.8.8,1.1.1.1 cloudbr1_ip=$CLOUDBR1_IP/24\""
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = tls_private_key.ssh.private_key_pem
      host        = aws_eip.kvm.public_ip
      timeout     = "15m"
    }
  }

  depends_on = [aws_key_pair.generated, aws_instance.cloudstack, aws_eip.kvm]
}
