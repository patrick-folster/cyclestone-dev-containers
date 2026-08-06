# Architecture and Compatibility

Compatibility is allow-list based. A combination is supported only when an
entire row below matches; omitted combinations are **unsupported**, not implied
support. Rows are tested scenarios, not a Cartesian-product promise.

## Status vocabulary

| Status | Meaning |
| --- | --- |
| Supported | Release-blocking contract with the stated validation method. |
| Experimental | Available for evaluation; failure is not release-blocking and no stability promise applies. |
| Deferred | No implementation/support promise until the named owner decides by the deadline. |
| Unsupported | Intentionally outside the contract; no validation or compatibility promise. |

## Base distribution decision

| Candidate | Lifetime and maintenance | Multi-architecture | Size/tool compatibility | Outcome |
| --- | --- | --- | --- | --- |
| Ubuntu 24.04 LTS | Standard security maintenance through May 2029; Canonical `apt` security updates | Official image provides `amd64` and `arm64` | Small base, glibc/shell/package ecosystem fits Cyclestone and development tooling | **Selected** |
| Debian 12 slim | Long-lived Debian security support | Official multi-architecture image | Smaller, but older packages increase bootstrap work | Not selected for line `1.x` |
| Alpine 3.x | Shorter moving release line | Official multi-architecture image | Smallest, but musl and minimal userspace add compatibility risk | Unsupported for line `1.x` |

Builds must pin the reviewed Ubuntu 24.04 OCI index digest, record it in
`org.opencontainers.image.base.digest`, and receive normal security rebuilds.
The floating `ubuntu:24.04` tag is discovery input, not a reproducible release
reference. Moving to another distribution or LTS release requires the versioning
classification in `versioning.md`.

## Validation methods

| ID | Concrete release check |
| --- | --- |
| V1 | On a native Ubuntu 22.04 amd64 host with rootful Docker Engine, build by pinned base digest; assert effective user/paths/environment/labels, write every contract directory, run `cyclestone --version`, and exercise PID-1 TERM forwarding. |
| V2 | Repeat V1 on native Ubuntu 24.04 amd64 with rootless Docker; bind-mount a host-owned workspace and assert non-root read/write without startup `chown`. |
| V3 | Repeat V1 on a native Ubuntu 24.04 arm64 runner using an arm64-native build (no QEMU) and verify the selected archive against the publisher checksum. |
| V4 | With no provider definition, credentials, optional mounts, or host sockets, run contract tests and Cyclestone in a temporary repository; assert the base behavior succeeds and does not inspect host credential locations. |
| V5 | With Dev Container CLI `0.86.0` and rootful Docker on native Ubuntu 24.04 amd64, run as a deliberately created `2001:2002` host identity; validate `remoteUser` and `containerUser`, UID/GID mutation, host-owned workspace operations, Git, persistent HOME, and absence of privilege/socket defaults. |
| V6 | With rootless Podman 4.9 and crun on native Ubuntu 24.04 amd64, map the invoking identity to image user `developer` using keep-id; validate workspace/Git ownership, namespace maps, persistent HOME, and `keep-groups` access. |
| V7 | For both identity modes, snapshot pre-existing workspace metadata, run shared create/edit/delete/Git/build assertions, reject `safe.directory=*`, record identity/mount/namespace evidence, restart, and prove no startup ownership rewrite. |
| V8 | On native Linux amd64 with Dev Container CLI `0.86.0` selecting rootless Podman directly, run the project template locally under isolated `1000:1000` and nonmatching accounts; build through rootless Podman from a builder-reported content-addressed image ID, assert keep-id workspace ownership, lifecycle and cache behavior, stop/reopen/rebuild, record the conflicting UID-mutation outcome, and repeat after removing editor customizations. |

Methods V1–V8 are mandatory publication gates. `tests/contracts.sh` verifies
that each supported row names its methods; it does not substitute for native
runtime evidence.

V8 was qualified on 2026-08-01 against commit
`c65f1f91eb356c1dc9ef0377db50cc6080be7567` under matching `1000:1000` and
differing `1001:1001` accounts on native Linux amd64 with Podman `5.8.4`, crun,
and Dev Container CLI `0.86.0`. Both evidence records have source digest
`1e51c7210f07ec42ffe338b364fe35301ebef42473d9ce3cb9838353c0b87e8a`.
The Podman 4.9 references in V6 and C5/C6 are minimum version requirements;
the V8 qualification used a newer Podman release that satisfies them.

## Allow-listed combinations

