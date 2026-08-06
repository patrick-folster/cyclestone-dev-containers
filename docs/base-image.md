# Base Image Build and Operations

The sole image definition is `images/base/Containerfile`. It builds Ubuntu 24.04
from the reviewed multi-architecture index digest in `images/base/versions.env`
and installs the `INSTALL_TOOLS` build-arg-selected toolset via the uniform
native installer `scripts/install-tools.sh`. All tools are opt-in; an empty
`INSTALL_TOOLS` produces a valid empty-toolset base image. The final process is
non-root `developer` in `/workspace`.

## Contents

`images/base/packages.txt` is the reviewed direct-package allow-list. It supplies
Bash; Git; the OpenSSH client; CA certificates; `curl`; `tar`, gzip, unzip, and
xz archive support; `rg` search; `jq` structured-data inspection; `file` binary
inspection; `less`; and `ps`/process inspection. Automated inspection records
the full transitive `dpkg` closure rather than treating the direct list as the
complete image. The build copies the allow-list into the non-final acquisition
stage and mounts it from that stage while installing final-image packages. This
keeps the file out of every final-image layer and avoids depending on
host-source SELinux labels for a build-time bind mount.

Ubuntu's `git` package has a hard dependency on Perl and installs `perl`,
`perl-base`, `perl-modules-*`, `libperl*`, and `liberror-perl`. This is the sole
reviewed language-runtime exception and exists to satisfy the milestone's required
Git client. Inspection fails if the Perl closure expands beyond that bounded set.

The image intentionally has no sudo or privilege escalation, language SDK or
project runtime beyond the documented Git/Perl dependency, service, daemon
socket, credential, project content, personal configuration, or publication
behavior. A host mount does not become safe merely because the container is
non-root; ownership and access remain host/runtime concerns. Provider CLIs
(codex, agy, ollama, opencode) and Cyclestone are opt-in via `INSTALL_TOOLS`;
none are installed by default.

## Tool installation framework

`scripts/install-tools.sh` is the uniform native installer for all supported
tools. It runs at build time (staging ollama, the only system tool, into
`/out` via `DESTDIR`; user tools are installed as developer in the final
stage) and is shipped into the image at `/usr/local/bin/cyclestone-tools`
for runtime updates. See
[`cyclestone-acquisition.md`](architecture/cyclestone-acquisition.md) for
the per-tool acquisition sequences and verification levels.

### Build-time selection

Pass `INSTALL_TOOLS` as a comma-separated list to `scripts/build-base.sh`:

```sh
INSTALL_TOOLS=cyclestone,codex,agy,ollama,opencode ./scripts/build-base.sh load
```

System tools (cyclestone, codex, agy, ollama) install to `/usr/local/bin`.
OpenCode installs to `/home/developer/.opencode/bin` (installer default). PATH
covers both.

### Runtime updates

As the `developer` user:

```sh
cyclestone-tools status              # list installed tools + versions
cyclestone-tools update              # update all user-installable tools
cyclestone-tools update --tool codex # update one tool
cyclestone-tools install --tool agy  # install a tool not selected at build
```

Ollama runtime updates are not supported (system install requires root); rebuild
the image to update ollama.

## Local build

Docker Engine with Buildx is required. Supply deterministic release metadata;
the license annotation describes the complete Ubuntu-derived image, not only the
MIT-licensed Cyclestone binary. Until the maintainer approves a release-wide SPDX
expression, use the explicit local-only review marker shown below and do not use
that marker as publication evidence.

```sh
export IMAGE_VERSION=1.0.0
export IMAGE_REVISION="$(git rev-parse HEAD)"
export IMAGE_CREATED=2026-07-31T17:00:00Z
export IMAGE_LICENSES=LicenseRef-Container-Image-Review-Required
export IMAGE_TAG=cyclestone-base:1.0.0
./scripts/build-base.sh load
```

`load` defaults to `linux/amd64` and accepts exactly one of `linux/amd64` or
`linux/arm64`; set `PLATFORMS=linux/arm64` explicitly for the arm64 image. The
wrapper does not infer the host architecture. A cache-aware build uses BuildKit
cache mounts for apt. To prove a clean resolution, add `BUILD_NO_CACHE=1`.

Create a local two-platform OCI archive, without pushing:

```sh
export PLATFORMS=linux/amd64,linux/arm64
export OCI_OUTPUT="$PWD/dist/cyclestone-base-1.0.0.oci.tar"
./scripts/build-base.sh oci
tar -xOf "$OCI_OUTPUT" index.json | jq .
```

Build arguments and examples contain no credentials. Do not add tokens, secret
files, SSH forwarding, or registry credentials to this acquisition flow.

## Runtime and inspection

Discover the tool version through either supported mechanism:

```sh
docker run --rm cyclestone-base:1.0.0 cyclestone --version
docker run --rm cyclestone-base:1.0.0 sh -c 'printf "%s\n" "$CYCLESTONE_VERSION"'
```

Run deterministic tests and inspect OCI configuration:

```sh
./tests/contracts.sh
IMAGE=cyclestone-base:1.0.0 ./tests/image-smoke.sh
IMAGE=cyclestone-base:1.0.0 ./tests/image-inspect.sh
docker image inspect cyclestone-base:1.0.0 --format '{{json .Config.Labels}}' | jq .
docker image inspect cyclestone-base:1.0.0 --format \
  'user={{.Config.User}} workdir={{.Config.WorkingDir}} entrypoint={{json .Config.Entrypoint}} cmd={{json .Config.Cmd}}'
```

