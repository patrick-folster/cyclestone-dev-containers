# Repository Layout and Ownership

The configured and canonical source repository is
`git@github.com:patrick-folster/cyclestone-dev-containers.git`. Repository
visibility is not an image-visibility promise. The canonical OCI image family is
`ghcr.io/patrick-folster/cyclestone-dev-container-base`.

| Area | Purpose | Accountable owner |
| --- | --- | --- |
| `images/` | Base and child image definitions | Image maintainer |
| `scripts/` | Shared build, install, entrypoint, and validation logic | Script maintainer |
| `providers/` | Provider definitions and metadata | Provider maintainer |
| `templates/` | Dev Container templates | Template maintainer |
| `tests/` | Automated contract and behavior validation | Repository maintainer |
| `examples/` | Non-normative usage examples | Example author |
| `.github/workflows/` | CI, security, and publication automation | Workflow maintainer |
| `schemas/` | Machine-readable contract schemas | Schema maintainer |
| `docs/` | Architecture contracts and user guidance | Documentation author |
| `.cyclestone/DECISIONS.md` | Append-only architecture decision history | Repository maintainer |

The named area owner prepares and validates a change. `@patrick-folster`, the
accountable repository maintainer, approves every public contract, compatibility,
security-boundary, schema-compatibility, required-check, or publication change.
Area READMEs define boundaries; an absent implementation file means the capability
has not been implemented, not that it is implicitly supported.
