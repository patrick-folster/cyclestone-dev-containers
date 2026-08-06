# Base-Image Contract

This document is normative for image line `1.x`. “Must” identifies a stable
public guarantee, “may” an extension point, and “internal” a replaceable detail.

## Identity and execution

The final image must run as non-root user `developer`, default UID/GID `1000:1000`,
with `HOME=/home/developer` and `WORKDIR=/workspace`. Build arguments
`DEVELOPER_UID` and `DEVELOPER_GID` may select other positive numeric IDs when
building a derived image. The supported runtime translations are C4's pinned
Dev Container client mutation, C5's direct rootless Podman keep-id mapping, and
C6's pinned Dev Container client selecting that same Podman mapping while client
mutation is disabled. Client mutation and keep-id must not be combined. Every
mode preserves the username `developer`; the image entrypoint never mutates IDs
or ownership. Other clients, runtimes, and filesystem policies do not gain an
identity-translation promise.

The default entrypoint must perform only deterministic, credential-free setup,
must not evaluate workspace content, and must finish with `exec "$@"` so the
requested command becomes PID 1 and receives signals. With no command, the image
must start an interactive login-capable shell. It must not require privilege,
Docker/Podman sockets, or a host path. Internal helper locations and package
layout are not contractual.

## Public filesystem interface

All paths are absolute paths inside the container.

| Path | Creation and owner | Mutability/persistence | Mount expectation |
| --- | --- | --- | --- |
| `/home/developer` | Build time, `developer:developer` | Writable; ephemeral unless mounted | No mount required |
| `/workspace` | Build time, `developer:developer` | Writable; project data normally mounted | Optional bind/volume target |
| `/home/developer/.config` | Build time, `developer:developer` | Writable user configuration | Optional volume |
| `/home/developer/.cache` | Build time, `developer:developer` | Writable disposable cache | Optional volume |
| `/home/developer/.local/share` | Build time, `developer:developer` | Writable user data | Optional volume |
| `/home/developer/.config/cyclestone` | Build time, `developer:developer` | Writable Cyclestone configuration | Optional volume |
| `/home/developer/.local/share/cyclestone` | Build time, `developer:developer` | Writable Cyclestone state/data | Optional volume |

Every directory above must be searchable and writable by the effective
`developer` identity without `sudo`. A mounted directory's backing filesystem and
runtime policy may supersede image ownership; startup must fail clearly rather
than silently changing host ownership or escalating privilege. No other host path
is required. `/workspace` is the only documented project mount, and every mount
in the table is optional. A bind mount at `/workspace` replaces its image-level
directory, ownership, mode, and contents completely. Supported C4/C5 persistent
HOME volumes and C6's narrower Go-cache volume are mode-specific and retain
numeric ownership across restarts; they must not be shared across modes unless
their numeric compatibility is first verified.

## Environment variables

This table is exhaustive for line `1.x`. Explicit runtime values take precedence
over image defaults. Empty values are invalid for variables marked required.

| Variable | Image default | Meaning |
| --- | --- | --- |
| `HOME` | `/home/developer` | Required home directory; contract override rules apply |
| `XDG_CONFIG_HOME` | `/home/developer/.config` | Required user configuration root |
| `XDG_CACHE_HOME` | `/home/developer/.cache` | Required user cache root |
| `XDG_DATA_HOME` | `/home/developer/.local/share` | Required user data root |
| `CYCLESTONE_CONFIG_DIR` | `/home/developer/.config/cyclestone` | Cyclestone configuration root |
| `CYCLESTONE_DATA_DIR` | `/home/developer/.local/share/cyclestone` | Cyclestone state/data root |
| `INSTALL_TOOLS` | `` (empty) | Comma-separated list of build-arg-selected tools; informational |

No credential variable is defined by the base image. A future provider may
document narrowly scoped runtime environment variables, runtime secret files, or
credential-helper/agent sockets. Secrets must never be image defaults, build
arguments, OCI labels, or copied files. Variable expansion does not define new
contract paths; resolved path values must be absolute.

## Required OCI labels

Published images must set `org.opencontainers.image.title`,
`org.opencontainers.image.description`, `org.opencontainers.image.source`,
`org.opencontainers.image.url`, `org.opencontainers.image.documentation`,
`org.opencontainers.image.licenses`, `org.opencontainers.image.version`,
`org.opencontainers.image.revision`, `org.opencontainers.image.created`, and
`org.opencontainers.image.base.digest`. They must also set
`io.cyclestone.image.version=1.x.y` and `io.cyclestone.tools` (comma-separated
list of build-arg-selected tools; empty for an empty-toolset image).
`org.opencontainers.image.source` identifies the canonical repository, while
`org.opencontainers.image.version` is the independent immutable image release.
Dynamic values must be injected by trusted CI, never inferred from a workspace.

## Downstream extension rules

| Rule | Requirement |
| --- | --- |
| Allowed | Add runtimes, packages, OCI labels, provider definitions, and project tooling. |
| Required | Preserve non-root operation; restore `USER developer`; retain writable contract paths; preserve command `exec`/signal behavior; declare added credentials, mounts, and trust boundaries. |
| Conditional | Override `USER`, `WORKDIR`, `ENTRYPOINT`, `HOME`, or a contract directory only with an explicit compatibility declaration and appropriate image-version change. |
| Forbidden | Bake credentials into layers/metadata, silently expose host credentials, require privileged mode or broad runtime sockets, execute untrusted workspace content during startup, or claim absent matrix combinations. |

Every conditional override note must state the old and new behavior, affected
consumers, compatibility impact, migration instructions, and semantic-version
effect. An incompatible override belongs in a new major image line. Child images
may use root while installing packages but their final state must return to
`developer`; otherwise they are not compatible with this base contract.

The reviewed implementation pattern, dependency-pin requirements, safe additions,
and runtime source-mount workflow are documented in
[`../child-images.md`](../child-images.md). The inheritance validator treats the
identity, environment, Cyclestone command, workspace, entrypoint, command, and
PID-1 behavior above as one contract rather than independent optional checks.