To inspect descriptor digests and every selected final-image layer in the
two-platform OCI output, run the archive audit once per platform:

```sh
IMAGE_ARCHIVE="$OCI_OUTPUT" IMAGE_PLATFORM=linux/amd64 ./tests/image-inspect.sh
IMAGE_ARCHIVE="$OCI_OUTPUT" IMAGE_PLATFORM=linux/arm64 ./tests/image-inspect.sh
```

The archive audit supports both classic Docker `manifest.json` archives and OCI
index/blob layouts. It fails closed on zero, missing, extra, corrupt, or
unreadable selected layers and checks each referenced historical layer for
credentials, personal/project content, caches, temporary/build artifacts, and
forbidden runtimes. Because OCI descriptors are content-addressed, multiple
stack positions may legitimately reference the same blob; every occurrence is
audited against its corresponding positional diff ID rather than deduplicated.

Set `IMAGE_NETWORK_TESTS=1` for the smoke test to exercise an actual HTTPS and CA
validation path. The normal smoke test remains deterministic and offline after
the image is loaded.

To compare two builds made with identical metadata:

```sh
IMAGE_TAG=cyclestone-base:rebuild-a ./scripts/build-base.sh load
IMAGE_TAG=cyclestone-base:rebuild-b BUILD_NO_CACHE=1 ./scripts/build-base.sh load
IMAGE=cyclestone-base:rebuild-a COMPARE_IMAGE=cyclestone-base:rebuild-b \
  ./tests/image-inspect.sh
```

The comparison normalizes and checks the Cyclestone binary digest/version,
sorted package inventory, contract path owner/mode, environment, user, workdir,
entrypoint, command, and labels. Creation time and revision are caller-controlled;
use the same values when testing equivalence.

## Platforms and release validation

Native C1–C3 cover the image runtime on Ubuntu 22.04/24.04 and amd64/arm64.
C4 additionally supports the pinned Dev Container CLI with rootful Docker on
Ubuntu 24.04 amd64; C5 supports direct rootless Podman 4.9 with crun on that same
host. See `docs/workspace-identity.md` for their deliberately separate commands.
Other combinations of hosts, architectures, distributions, clients/runtimes,
Cyclestone versions, and provider-enabled variants are unsupported. C6's
documented native-Linux host allowance is limited to its rootless-Podman V8
workflow and does not broaden C1–C5.

A cross-build or QEMU run checks mechanics but cannot replace V1–V3 native
evidence. Release validation also requires V4's non-provider behavior and the
V5–V7 workspace-identity checks. Run the smoke and inspection scripts natively
on both architectures; record `file`, `ldd`, package closure, image size, and
manifest digest output with the release evidence.

The manually dispatched `base-image-validation.yml` workflow maps C1, C2, and C3
to native GitHub-hosted runners, runs `validate-base-native.sh`, and retains each
row's logs and machine-readable evidence for 30 days. C2 installs and verifies a
rootless daemon before testing a host-owned bind mount. Rootless Docker maps the
host user to container UID 0 and maps `developer` through the user's subordinate
UID range, so the harness grants only that mapped UID a POSIX ACL; host ownership
does not change and image startup performs no `chown`. A separate native
workspace-identity job creates the deliberate host identity `2001:2002`; V5
checks the pinned client's UID/GID mutation and V6 checks Podman keep-id plus
supplementary GID `2003`. Both run V7's shared workspace/Git/HOME assertions and
retain `id`, ownership, mount, and namespace-map evidence. The optional
`run_multiarch` job requires the
`DOCKER_BUILD_CLOUD_ENDPOINT` repository variable and `DOCKERHUB_USERNAME` and
`DOCKERHUB_TOKEN` secrets. Those credentials authenticate the remote builder and
are never supplied as image build arguments or embedded in its output.

## Updating and reproducibility limits

The Ubuntu index digest and its amd64/arm64 manifest digests are review-controlled in
`versions.env`. Tool source URLs are documented constants, not immutable pins;
latest releases are resolved at build time via the GitHub releases API or
publisher installers. This makes tool installs non-reproducible by design;
resolved versions must be recorded in release evidence per build. For a base
update, inspect the index and both target manifests, update all three base
digests together, run clean native builds and the full matrix, review
package/size changes, and append the decision record.

The base digest is immutable. Ubuntu apt repositories are not snapshotted, so
resolved package versions may drift between builds; security rebuilds
deliberately consume current repository metadata. Consequently the contract
promises functional equivalence under normalized inspection, not byte-for-byte
image identity. A stronger claim requires a separately reviewed apt snapshot
policy. Tool installs add further non-reproducibility: the latest v-tag and
publisher installer outputs may change between builds.

All contract directories are created and owned at build time. They are ephemeral
unless explicitly mounted; image startup never reads project files, mounts host
paths, changes UID/GID, or recursively changes ownership. The supported C4 client
may change numeric IDs before startup; C5 maps them in the user namespace.
Consumers needing runtimes, providers, templates, orchestration, credentials, or
services must add and review those capabilities in a child image or later
milestone.
