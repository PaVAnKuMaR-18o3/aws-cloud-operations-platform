# AWS Cloud Operations Platform

**AWS · Terraform · Docker · EC2 · ECR · GitHub Actions · CloudWatch · Linux**

A hands-on cloud engineering project focused on provisioning, deploying, validating, monitoring, and troubleshooting a containerised Node.js application on AWS.

This project demonstrates infrastructure as code, container operations, AWS administration, automated testing, release engineering, application monitoring, and performance measurement.

**Repository:** [PaVAnKuMaR-18o3/aws-cloud-operations-platform](https://github.com/PaVAnKuMaR-18o3/aws-cloud-operations-platform)

---

## At a glance

| Area | Implementation |
|---|---|
| Cloud platform | AWS |
| Infrastructure as Code | Terraform |
| Compute | Amazon EC2 |
| Container registry | Amazon ECR |
| Application | Node.js / Express |
| Containerisation | Docker |
| CI and release automation | GitHub Actions |
| Monitoring and logs | Amazon CloudWatch |
| Instance administration | AWS Systems Manager Session Manager |
| Testing | Jest, Supertest, curl |
| Image publishing | GitHub Container Registry (GHCR) |

### Project highlights

- Provisioned AWS infrastructure with Terraform and deployed a Dockerised application to EC2.
- Configured instance administration using an IAM role and Systems Manager Session Manager, without requiring inbound SSH.
- Integrated Amazon ECR for image retrieval and CloudWatch Logs for application log collection.
- Implemented GitHub Actions workflows for application tests, dependency auditing, and Docker runtime validation.
- Built release automation with isolated candidate checks, image digest verification, signed provenance generation, and versioned GHCR publishing.
- Used digest-pinned image references, deployment locking, health checks, and rollback handling in deployment tooling.
- Recorded **2,500/2,500 successful responses** in one local synthetic burst test; results are qualified below.

---

## Architecture

```text
                         Source & validation
  Developer ──> GitHub repository
                      │
                      ├── GitHub Actions: application tests
                      ├── GitHub Actions: dependency audit
                      ├── GitHub Actions: Docker runtime validation
                      └── GitHub Actions: release validation & publishing
                                      │
                                      └──> GHCR
                                           Versioned image aliases
                                           Digest verification
                                           Signed provenance

                         AWS hosting & operations
  Amazon ECR ──> Amazon EC2 ──> Docker runtime ──> Node.js / Express app
                      │                               │
                      │                               └──> /health
                      ├── IAM instance profile
                      ├── AWS Systems Manager
                      └── CloudWatch Logs

  Infrastructure: Terraform
  Operations: AWS CLI, SSM Session Manager, Docker CLI
```

**Important distinction:** CI and release publishing are automated. The repository does **not** implement end-to-end GitHub Actions delivery to the AWS production environment. The AWS deployment and operations process is separate.

Candidate release validation runs an isolated container with loopback-only port exposure and health checks. It is designed to validate a candidate without replacing the existing production container during that check.

---

## Engineering work

### 1. AWS infrastructure and operations

- Defined cloud infrastructure using Terraform.
- Configured EC2 instance access through an IAM role and instance profile.
- Used AWS Systems Manager Session Manager for remote administration without requiring inbound SSH.
- Configured Amazon ECR for container image storage and retrieval.
- Integrated CloudWatch Logs for application log collection.
- Used EC2 and application health checks for operational verification.
- Worked with security groups, instance networking, and encrypted EBS storage.

### 2. Containerisation and deployment

- Packaged the Node.js application into a Docker image.
- Retrieved images from Amazon ECR and deployed the application to EC2.
- Used digest-pinned image references for deterministic image selection.
- Ran the application as a non-root container user.
- Inspected container status, runtime configuration, logs, and resource consumption.
- Implemented deployment safeguards including locking, health checks, and rollback handling.

### 3. Continuous integration

Four GitHub Actions workflows are present in the repository:

| Workflow | Purpose |
|---|---|
| `test.yml` | Executes automated application tests |
| `dependencyScan.yml` | Audits production dependencies |
| `docker-runtime.yml` | Builds the image and validates runtime health |
| `release.yml` | Validates and publishes release images |

The dependency workflow runs:

```bash
npm audit --omit=dev --audit-level=high
```

The Docker validation workflow builds a test image, launches an isolated container, checks the application health endpoint, and cleans up the test container.

### 4. Release engineering and image publishing

The release workflow implements a controlled image validation and publishing sequence:

1. Checks release prerequisites and expected image state.
2. Builds a candidate image.
3. Starts an isolated candidate container.
4. Runs application health checks.
5. Publishes the validated image to GitHub Container Registry (GHCR).
6. Captures and verifies the published image digest.
7. Generates signed build provenance.
8. Publishes and verifies versioned release aliases.
9. Produces a workflow summary.

**Latest verified release:** `v0.1.4`

- **Result:** Successful
- **Workflow duration:** 54 seconds
- **Git commit:** `ebb8a8ef9e7d3afbe96d4d2f6c59106130db1f54`
- **Evidence:** [View GitHub Actions release run](https://github.com/PaVAnKuMaR-18o3/aws-cloud-operations-platform/actions/runs/41185186145)

The release workflow verified the published image by digest and checked that release aliases resolved to the expected image. Signed provenance generation is implemented.

The release history includes a failed `v0.1.3` attempt followed by successful `v0.1.4`. The cause of the failed run should not be inferred without reviewing its logs.

---

## Performance testing

Synthetic HTTP tests were conducted against the candidate application's local loopback health endpoint.

### Concurrent burst benchmark

| Metric | Observed result |
|---|---:|
| Requests | 2,500 |
| Successful responses | 2,500 |
| Failed requests | 0 |
| Success rate | 100% |
| Observed throughput | 1,073.24 requests/sec |
| Average latency | 4.598 ms |
| P50 latency | 3.888 ms |
| P95 latency | 9.149 ms |
| P99 latency | 16.880 ms |

### Additional verification

| Test | Observed result |
|---|---|
| Sequential follow-up | 500/500 HTTP 200 |
| Follow-up average latency | 0.954 ms |
| Separate 30-second test | 1,651 successful / 1,681 requests |
| Failures in 30-second test | 30 (6 timeouts, 24 `URLError` events) |

**Interpretation:** The 2,500-request test achieved 100% success in that specific short burst. A separate 30-second test recorded 30 failures; their cause was not established. These local synthetic observations are not production SLA measurements or sustained capacity guarantees.

---

## Monitoring and troubleshooting

### Check application health

```bash
curl http://YOUR_PUBLIC_IP/health
```

### Connect with Systems Manager

```bash
aws ssm start-session \
  --target YOUR_INSTANCE_ID \
  --region YOUR_REGION
```

### Inspect the container

```bash
sudo docker ps
sudo docker stats --no-stream
sudo docker logs --tail 100 cloud-operations-platform
```

### CloudWatch

Application log group:

```text
/cloud-operations-platform/app
```

These checks support investigation of application health, container status, logs, runtime resource use, and deployment issues.

---

## Security controls and considerations

Controls and practices used in this project include:

- IAM role-based instance access.
- Systems Manager Session Manager administration.
- IMDSv2 requirement.
- Non-root application container.
- Digest-pinned deployment image.
- Isolated candidate validation.
- Automated production dependency auditing.
- Automated Docker runtime health checks.
- Encrypted EBS storage.

### Known limitations

This is a **portfolio learning project**, not a production-ready reference architecture.

- Public HTTP exposure is configured; HTTPS/TLS is not configured.
- End-to-end GitHub Actions delivery to AWS is not implemented.
- AWS Organizations Service Control Policy restrictions blocked the required IAM OIDC inspection operations.
- A production deployment script with rollback logic exists, but end-to-end production rollback and recovery have not been fully verified.
- The deployment-state helper is separate from the production deployment workflow and is not an integrated transaction journal.
- The timed benchmark's intermittent failures remain unexplained.
- Performance tests do not establish production capacity, availability, or reliability.

---

## Run locally

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

## Project structure

```text
.
├── .github/
│   └── workflows/
│       ├── test.yml
│       ├── dependencyScan.yml
│       ├── docker-runtime.yml
│       └── release.yml
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

## AWS cost awareness and cleanup

AWS resources such as EC2, EBS, ECR, CloudWatch, and public IPv4 addresses may incur charges.

Before leaving the environment running:

1. Review **AWS Billing and Cost Management**.
2. Identify active resources in the project region.
3. Review Terraform state and the resources it manages.
4. Check resource dependencies, retention needs, and deletion protection.
5. Decide whether to retain or remove each resource.

Do not delete resources blindly. Confirm what Terraform will change before applying a destroy operation, and preserve any evidence or state needed for the portfolio.

---

## Skills demonstrated

**Cloud & infrastructure:** AWS, EC2, ECR, IAM, Terraform, infrastructure as code  
**Containers:** Docker, Docker Compose, image lifecycle, runtime validation  
**CI & release engineering:** GitHub Actions, automated testing, dependency auditing, release validation, image digests, provenance  
**Operations:** Linux, AWS CLI, Systems Manager, CloudWatch Logs, health checks, troubleshooting  
**Quality:** Jest, Supertest, synthetic HTTP testing, performance measurement

---

## Repository and evidence

- **Source code:** [GitHub repository](https://github.com/PaVAnKuMaR-18o3/aws-cloud-operations-platform)
- **Latest release workflow:** [v0.1.4 — successful run](https://github.com/PaVAnKuMaR-18o3/aws-cloud-operations-platform/actions/runs/41185186145)
