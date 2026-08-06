# Security Policy

## Supported versions

The image family `ghcr.io/patrick-folster/cyclestone-dev-container-base` follows the
versioning policy in [docs/architecture/versioning.md](./docs/architecture/versioning.md).
Pre-1.0 development tags (such as `0.0.x`) are not part of the supported
image line and receive security fixes on a best-effort basis only. The
first supported line is `1.x`.

Security fixes ship as patch releases as soon as validation permits. A
breaking fix normally starts a new major line; the maintainer may authorize
an emergency migration on the affected line only with a dated security
decision and prominent release notice (see the "Urgent security exception"
section of the versioning policy).

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security-sensitive reports.

Instead, report vulnerabilities through GitHub Security Advisories:

1. Go to the repository's **Security** tab.
2. Select **Report a vulnerability** under "Private vulnerability reporting".
3. Describe the issue, affected versions, reproduction steps, and suggested
   remediation if available.

Reports are acknowledged within 5 business days. Coordinated disclosure and
credit are provided by default. A fix is released as soon as validation
permits, after which the advisory may be published.

## Trust model and scope

The security boundary and trust assumptions are documented in
[docs/architecture/threat-model.md](./docs/architecture/threat-model.md).
Reports outside the documented trust boundary (for example, a compromise of
the host kernel, the trusted maintainer account, or GitHub TLS) are residual
platform risks rather than Cyclestone vulnerabilities.

Built images are published with SBOM and SLSA build-provenance attestations.
See [docs/architecture/release-reproduction.md](./docs/architecture/release-reproduction.md)
for verification steps using `gh attestation verify`.