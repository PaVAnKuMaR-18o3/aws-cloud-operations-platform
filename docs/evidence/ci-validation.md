# CI validation evidence

## Latest source commit

- Commit: `0d750f3` — `fix: remove vulnerable production template dependency`
- The reported GitHub Actions results for this commit were:
  - Run Tests: passed
  - Dependency Vulnerability Check: passed
  - Docker Build and Runtime Validation: passed

The three workflows passed according to the verification captured during project closeout. Add direct run URLs or fresh screenshots if available.

## Test results recorded during closeout

- Node.js: 1 suite, 5 tests passed.
- Python deployment-state tests: 9 passed.
- Production dependency audit: `npm audit --omit=dev` reported 0 vulnerabilities.

Important: zero findings applies to production dependencies only. Do not state that the full development dependency tree has zero findings based on this audit.

## Release pipeline distinction

The release workflow is tag-triggered (`v*`). The latest main-branch commit did not automatically create a new published release. Release `v0.1.4` is documented separately in `README.md` for this evidence folder.
