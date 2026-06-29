variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "key_name" {
  description = "Name of the AWS key pair"
  type        = string
  default     = "cloudstack-key"
}

variable "ssh_private_key_directory" {
  description = "Local directory where the generated SSH private key is stored"
  type        = string
  default     = "~/.ssh"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to access SSH"
  type        = list(string)
}

variable "allowed_cloudstack_ui_cidr_blocks" {
  description = "CIDR blocks allowed to access CloudStack UI ports"
  type        = list(string)
}

variable "mysql_root_password" {
  description = "MySQL root password used by the CloudStack installer"
  type        = string
  sensitive   = true
}

variable "mysql_cloud_password" {
  description = "CloudStack MySQL user password used by the CloudStack installer"
  type        = string
  sensitive   = true
}
