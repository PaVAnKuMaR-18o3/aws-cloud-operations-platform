variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "ap-southeast-2"
}

variable "vpc_id" {
  description = "Existing AWS VPC ID"
  type        = string
  default     = "vpc-0083a372d370be4f9"
}

variable "subnet_id" {
  description = "Existing public subnet ID"
  type        = string
  default     = "subnet-02a5f06250e99e0aa"
}

variable "project_name" {
  description = "Project resource name"
  type        = string
  default     = "cloud-operations-platform"
}
