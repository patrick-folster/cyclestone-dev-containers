# Contributing to Cyclestone Development Containers

Thank you for your interest in contributing. This repository is the canonical
source for the `ghcr.io/patrick-folster/cyclestone-dev-container-base` image family. It is
maintained by `@patrick-folster`, who approves every public-contract,
compatibility, security-boundary, schema-compatibility, required-check, or
publication change.

## License

By contributing, you agree that your contributions are licensed under the MIT
License, the same license that covers this repository — see [LICENSE](./LICENSE).
Every commit must be signed off (see "Developer Certificate of Origin" below).

## Scope

Accepted contributions:

- Bug fixes and security improvements to scripts, templates, schemas,
  tests, and documentation.
- New examples under `examples/` that fit the documented image contract.
- New provider definitions under `providers/` after security review.
- Documentation improvements.

Out of scope for unsolicited contributions:

- The contents of `.cyclestone/` (internal planning, milestones, reports).
  This directory is gitignored and not part of the public contract; do not
  submit changes to it.
- Changes to `docs/architecture/` contracts without maintainer pre-approval.
- Changes that alter the published image family's behavior, OCI labels, or
  supported compatibility matrix without an explicit compatibility declaration.

## Before you start

1. Read [docs/architecture/repository-layout.md](./docs/architecture/repository-layout.md)
   for area ownership.
2. Read [docs/architecture/image-contract.md](./docs/architecture/image-contract.md)
   for the non-negotiable image contract.
3. Read [docs/architecture/threat-model.md](./docs/architecture/threat-model.md)
   for the trust boundaries your change must respect.

If your change affects a public contract, compatibility row, security
boundary, schema, required check, or publication, open an issue first to
confirm the maintainer is willing to accept it before doing significant work.

## Development setup

No special toolchain is required for static contract checks:

```sh
./tests/contracts.sh
```

Local image builds require either Docker (with Buildx) or rootless Podman:

```sh
./scripts/build-base.sh load      # Docker, native image
./scripts/build-base-podman.sh    # rootless Podman
```

See [docs/quick-start.md](./docs/quick-start.md) for the guided path.

## Developer Certificate of Origin

Every commit must include a `Signed-off-by:` line certifying that you have
the right to contribute it under the project license. The full text is at
<https://developercertificate.org/>:

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that (a) the
contribution was created in whole or in part by me and I have the right to
submit it under the open source license indicated in the file; or (b) the
contribution is based upon previous work that, to my knowledge, is covered
under an appropriate open source license and I have the right under that
license to submit that work with modifications, created and/or contributed
by me, unless the contribution is based upon an approved upstream project;
or (c) the contribution was provided directly to me by some other person
who certified (a), (b) or (c) and I have not modified it.

(d) I understand and agree that this project, its contributors, and the
maintainer will be free to use, copy, modify, and distribute the
contribution under the project license, and that I grant those rights to the
project, its contributors, and the maintainer. I represent that I am
legally able to grant these rights.
```

Git can add the trailer automatically:

```sh
git commit -s -m "your message"
```

The DCO GitHub Action checks every pull request; commits missing the trailer
are rejected. If you forget, amend the commit:

```sh
git commit --amend -s --no-edit
```

## Pull request checklist

- [ ] Commit message explains **why**, not just **what**.
- [ ] Every commit ends with `Signed-off-by: Your Name <your.email@example.com>`.
- [ ] `./tests/contracts.sh` passes locally.
- [ ] New behavior has corresponding test coverage in `tests/`.
- [ ] Docs updated if behavior, contract, or compatibility changes.
- [ ] No secrets, credentials, or machine-local paths added.
- [ ] No changes under `.cyclestone/` (it is private).

## Tests

Tests live in [tests/](./tests/). See [tests/README.md](./tests/README.md)
for the full list. The repository maintainer owns the required check set;
adding a new required check is a maintainer decision.

## Reporting issues

Use GitHub Issues for bugs and feature requests. For security-sensitive
reports, follow [SECURITY.md](./SECURITY.md) instead of opening a public issue.

## Code of conduct

Participation in this project is governed by [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).
By participating you accept its terms.