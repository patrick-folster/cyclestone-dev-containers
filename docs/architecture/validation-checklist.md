# Architecture Validation Checklist

Date: 2026-08-01. Reviewer/owner: `@patrick-folster`. Updated 2026-08-03 for
ms-pf-0015 MVP qualification.

`PASS` here means the named static or fixture-backed check is complete. Runtime
methods V1–V8 in `compatibility.md` are mandatory publication gates and require
separately recorded native evidence. Items not yet backed by native evidence are
marked `DEFERRED` and converted to explicit support limitations with an owner and
ISO-8601 deadline (see [compatibility.md](compatibility.md) "Deferred native
evidence" section and [delivery-roadmap.md](delivery-roadmap.md)).

## Identity and decisions

| Check | Evidence | State |
| --- | --- | --- |
| Canonical source and image family are explicit; remote is unchanged | `repository-layout.md`; `.cyclestone/DECISIONS.md` D-001 | PASS |
| Base selection compares lifetime, architecture, maintenance, size, requirements | `compatibility.md`; D-002 | PASS |
| Every platform is supported or unsupported | `compatibility.md` C1–C10; D-003/D-016/D-018 | PASS |
| All supported matrix rows identify validation | C1: V1/V4; C2: V2/V4; C3: V3/V4; C4: V5/V7; C5: V6/V7; C6: V8 | PASS |
| Dev Container and Podman translations are separate | Fixtures reject keep-id with UID update; C6 disables mutation; D-016/D-018 | PASS |
| Unresolved/deferred decisions have owner and ISO-8601 deadline | D-009: no unresolved/deferred architecture decisions; V1–V7 native evidence deferrals have owner `@patrick-folster` and deadline 2026-09-30 | PASS |

## Public paths and writability

All values below are absolute in-container paths. `tests/contracts.sh` checks
their literal presence and absolute form. V1–V3 must execute `test -w` as the
effective non-root user and create/remove a probe file in every writable path.

| Path | Contract evidence | Runtime evidence method | State |
| --- | --- | --- | --- |
| `/home/developer` | filesystem table | V1, V2, V3 | DEFERRED — pending native evidence |
| `/workspace` | filesystem table/default `WORKDIR` | V1, V2, V3 | DEFERRED — pending native evidence |
| `/home/developer/.config` | filesystem table/`XDG_CONFIG_HOME` | V1, V2, V3 | DEFERRED — pending native evidence |
| `/home/developer/.cache` | filesystem table/`XDG_CACHE_HOME` | V1, V2, V3 | DEFERRED — pending native evidence |
| `/home/developer/.local/share` | filesystem table/`XDG_DATA_HOME` | V1, V2, V3 | DEFERRED — pending native evidence |
| `/home/developer/.config/cyclestone` | filesystem table/`CYCLESTONE_CONFIG_DIR` | V1, V2, V3 | DEFERRED — pending native evidence |
| `/home/developer/.local/share/cyclestone` | filesystem table/`CYCLESTONE_DATA_DIR` | V1, V2, V3 | DEFERRED — pending native evidence |

The specification requires `developer:developer` ownership at build time and
non-root write/search permission. Mounted backing stores are explicitly runtime
controlled; the image may not silently `chown` them. Local rootless-Podman
validation (C6/V8) exercises these paths on the current commit.

## Credentials and host dependencies

| Check | Evidence | State |
| --- | --- | --- |
| Base image embeds or requires no credential | `image-contract.md` environment table; `cyclestone-acquisition.md` public downloads | PASS |
| Allowed future injection is runtime-only and provider-documented | Narrow runtime environment variable, runtime secret file, or credential-helper/agent socket; none currently defined | PASS |
| Credentials are forbidden in build args, layers, defaults, labels, examples | `image-contract.md`; `threat-model.md` | PASS |
| No unspecified host path is required | Filesystem table and threat boundary 1 | PASS |
| Every optional host mount is enumerated | `/workspace`, `/home/developer`, `/home/developer/.config`, `/home/developer/.cache`, `/home/developer/.local/share`, `/home/developer/.config/cyclestone`, `/home/developer/.local/share/cyclestone` | PASS |
| Privileged mode and broad Docker/Podman socket mounts are not required | `image-contract.md`; `threat-model.md` | PASS |

## Acquisition and contract integrity

| Check | Evidence | State |
| --- | --- | --- |
| Explicit version/source/artifact mapping | `cyclestone-acquisition.md`; D-005; D-038 | PASS |
| Publisher checksum exists and both supported archives match | Cyclestone latest v-tag resolved at build; publisher `checksums.txt` fetched and trusted; archive digest verified | PASS |
| Missing, malformed, absent-record, mismatched, or unsafe archive fails closed | Required installation sequence in `cyclestone-acquisition.md`; `tests/install-tools.sh` | PASS |
| Environment table and OCI label set are exhaustive | `image-contract.md` | PASS |
| Downstream overrides have compatibility and migration requirements | `image-contract.md`; `versioning.md` | PASS |
| Child extensions preserve identity, paths, command, workspace, and PID-1 behavior | `child-images.md`; `child-image-contract.sh`; native C1-C3 fixture | DEFERRED — pending native C1–C3 evidence (owner `@patrick-folster`, deadline 2026-09-30) |
| Automated static architecture checks pass | `./tests/contracts.sh` | PASS |

## Source evidence

- Cyclestone latest v-tag GitHub Release, publisher `checksums.txt`, and
  archive member inspection, validated via `tests/install-tools.sh` mocked
  fixtures. Resolved version recorded per build.
- Paired Codex artifacts and agy, ollama, and opencode publisher-trusted native installers over
  HTTPS, validated via `tests/install-tools.sh` mocked fixtures.
- Canonical Ubuntu lifecycle documentation (Ubuntu 24.04 standard maintenance
  through May 2029), inspected 2026-07-31.
- Docker Official Image metadata for Ubuntu 24.04 `amd64` and `arm64`, inspected
  2026-07-31. `images/base/versions.env` pins reviewed index digest
  `sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90`
  and the reviewed amd64/arm64 platform manifests.
- Official Go release metadata at `https://go.dev/dl/?mode=json`, inspected
  2026-07-31. `examples/child-image/versions.env` pins Go 1.26.5 and the
  publisher's distinct Linux amd64/arm64 archive SHA-256 values.

## Implementation checks

| Check | Evidence | State |
| --- | --- | --- |
| Explicit build context, sole Containerfile, package allow-list | `.dockerignore`; `images/base/` | PASS |
| Immutable acquisition and hostile-fixture rejection | `install-tools.sh`; `tests/install-tools.sh` | PASS |
| Platform and metadata validation; load/OCI output | `build-base.sh`; `tests/build-base.sh` | PASS |
| Docker/OCI descriptor resolution and fail-closed layer coverage | `image-inspect.sh`; `image-inspect-archive.sh` hostile fixtures | PASS |
| Native runtime, filesystem, metadata, linkage, and layer inspection | `image-smoke.sh`; `image-inspect.sh`; V1–V4 | DEFERRED — pending native evidence (owner `@patrick-folster`, deadline 2026-09-30) |
| Dev Container behavior | V5 | DEFERRED — pending native evidence (owner `@patrick-folster`, deadline 2026-09-30) |
| Shared workspace, Git, HOME restart, and mutation regression | `workspace-identity.sh`; V7 | DEFERRED — pending native evidence (owner `@patrick-folster`, deadline 2026-09-30) |
| Rootless Podman keep-id and supplementary groups | `rootless-podman.sh`; V6 | DEFERRED — pending native evidence (owner `@patrick-folster`, deadline 2026-09-30) |
| Child Go SDK inheritance and hostile child rejection on amd64/arm64 | `child-image-inheritance.sh`; C1-C3 evidence | DEFERRED — pending native C1–C3 evidence (owner `@patrick-folster`, deadline 2026-09-30) |
| Project template on rootless Podman for matching/differing identities | `validate-milestone-local.sh`; `devcontainer-podman.sh`; V8; commit `c65f1f91eb356c1dc9ef0377db50cc6080be7567` | PASS |

## Automated release publication

| Check | Evidence | State |
| --- | --- | --- |
| Release workflow configuration is secure, permissions are restricted, commits are pinned to SHAs, runs on stable releases, and restricts forks/PRs | `.github/workflows/release-image.yml` | PASS |
| Multi-arch build and publish sets exact OCI labels and version mapping matching the versioning policy | `.github/workflows/release-image.yml`; `docs/architecture/versioning.md` | PASS |
| Automated vulnerability scanning runs prior to publication and fails closed on critical/high issues | `.github/workflows/release-image.yml` Trivy step | PASS |
| Cryptographically verifiable build provenance and SBOM are generated and attached via actions/attest-build-provenance | `.github/workflows/release-image.yml` Attestation step | PASS |

## Final state

**PASS — static architecture and implementation checks pass.** There are no
unresolved architecture decisions or allowed deferrals. Native V1–V7 runtime
evidence is deferred with explicit owner `@patrick-folster` and deadline
2026-09-30; these items are documented as support limitations in
[compatibility.md](compatibility.md) and [delivery-roadmap.md](delivery-roadmap.md).
V8 passed natively on 2026-08-01 for matching `1000:1000` and differing
`1001:1001` identities with Podman `5.8.4`, crun, and Dev Container CLI
`0.86.0`; both records share commit
`c65f1f91eb356c1dc9ef0377db50cc6080be7567` and source digest
`1e51c7210f07ec42ffe338b364fe35301ebef42473d9ce3cb9838353c0b87e8a`.

Milestone-cycle completion is local-first. C6/V8 must pass through
`./scripts/validate-milestone-local.sh ms-pf-0005` under matching and differing
host identities for the same commit. Docker jobs and GitHub-hosted results are
additional compatibility and publication coverage; they are not required to
finish a milestone cycle.
