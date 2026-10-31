# Project evidence

This directory documents evidence for the AWS Cloud Operations Platform.

## Evidence status

| Evidence | Status | Notes |
|---|---|---|
| CI validation | Partially documented | Latest source commit `0d750f3` was reported with the three validation workflows passing. Add direct run links/screenshots if available. |
| Published container release | Verified historical release | `v0.1.4`; see release details below. |
| AWS deployment | Not packaged here | Add sanitized console screenshots or command output after checking the current resource state. |
| Application health | Not packaged here | Capture the live `/health` response only after verifying it is reachable. |
| Benchmark | Pending source-output reconciliation | Do not publish a numeric claim until the original benchmark output is confirmed. |
| Rollback | Not verified end-to-end on AWS | Unit/state tests are not proof of an actual AWS rollback. |

## Known release evidence

- Release: `v0.1.4`
- Release workflow run: [41185186145](https://github.com/PaVAnKuMaR-18o3/aws-cloud-operations-platform/actions/runs/41185186145)
- Release commit: `ebb8a8ef9e7d3afbe96d4d2f6c59106130db1f54`
- Release image digest: `sha256:fb38201de0256ac99a690c66ef20a0c6e51e593606484731be9f80b3dc2277b0`
- Reported release checks: candidate health check, digest verification, version alias verification, and signed provenance.

This is historical release evidence. It does not certify that the current production instance is running this release or that the latest main-branch commit was released.

## How to add deployment evidence

Use current output only. Redact account IDs, access details, private IPs where unnecessary, request identifiers, secrets, and user data before committing.

Suggested evidence:
1. Screenshot showing the running EC2 instance and instance state (hide account ID and unrelated resources).
2. Sanitized terminal output showing the deployed app's `/health` response and version/commit if exposed by the app.
3. Screenshot or link to successful GitHub Actions runs for the current commit.
4. CloudWatch log/metrics screenshot with a visible time range and resource label redacted as needed.

Suggested filenames:
- `aws-instance-state.png`
- `application-health.png`
- `ci-validation.png`
- `cloudwatch-operations.png`

Do not create placeholder images or claim screenshots exist when they do not.
