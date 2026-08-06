# Cyclestone Development Containers

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)
[![Base image native validation](https://github.com/patrick-folster/cyclestone-dev-containers/actions/workflows/base-image-validation.yml/badge.svg)](https://github.com/patrick-folster/cyclestone-dev-containers/actions/workflows/base-image-validation.yml)
[![DCO](https://github.com/patrick-folster/cyclestone-dev-containers/actions/workflows/dco.yml/badge.svg)](https://github.com/patrick-folster/cyclestone-dev-containers/actions/workflows/dco.yml)
[![Container image](https://img.shields.io/badge/image-ghcr.io%2Fpatrick--folster%2Fcyclestone--dev--container--base-blue)](https://github.com/patrick-folster/cyclestone-dev-containers/pkgs/container/cyclestone-dev-container-base)

> **Alpha software — experimental, no warranty, no liability.** This repository
> and the published `ghcr.io/patrick-folster/cyclestone-dev-container-base` image family are
> in early development and may break without notice. The maintainer
> `@patrick-folster` is not liable for any damages. See
> [DISCLAIMER.md](./DISCLAIMER.md) and [LICENSE](./LICENSE).

This repository is the canonical source for the
`ghcr.io/patrick-folster/cyclestone-dev-container-base` image family. It defines and locally
builds the non-provider, non-root Cyclestone base image; it does not publish it.

This project is a work in progress in preparation for an upcoming release. Its main purpose is to access the base image. With the [Cyclestone](https://github.com/patrick-folster/cyclestone) app, you can create a dev container based on this image.

Start with the [repository layout](docs/architecture/repository-layout.md),
[base-image contract](docs/architecture/image-contract.md), and
[compatibility matrix](docs/architecture/compatibility.md). Contract changes
require approval from the repository maintainer, `@patrick-folster`, and the
tests in `tests/` must remain green.

The [base-image operator guide](docs/base-image.md) covers local builds, tests,
inspection, supported platforms, updates, and limitations. The
[workspace identity guide](docs/workspace-identity.md) gives separate Dev
Container and direct rootless Podman commands and troubleshooting.
The [child-image extension guide](docs/child-images.md) provides the supported
digest-pinned pattern for adding project SDKs without baking in source.
The [project Dev Container guide](docs/devcontainers.md) covers the reusable
template, rootless Podman CLI workflow, trust review, cache, and editor smoke.
The [local provider authorization guide](docs/provider-authorization.md) covers
the supported `scripts/devcontainer-permissions.sh` interface, exact-plan
approval, project identity, private grants, and revocation. Authorization is
value-free. The [provider credential guide](docs/provider-credentials.md) covers
the separate rootless-Podman materialization interface, exact built-in adapters,
refresh/synchronization, active-session revocation, recovery, and backup limits.
The [runtime configuration guide](docs/runtime-configuration.md) covers
deterministic committed/local generation, validation, and explicit startup.
The [Ollama setup guide](docs/ollama.md) covers host-service provider setup with
GPU and CPU access. The [SELinux guide](docs/selinux.md) covers Fedora SELinux
configuration for rootless Podman. The [upgrades guide](docs/upgrades.md) covers
image, SDK, provider, and template upgrade steps. The
[troubleshooting guide](docs/troubleshooting.md) covers common failure modes.
The [quick-start guide](docs/quick-start.md) provides a guided path from base
build to running project Dev Container.

Run the dependency-free contract checks with:

```sh
./tests/contracts.sh
```

Qualify secure provider credentials locally with one non-root rootless-Podman
account (expected negative probes are internal; the final status must be zero):

```sh
./scripts/validate-milestone-local.sh ms-pf-0008
```

Finish the project Dev Container milestone locally with rootless Podman (no
Docker or GitHub Actions required):

```sh
./scripts/validate-milestone-local.sh ms-pf-0005
```

V8 requires one run as a `1000:1000` account and one as a nonmatching account;
both accounts must have Dev Container CLI `0.86.0` on `PATH` and must use the
same absolute `EVIDENCE_DIR`. A passing first identity case intentionally exits
nonzero while it waits for its peer; the second successful run validates both
same-commit evidence records. See the
[project Dev Container guide](docs/devcontainers.md#local-cycle-qualification)
for the exact workflow and a pinned `npm exec` fallback.

Validate templates, examples, and documentation locally (static checks plus
provider example validation; SDK builds run when a container engine and base
image are available):

```sh
./scripts/validate-milestone-local.sh ms-pf-0014
```

See the [examples](examples/README.md) and [quick-start guide](docs/quick-start.md)
for the five example projects and task-oriented workflows.

The latest completed C6/V8 qualification passed on 2026-08-01 for commit
`c65f1f91eb356c1dc9ef0377db50cc6080be7567` with source digest
`1e51c7210f07ec42ffe338b364fe35301ebef42473d9ce3cb9838353c0b87e8a`,
using Podman `5.8.4`, crun, and Dev Container CLI `0.86.0` under matching
`1000:1000` and differing `1001:1001` accounts.

## Limitations

V1–V7 native evidence is DEFERRED to 2026-09-30; only C6/V8 currently has
recorded native evidence. See the
[compatibility matrix](docs/architecture/compatibility.md) "Deferred native
evidence" section and the [delivery roadmap](docs/architecture/delivery-roadmap.md)
for the full limitations table and accountable owner. Unsupported matrix rows
(C7–C10) remain explicitly unsupported.

## Repository license vs. image license

The scripts, templates, schemas, and documentation in this repository are
licensed under the MIT License — see [LICENSE](./LICENSE). The published
container image family is a composite artifact (Ubuntu base + MIT Cyclestone
binary + optional provider CLIs) and carries its own SPDX license expression
in its `org.opencontainers.image.licenses` OCI label; see [NOTICE](./NOTICE)
and [docs/architecture/release-reproduction.md](docs/architecture/release-reproduction.md)
for verification.

## Contributing and security

- [CONTRIBUTING.md](./CONTRIBUTING.md) — scope, DCO sign-off, pull-request checklist.
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) — Contributor Covenant 2.1.
- [SECURITY.md](./SECURITY.md) — private vulnerability reporting and supported-version policy.
- [CHANGELOG.md](./CHANGELOG.md) — repository-level change history.
