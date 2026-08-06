# Extending the Cyclestone Base Image

Project-specific images may add an SDK, build packages, or project tools while
preserving the base image's public contract. The executable Go example is in
`examples/child-image/`; it installs no project source and is validated on every
native C1-C3 architecture.

## Pin the base and dependencies

Use a full canonical registry reference with a reviewed manifest digest:

```sh
BASE_IMAGE_REF='ghcr.io/patrick-folster/cyclestone-dev-container-base@sha256:<reviewed-manifest-digest>' \
PLATFORM=linux/amd64 IMAGE_TAG=my-project-dev:local \
  ./scripts/build-child-image.sh
```

The placeholder is intentionally not buildable. This repository has not
published or recorded a Cyclestone 1.x manifest digest, so consumers must supply
one from a reviewed release. Native repository validation instead uses the
loaded base's content-addressed Docker image ID as its trust identity and its
loaded tag only as a BuildKit locator. The wrapper proves the locator resolves to
that exact ID before building, then explicitly uses Buildx's context-backed
`default` builder so the verified daemon-store image is visible even when a
`docker-container` builder is currently selected. Canonical registry-digest
builds continue to use the selected builder and pull the pinned reference. An
image ID is local test input, not a pullable registry manifest digest.

The example pins Go's HTTPS download URL, version, architecture-specific archive
names, and publisher SHA-256 values in `examples/child-image/versions.env`. The
build selects only `linux/amd64` or `linux/arm64`, verifies the checksum before
extraction, and fails closed for every missing or unknown mapping. Updates must
review the publisher evidence, license, transitive dependencies, and both native
architectures. If an extension uses `apt`, pin or otherwise review its trusted
package source, use `--no-install-recommends` where appropriate, and remove apt
lists and package caches in the same layer. Never pipe an unverified installer
from the network into a shell.

## Preserve the inherited contract

Usually safe additions are SDKs, distribution packages, project tools, and
accurate child OCI labels. They remain safe only when their package sources and
new trust boundaries are documented and they do not introduce credentials,
automatic mounts, privilege, or unsupported platform claims. Root may be used
only during installation; the final image restores `USER developer` and
`WORKDIR /workspace`.

The following are public-contract changes and require maintainer compatibility
review, migration notes, and the Semantic Versioning classification in
`architecture/versioning.md`:

- changing the `developer` name, UID/GID behavior, or final `USER`;
- changing `HOME`, XDG paths, or Cyclestone configuration/data paths;
- removing or shadowing the `cyclestone` command;
- changing `WORKDIR`, the `/workspace` mount/write semantics, or startup access;
- replacing `ENTRYPOINT` or `CMD`, including loss of PID-1 `exec` and signal
  forwarding;
- adding credentials, implicit host mounts, daemon sockets, privilege, or broader
  supported-platform claims.

If a child must change one of these, document old and new behavior, affected
consumers, rollback and migration steps, and the required image-version impact.
An incompatible change is not a compatible Cyclestone 1.x child.

## Mount source at runtime

Mount the working tree into `/workspace` through the selected supported runtime
identity mode. Do not `COPY` or `ADD` it in the normal development image. Copying
source creates stale code and larger layers, can capture ignored files or
secrets, and turns a live host/runtime-owned workspace into a baked artifact.
The image should contain tools; the runtime mount supplies the current project.

## Validation

Static checks require no daemon or network:

```sh
./tests/contracts.sh
```

For a loaded native base, build and exercise the child directly:

```sh
BASE_IMAGE=cyclestone-base:1.0.0 PLATFORM=linux/amd64 \
  ./tests/child-image-inheritance.sh
```

Use `linux/arm64` only on a native arm64 host. The manually dispatched
`base-image-validation.yml` workflow runs the child fixture in C1 and C2 on
native amd64 and C3 on native arm64, retaining child evidence with each row.
Cross-build or QEMU-only success is diagnostic and is not release evidence.
