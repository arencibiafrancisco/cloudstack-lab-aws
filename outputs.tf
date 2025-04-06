output "cloudstack_public_ip" {
  description = "Public IP of CloudStack instance"
  value       = aws_instance.cloudstack.public_ip
}

output "cloudstack_private_ip" {
  description = "Private IP of CloudStack instance"
  value       = aws_instance.cloudstack.private_ip
}

output "kvm_public_ip" {
  description = "Public IP of KVM instance"
  value       = aws_eip.kvm.public_ip
}

output "kvm_private_ip" {
  description = "Private IP of KVM instance"
  value       = aws_instance.kvm.private_ip
}

output "kvm_cloudbr1_ip" {
  description = "CloudBr1 IP of KVM instance"
  value       = aws_network_interface.kvm_cloudbr1.private_ip
}

output "private_key_path" {
  description = "Path to the generated private key"
  value       = "/home/farencibia/.ssh/${var.key_name}.pem"
}

output "ssh_connection_cloudstack" {
  description = "SSH command to connect to CloudStack instance"
  value       = "ssh -i /home/farencibia/.ssh/${var.key_name}.pem ubuntu@${aws_instance.cloudstack.public_ip}"
}

output "ssh_connection_kvm" {
  description = "SSH command to connect to KVM instance"
  value       = "ssh -i /home/farencibia/.ssh/${var.key_name}.pem ubuntu@${aws_eip.kvm.public_ip}"
}

output "cloudstack_ui_urls" {
  description = "CloudStack UI access URLs"
  value = {
    http  = "http://${aws_instance.cloudstack.public_ip}:8080/client"
    https = "https://${aws_instance.cloudstack.public_ip}:8443/client"
  }
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.main.id
}
