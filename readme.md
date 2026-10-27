# AWS Cloud Operations Platform

A containerised Node.js application deployed on AWS using Terraform, Amazon ECR, Amazon EC2, AWS Systems Manager, and Amazon CloudWatch.

This project demonstrates practical cloud engineering skills including infrastructure as code, containerisation, application deployment, monitoring, IAM permissions, and CI automation.

## Architecture

Developer → GitHub → Docker image → Amazon ECR → Amazon EC2 → Node.js application

Operational monitoring:
- AWS Systems Manager for instance management
- Amazon CloudWatch Logs for application logs
- EC2 status checks and application health endpoint
- GitHub Actions for automated tests and dependency auditing

## Technology Stack

- AWS EC2
- Amazon ECR
- AWS Systems Manager (SSM)
- Amazon CloudWatch Logs
- Terraform
- Docker
- Node.js and Express
- Git and GitHub
- GitHub Actions
- npm audit

## Key Features

- Infrastructure provisioned with Terraform
- Dockerised Node.js application
- Container image stored in Amazon ECR
- EC2 deployment using a pinned container image digest
- IAM instance role and instance profile
- Systems Manager access without requiring inbound SSH
- IMDSv2 required for the EC2 instance
- Encrypted gp3 EBS root volume
- CloudWatch application logging with 14-day retention
- Application health endpoint
- GitHub Actions automated test workflow
- Production dependency vulnerability auditing
- ECR image scanning on push

## Project Structure

```text
.
├── .github/
│   └── workflows/
│       ├── test.yml
│       └── dependencyScan.yml
├── terraform/
│   ├── main.tf
│   ├── outputs.tf
│   ├── variables.tf
│   ├── versions.tf
│   └── .terraform.lock.hcl
├── app/
├── app.js
├── Dockerfile
├── docker-compose.yml
├── package.json
├── package-lock.json
├── tests/
├── .dockerignore
└── readme.md
```

## Application Endpoints

| Endpoint | Purpose |
|---|---|
| `/` | Application homepage |
| `/health` | Application health check |

Example:

```bash
curl http://YOUR_PUBLIC_IP/health
```

Expected response: a healthy JSON response from the application.

## Infrastructure and Deployment

The AWS infrastructure is defined in the `terraform/` directory.

The deployment uses:
- An EC2 instance running Amazon Linux
- An EC2 IAM role with Systems Manager access
- ECR permissions for retrieving the application image
- A security group allowing HTTP access on port 80
- CloudWatch Logs for application output

The application container listens on port 3000 internally, with host port 80 mapped to container port 3000.

The deployed application image is referenced by digest to provide deterministic image selection.

### Terraform

Prerequisites:
- AWS CLI
- Terraform
- Appropriate AWS credentials and permissions

From the project root:

```bash
cd terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
```

**Review the plan before making infrastructure changes.**

Do not apply changes blindly. Review replacements, downtime, public IP changes, and potential AWS costs.

## Containerisation

The application uses Docker.

The Dockerfile:
- Uses Node.js 24 Alpine
- Installs production dependencies
- Runs as a non-root application user
- Exposes port 3000

Build and run locally:

```bash
docker build -t cloud-operations-platform .
docker run --rm -p 3000:3000 cloud-operations-platform
```

Test:

```bash
curl http://localhost:3000/health
```

## CI and Dependency Security

GitHub Actions currently runs two workflows on pushes to `main` and pull request updates:

1. **Run Tests**
   - Installs project dependencies
   - Executes the automated test suite

2. **Dependency Vulnerability Check**
   - Installs production dependencies
   - Runs npm audit with a high-severity threshold

The dependency audit is scoped to production dependencies. It does not replace full development dependency, container, infrastructure, or runtime security assessments.

## Monitoring and Troubleshooting

### Application health

```bash
curl http://YOUR_PUBLIC_IP/health
```

### AWS Systems Manager

Use Session Manager to connect to the managed instance without opening SSH access.

### CloudWatch Logs

Log group:

`/cloud-operations-platform/app`

Review application startup messages and runtime logs in CloudWatch Logs.

### Common checks

- EC2 status checks
- SSM managed instance status
- EC2 security group rules
- ECR image availability
- Container status and logs
- CloudWatch log stream
- Application health endpoint

## Security Considerations

This is a portfolio and learning project, not a production-ready reference architecture.

Current considerations:
- The demo application is reachable over HTTP; HTTPS/TLS is not configured.
- HTTP access is publicly exposed through the security group.
- Review security group egress and IAM permissions before production use.
- Protect AWS credentials and GitHub tokens.
- Avoid committing `.env` files, Terraform state, credentials, or other secrets.
- Review dependency and image scan results regularly.
- Apply least-privilege IAM policies.
- Consider a managed HTTPS entry point, restricted network access, and stronger deployment controls for a production design.

## Cost Awareness

AWS resources may incur charges, including EC2 compute, EBS storage, ECR storage, CloudWatch ingestion/storage, and public IPv4 usage.

Check AWS Billing and Cost Management and review all deployed resources before leaving the project running.

## Cleanup

Terraform manages infrastructure lifecycle, but this configuration includes resource protection such as `prevent_destroy`.

Before cleanup:
1. Review Terraform state and resource dependencies.
2. Review the destruction plan.
3. Identify resources that may be retained or billed separately.
4. Confirm the consequences before removing protection or deleting resources.

Never remove protection or destroy resources without reviewing the impact.

## Skills Demonstrated

- AWS infrastructure operations
- Terraform infrastructure as code
- Docker image building and deployment
- Amazon ECR
- EC2 administration
- IAM roles and permissions
- AWS Systems Manager
- CloudWatch monitoring and logs
- CI automation
- Dependency auditing
- Linux troubleshooting
- Application health checks

## Repository

GitHub: https://github.com/PaVAnKuMaR-18o3/aws-cloud-operations-platform
