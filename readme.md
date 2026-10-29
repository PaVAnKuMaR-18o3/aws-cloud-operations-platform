# AWS Cloud Operations Platform

**AWS | Terraform | Docker | EC2 | ECR | GitHub Actions | CloudWatch | Linux**

A hands-on cloud engineering project focused on deploying, validating, monitoring, and troubleshooting a containerised Node.js application on AWS.

The project demonstrates infrastructure as code, container operations, AWS administration, automated testing, release validation, application monitoring, and performance measurement.

**[GitHub Repository](https://github.com/PaVAnKuMaR-18o3/aws-cloud-operations-platform)**

---

## Project Highlights

- **AWS deployment:** Deployed a containerised Node.js application on Amazon EC2 using an Amazon ECR image.
- **Infrastructure as Code:** Used Terraform to define AWS infrastructure.
- **Container operations:** Built, retrieved, ran, inspected, and validated Docker images and containers.
- **Automated CI:** Implemented GitHub Actions workflows for tests, dependency auditing, and Docker runtime validation.
- **Release validation:** Tested a candidate image in an isolated container while preserving the existing production deployment.
- **Monitoring:** Integrated CloudWatch Logs and used AWS Systems Manager Session Manager for instance administration.
- **Performance testing:** Executed synthetic HTTP tests, including a 2,500-request concurrent burst with 100% successful responses in one test.

## Architecture

```text
              Developer
                  |
                  v
              GitHub
                  |
          GitHub Actions
          /      |       \
       Tests   Audit    Docker
                         Build
                  |
             Amazon ECR
                  |
                  v
              Amazon EC2
                  |
             Docker Runtime
                  |
            Node.js / Express
                  |
             Application
                  |
          +-------+--------+
          |                |
          v                v
    CloudWatch Logs    Health Endpoint

    Operations:
    AWS Systems Manager
```

**Release validation:** A separate candidate container is used for validation, with loopback-only port exposure and health checks before any production promotion decision.

---

## Technology Stack

| Category | Technologies |
|---|---|
| Cloud | AWS EC2, Amazon ECR, CloudWatch, Systems Manager |
| Infrastructure as Code | Terraform |
| Containers | Docker, Docker Compose |
| Application | Node.js, Express, EJS |
| CI | GitHub Actions |
| Testing | Jest, Supertest, curl |
| Security | IAM, IMDSv2, npm audit |
| Operations | Linux, AWS CLI, Docker CLI |
| Version Control | Git, GitHub |

---

## Engineering Work

### 1. AWS Infrastructure and Operations

Provisioned and operated cloud infrastructure for hosting a containerised application.

- Defined infrastructure using Terraform.
- Configured EC2 instance access through an IAM role and instance profile.
- Used AWS Systems Manager Session Manager for remote administration without requiring inbound SSH.
- Configured Amazon ECR for container image storage and retrieval.
- Integrated CloudWatch Logs for application log collection.
- Used EC2 and application health checks for operational verification.
- Worked with security groups, instance networking, and encrypted EBS storage.

### 2. Containerisation and Deployment

- Packaged the Node.js application into a Docker image.
- Used Amazon ECR as the container image registry.
- Deployed the application to EC2.
- Used a digest-pinned image reference for deterministic image selection.
- Ran the application as a non-root container user.
- Inspected container status, runtime configuration, logs, and resource consumption.

### 3. CI Automation

Implemented three GitHub Actions workflows.

| Workflow | Purpose |
|---|---|
| Run Tests | Executes automated application tests |
| Dependency Vulnerability Check | Audits production dependencies |
| Docker Build and Runtime Validation | Builds the image and validates application health |

The Docker CI workflow builds a test image, launches an isolated container, checks its health endpoint, and cleans up the test container.

The dependency workflow runs:

`npm audit --omit=dev --audit-level=high`

**Verification:** Successful GitHub Actions runs were observed for the test, dependency audit, Docker build, and runtime validation workflows.

### 4. Candidate Release Validation

Implemented an isolated candidate validation process.

The validation workflow includes:

1. Checking the expected production baseline.
2. Pulling the target image.
3. Verifying candidate image identity.
4. Starting a separate candidate container.
5. Binding the candidate service to loopback on port `13002`.
6. Running health checks.
7. Cleaning up the candidate container after validation.

The existing production container was preserved during candidate testing.

This demonstrates release verification and operational caution rather than directly replacing a running service.

---

## Performance Testing

Synthetic HTTP tests were conducted against the candidate application's local loopback health endpoint.

### Concurrent burst benchmark

| Metric | Observed result |
|---|---:|
| Requests | 2,500 |
| Successful responses | 2,500 |
| Failed requests | 0 |
| Success rate | 100% |
| Observed throughput | 1,073.24 req/sec |
| Average latency | 4.598 ms |
| P50 latency | 3.888 ms |
| P95 latency | 9.149 ms |
| P99 latency | 16.880 ms |

### Additional verification

| Test | Result |
|---|---|
| Sequential follow-up | 500/500 HTTP 200 |
| Follow-up average latency | 0.954 ms |
| Separate 30-second test | 1,651 successful / 1,681 requests |
| Failures in 30-second test | 30 |

### Interpretation

The 2,500-request test achieved 100% success in that particular short burst.

A separate 30-second benchmark recorded 30 failures: 6 timeouts and 24 `URLError` events. The cause was not established.

These are local, synthetic observations, not production SLA measurements or sustained capacity guarantees.

---

## Monitoring and Troubleshooting

### Application health

```bash
curl http://YOUR_PUBLIC_IP/health
```

### Connect through AWS Systems Manager

```bash
aws ssm start-session \
  --target YOUR_INSTANCE_ID \
  --region YOUR_REGION
```

### Useful operational checks

```bash
sudo docker ps
sudo docker stats --no-stream
sudo docker logs --tail 100 cloud-operations-platform
```

CloudWatch log group:

`/cloud-operations-platform/app`

These checks help investigate container health, application logs, runtime resources, and deployment issues.

---

## Security and Reliability Considerations

Security controls and operational practices used in the project include:

- IAM role-based instance access.
- Systems Manager administration.
- IMDSv2 requirement.
- Non-root application container.
- Digest-pinned deployment image.
- Isolated candidate validation.
- Automated dependency auditing.
- Automated Docker runtime health checks.

### Known limitations

This is a portfolio learning project, not a production-ready reference architecture.

- Public HTTP exposure is configured; HTTPS/TLS is not configured.
- End-to-end GitHub Actions delivery to AWS is not implemented.
- AWS Organizations Service Control Policy restrictions blocked the required IAM OIDC inspection operations.
- A production deployment script with rollback logic exists, but end-to-end production rollback and recovery have not been fully verified.
- The deployment-state helper is separate from the production deployment workflow and is not an integrated transaction journal.
- The timed benchmark's intermittent failures remain unexplained.
- Performance tests do not establish production capacity or reliability.

---

## Project Structure

```text
.
├── .github/
│   └── workflows/
│       ├── test.yml
│       ├── dependencyScan.yml
│       └── docker-runtime.yml
├── app/
├── scripts/
├── terraform/
├── tests/
├── app.js
├── Dockerfile
├── docker-compose.yml
├── package.json
├── package-lock.json
├── .dockerignore
└── readme.md
```

---

## Run Locally

### Prerequisites

- Node.js
- npm
- Docker

### Build and run

```bash
docker build -t cloud-operations-platform .
docker run --rm -p 3000:3000 cloud-operations-platform
```

Verify:

```bash
curl http://localhost:3000/health
```

### Run automated tests

```bash
npm ci
npm test
```

---

## AWS Cost Awareness

Resources such as EC2, EBS, ECR, CloudWatch, and public IPv4 addresses may incur charges.

Review AWS Billing and Cost Management and identify deployed resources before leaving the environment running.

Review Terraform state, resource protection, and deletion dependencies before performing cleanup.

---

## Skills Demonstrated

AWS Cloud Engineering · Cloud Operations · Infrastructure as Code · Terraform · Docker · Amazon EC2 · Amazon ECR · IAM · AWS Systems Manager · CloudWatch · GitHub Actions · CI Automation · Linux Administration · Application Monitoring · Troubleshooting · Release Validation · Performance Testing

---

## Repository

**GitHub:** [PaVAnKuMaR-18o3/aws-cloud-operations-platform](https://github.com/PaVAnKuMaR-18o3/aws-cloud-operations-platform)
