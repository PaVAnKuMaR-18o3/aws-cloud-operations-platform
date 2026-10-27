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

# Private Amazon ECR repository for application images
resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = "${var.project_name}-ecr"
    Project = var.project_name
  }
}

# Allow the EC2 instance to pull images from this repository
resource "aws_iam_role_policy" "ecr_pull" {
  name = "${var.project_name}-ecr-pull"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "ECRAuthorization"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "PullApplicationImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = aws_ecr_repository.app.arn
      }
    ]
  })
}

# EC2 application server
resource "aws_instance" "app" {
  ami                    = "ami-0ddbd63d0e3325a92"
  instance_type          = "t3.micro"
  subnet_id              = data.aws_subnet.selected.id
  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-USERDATA
    #!/bin/bash
    set -Eeuo pipefail

    exec > >(tee -a /var/log/cloud-operations-bootstrap.log | logger -t cloud-operations-bootstrap -s 2>/dev/console) 2>&1
    trap 'rc=$?; echo "BOOTSTRAP_FAILED exit_code=$rc line=$LINENO"; exit "$rc"' ERR

    REGION="ap-southeast-2"
    REGISTRY="074494041866.dkr.ecr.ap-southeast-2.amazonaws.com"
    IMAGE="$${REGISTRY}/cloud-operations-platform@sha256:2654baa36c8355f51c09cd4065985536bd14026ab1b06af0fb1ef3067fdebbbc"
    CONTAINER="cloud-operations-platform"

    retry() {
      local attempts="$1"
      shift
      local n=1
      until "$@"; do
        if [ "$n" -ge "$attempts" ]; then
          echo "FAILED after $n attempts: $*"
          return 1
        fi
        echo "Attempt $n failed: $*. Retrying in 10 seconds."
        n=$((n + 1))
        sleep 10
      done
    }

    echo "BOOTSTRAP_STARTED $(date -Is)"

    retry 3 dnf install -y docker
    systemctl enable --now docker
    retry 5 systemctl is-active --quiet docker

    command -v aws
    command -v curl

    ecr_login() {
      aws ecr get-login-password --region "$REGION" \
        | docker login --username AWS --password-stdin "$REGISTRY"
    }

    retry 6 ecr_login
    retry 6 docker pull "$IMAGE"

    start_container() {
      if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
        echo "Container already exists; leaving it untouched."
        return 0
      fi

      docker run -d \
        --name "$CONTAINER" \
        --restart unless-stopped \
        --log-driver=awslogs \
        --log-opt awslogs-region="$REGION" \
        --log-opt awslogs-group="/cloud-operations-platform/app" \
        --log-opt awslogs-stream="$${CONTAINER}" \
        --log-opt awslogs-create-group=false \
        --log-opt mode=non-blocking \
        --log-opt max-buffer-size=4m \
        -p 80:3000 \
        "$IMAGE"
    }

    retry 5 start_container

    health_check() {
      curl --fail --silent --show-error \
        --max-time 3 \
        http://127.0.0.1/health >/dev/null
    }

    for attempt in $(seq 1 30); do
      if health_check; then
        echo "BOOTSTRAP_SUCCESS $(date -Is)"
        exit 0
      fi
      echo "Health check $attempt/30 failed."
      sleep 5
    done

    echo "Application health check failed."
    docker ps -a
    docker logs --tail 100 "$CONTAINER" || true
    exit 1
  USERDATA

  tags = {
    Name    = "${var.project_name}-ec2"
    Project = var.project_name
  }

  depends_on = [
    aws_iam_role_policy.ecr_pull,
    aws_iam_role_policy_attachment.ssm,
    aws_iam_role_policy.cloudwatch_logs,
    aws_cloudwatch_log_group.app
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Application log group with finite retention
resource "aws_cloudwatch_log_group" "app" {
  name              = "/cloud-operations-platform/app"
  retention_in_days = 14

  tags = {
    Name    = "${var.project_name}-app-logs"
    Project = var.project_name
  }
}

# Allow EC2 to publish application logs
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.project_name}-cloudwatch-logs"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteApplicationLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.app.arn}:*"
      }
    ]
  })
}
