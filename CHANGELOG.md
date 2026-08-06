# Changelog

All notable changes to the Cyclestone Development Containers repository are
recorded here. The published container image family
`ghcr.io/patrick-folster/cyclestone-dev-container-base` is versioned independently under
Semantic Versioning — see [docs/architecture/versioning.md](./docs/architecture/versioning.md).
Image release notes are published on the GitHub Releases page; this changelog
tracks repository-level changes.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for repository source. Pre-1.0 development tags (`0.0.x`) are not part of the
supported image line; the first supported line is `1.x`.

## [Unreleased]

### Added
- `LICENSE` (MIT) for repository source.
- `NOTICE` documenting the repository license vs. the composite image license.
- `SECURITY.md` with private vulnerability reporting and supported-version policy.
- `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1).
- `CONTRIBUTING.md` with scope, DCO sign-off, and pull-request checklist.
- `.github/CODEOWNERS` designating `@patrick-folster` as the repository owner.
- DCO GitHub Action requiring `Signed-off-by:` on every commit.

### Changed
- Repository canonical name changed from `cyclestone-dev-containers-private`
  to `cyclestone-dev-containers` across workflows, scripts, tests, and docs.
- `README.md` updated with license, contributing, and security links plus
  CI and license badges.
- `release-image.yml` CI guard and OCI image label URLs updated to the
  public repository name.

### Removed
- Stale `.devcontainer/devcontainer.json.portable-bak` backup file.

## [0.0.1] - 2026-08-04

First public development snapshot of the Cyclestone Development Containers
repository. This is a pre-1.0 development tag; the first supported image
line is `1.x` per the versioning policy.

### Scope

- One independently versioned base image
  (`ghcr.io/patrick-folster/cyclestone-dev-container-base`, image line `1.x`) built from
  pinned Ubuntu 24.04 LTS.
- The `developer` (`1000:1000`) non-root user and `/workspace` contract.
- Direct rootless Podman `keep-id` support (C5).
- One validated Dev Container path via Dev Container CLI `0.86.0` with
  rootless Podman (C6/V8) for both matching `1000:1000` and differing
  `1001:1001` host identities.
- Deterministic provider configuration generation and validation.
- Local per-project provider authorization (default-deny, value-free).
- Codex and Ollama reference providers with secure credential handling.
- Fedora SELinux guidance for enforcing-SELinux hosts.
- Automated CI tests and GHCR publication workflow with SBOM and SLSA
  provenance.
- One fully exercised child-image example (Go 1.26.5).

### Qualification

The latest completed C6/V8 qualification passed on 2026-08-01 for commit
`c65f1f91eb356c1dc9ef0377db50cc6080be7567` with source digest
`1e51c7210f07ec42ffe338b364fe35301ebef42473d9ce3cb9838353c0b87e8a`,
using Podman `5.8.4`, crun, and Dev Container CLI `0.86.0` under matching
`1000:1000` and differing `1001:1001` accounts.

### Limitations

V1–V7 native evidence is DEFERRED to 2026-09-30; only C6/V8 currently has
recorded native evidence. See
[docs/architecture/compatibility.md](./docs/architecture/compatibility.md)
"Deferred native evidence" section and
[docs/architecture/delivery-roadmap.md](./docs/architecture/delivery-roadmap.md)
for the full limitations table. Unsupported matrix rows (C7–C10) remain
explicitly unsupported.

[Unreleased]: https://github.com/patrick-folster/cyclestone-dev-containers/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/patrick-folster/cyclestone-dev-containers/releases/tag/v0.0.1