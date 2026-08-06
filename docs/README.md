# Documentation

Owns user guidance and architecture contracts. Document authors own accuracy;
`@patrick-folster` approves architectural and public-contract changes. Normative
foundation documents live in `architecture/`, while chronological decisions live
in `.cyclestone/DECISIONS.md`.

## Quick start

Start with the [quick-start guide](quick-start.md) for a guided path from base
build to running project Dev Container with optional providers.

## User guides

| Guide | Topic |
| --- | --- |
| [base-image.md](base-image.md) | Build, test, inspect, update, and operate the non-provider base |
| [child-images.md](child-images.md) | Extend the base with a checksum-pinned SDK |
| [devcontainers.md](devcontainers.md) | Project Dev Container template, rootless Podman CLI, lifecycle, cache |
| [workspace-identity.md](workspace-identity.md) | Dev Container and Podman UID/GID ownership modes |
| [providers.md](providers.md) | Project request syntax, trusted registry, resolver plans |
| [provider-authorization.md](provider-authorization.md) | Local approval, identity, grants, revocation |
| [provider-credentials.md](provider-credentials.md) | Rootless-Podman materialization, adapters, refresh, revocation |
| [runtime-configuration.md](runtime-configuration.md) | Deterministic generated/local Dev Container configuration |
| [ollama.md](ollama.md) | Ollama host-service setup with GPU and CPU |
| [selinux.md](selinux.md) | Fedora SELinux configuration for rootless Podman |
| [upgrades.md](upgrades.md) | Image, SDK, provider, and template upgrade steps |
| [troubleshooting.md](troubleshooting.md) | Common failure modes and solutions |

## Architecture references

| Document | Topic |
| --- | --- |
| [architecture/repository-layout.md](architecture/repository-layout.md) | Repository and image identity |
| [architecture/image-contract.md](architecture/image-contract.md) | Filesystem, process, and metadata contract |
| [architecture/cyclestone-acquisition.md](architecture/cyclestone-acquisition.md) | Pinned Cyclestone acquisition |
| [architecture/compatibility.md](architecture/compatibility.md) | Supported platform matrix |
| [architecture/versioning.md](architecture/versioning.md) | Semantic versioning policy |
| [architecture/threat-model.md](architecture/threat-model.md) | Trust posture and threat model |
| [architecture/mvp.md](architecture/mvp.md) | MVP boundary |
| [architecture/validation-checklist.md](architecture/validation-checklist.md) | Validation checklist |
| [architecture/release-reproduction.md](architecture/release-reproduction.md) | Provenance and release reproduction |

## Examples

See [examples/README.md](../examples/README.md) for the five example projects:
Go, Node.js/TypeScript, .NET, Codex, and Ollama.

## Templates

See [templates/README.md](../templates/README.md) for the reusable project Dev
Container template.