| ID | Host | CPU | Runtime | Base | Image line | Cyclestone | Provider definition | Dev Container behavior | Status | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | Native Ubuntu 22.04 LTS Linux | `amd64` | Rootful Docker Engine | Ubuntu 24.04 LTS | `1.x` | latest v-tag | Empty toolset (default) | Direct engine; image identity `developer:1000:1000` | Supported | V1, V4 |
| C2 | Native Ubuntu 24.04 LTS Linux | `amd64` | Rootless Docker Engine | Ubuntu 24.04 LTS | `1.x` | latest v-tag | Empty toolset (default) | Direct engine; explicit mapped-UID ACL for bind mount | Supported | V2, V4 |
| C3 | Native Ubuntu 24.04 LTS Linux | `arm64` | Rootful Docker Engine | Ubuntu 24.04 LTS | `1.x` | latest v-tag | Empty toolset (default) | Direct engine; image identity `developer:1000:1000` | Supported | V3, V4 |
| C4 | Native Ubuntu 24.04 LTS Linux | `amd64` | Rootful Docker Engine + Dev Container CLI `0.86.0` | Ubuntu 24.04 LTS | `1.x` | latest v-tag | Empty toolset (default) | Both user fields are `developer`; `updateRemoteUserUID=true`; no keep-id | Supported | V5, V7 |
| C5 | Native Ubuntu 24.04 LTS Linux | `amd64` | Rootless Podman 4.9 + crun | Ubuntu 24.04 LTS | `1.x` | latest v-tag | Empty toolset (default) | Direct command; keep-id maps host identity to `developer:1000:1000`; no client UID mutation | Supported | V6, V7 |
| C6 | Native Linux | `amd64` | Rootless Podman 4.9 + crun + Dev Container CLI `0.86.0` | Ubuntu 24.04 LTS | `1.x` | latest v-tag | Empty toolset (default) | Direct `--docker-path podman`; both user fields `developer`; `updateRemoteUserUID=false`; keep-id maps host identity to unchanged `1000:1000` | Supported | V8 |
| C7 | WSL2, macOS, or Windows host | Any | Any | Ubuntu 24.04 LTS | `1.x` | latest v-tag | Any | Any | Unsupported | None |
| C8 | Any Linux host | `arm/v7`, `ppc64le`, `riscv64`, or `s390x` | Any | Ubuntu 24.04 LTS | `1.x` | latest v-tag | Any | Any | Unsupported | Cyclestone release artifact absent |
| C9 | Any host | Any | Any | Any other distribution | `1.x` | Any | Any | Any | Unsupported | None |
| C10 | Any host | Any | Any | Ubuntu 24.04 LTS | `1.x` | Any pinned version | Any provider definition | Any | Unsupported | No pinned-version contract; latest v-tag resolved at build |

"Empty toolset (default)" is a positive supported state: no tool is installed
unless `INSTALL_TOOLS` selects it; no provider metadata, CLI, credential,
service, socket, or provider-specific mount is present or required by default.
Future rows must specify all eight dimensions, a status, and validation. A status
change is a reviewed compatibility decision, not an editorial update.

## Deferred platform decisions

No platform decision is deferred for line `1.x`: native Ubuntu hosts and the two
architectures above are the bounded supported set; all other platforms are
explicitly unsupported. Future platform proposals begin
unsupported and must name an accountable owner and ISO-8601 validation deadline
before they may be recorded as deferred.

## Deferred native evidence

Native runtime evidence for V1–V7 requires Ubuntu 22.04 amd64, Ubuntu 24.04
amd64, and Ubuntu 24.04 arm64 hosts with the specified Docker and Podman
versions. V8 was qualified locally on 2026-08-01. The following items are
converted to explicit support limitations with an accountable owner and
ISO-8601 deadline, as required by the MVP qualification acceptance criteria:

| Item | Methods | Owner | Deadline | Note |
| --- | --- | --- | --- | --- |
| Native runtime, filesystem, metadata, linkage, and layer inspection | V1–V4 | `@patrick-folster` | 2026-09-30 | Static contract checks and local rootless-Podman validation pass; native Ubuntu evidence pending |
| Dev Container behavior (rootful Docker UID mutation) | V5 | `@patrick-folster` | 2026-09-30 | C4 requires native Ubuntu 24.04 amd64 with Dev Container CLI and rootful Docker |
| Rootless Podman keep-id and supplementary groups | V6 | `@patrick-folster` | 2026-09-30 | C5 requires native Ubuntu 24.04 amd64 with rootless Podman 4.9 and crun |
| Shared workspace, Git, HOME restart, and mutation regression | V7 | `@patrick-folster` | 2026-09-30 | V7 supports both C4 and C5 identity modes on native Ubuntu |
| Child Go SDK inheritance and hostile child rejection on amd64/arm64 | C1–C3 | `@patrick-folster` | 2026-09-30 | Child-image static checks and local rootless-Podman child builds pass; native amd64/arm64 inheritance evidence pending |

These deferrals do not change the supported status of C1–C5. They record that
native evidence has not yet been captured on the declared matrix hosts. V8
remains PASS on native Linux amd64. GitHub-hosted workflows may repeat or
extend coverage but cannot be the sole source of a cycle-completion verdict
(D-019).
