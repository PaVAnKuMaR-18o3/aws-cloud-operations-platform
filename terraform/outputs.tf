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
