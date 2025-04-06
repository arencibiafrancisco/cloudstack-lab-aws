variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"  # Ireland region
}

variable "key_name" {
  description = "Name of the AWS key pair"
  type        = string
  default     = "cloudstack-key"
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
