output "vpc_id" {
  description = "Existing VPC used by this deployment"
  value       = data.aws_vpc.existing.id
}

output "subnet_id" {
  description = "Selected deployment subnet"
  value       = data.aws_subnet.selected.id
}

output "security_group_id" {
  description = "Application security group"
  value       = aws_security_group.app.id
}

output "ecr_repository_name" {
  description = "Private ECR repository name"
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_url" {
  description = "Private ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

output "instance_id" {
  description = "Application EC2 instance ID"
  value       = aws_instance.app.id
}

output "instance_public_ip" {
  description = "Application EC2 public IP"
  value       = aws_instance.app.public_ip
}

output "application_url" {
  description = "Application HTTP URL"
  value       = "http://${aws_instance.app.public_ip}"
}
