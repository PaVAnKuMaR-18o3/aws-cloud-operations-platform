data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "Security group for Cloud Operations Platform"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    description = "HTTP application access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}
# EC2 IAM role for Systems Manager
resource "aws_iam_role" "ec2" {
  name        = "CloudOperationsPlatformEC2Role"
  description = "EC2 role for Cloud Operations Platform Systems Manager access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "CloudOperationsPlatformEC2Role"
    Project = var.project_name
  }
}

# Existing AWS-managed SSM permissions
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2 instance profile
resource "aws_iam_instance_profile" "ec2" {
  name = "CloudOperationsPlatformEC2Profile"
  role = aws_iam_role.ec2.name

  tags = {
    Name    = "CloudOperationsPlatformEC2Profile"
    Project = var.project_name
  }
}
