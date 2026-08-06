# Quick Start

This guide gets a project running with the Cyclestone development container
foundation in minutes. Each section links to the detailed guide for the topic.

## 1. Build the base image

The base image is non-provider and non-root. Build it locally (no push):

```sh
./scripts/build-base.sh
```

See [base-image.md](base-image.md) for build options, platforms, and
inspection.

## 2. Extend with a project SDK

Copy an SDK example's `Containerfile` and `versions.env` into the project, or
build an example directly:

| Runtime | Example | Build command |
| --- | --- | --- |
| Go | `examples/child-image/` | `BASE_IMAGE_REF=<digest> ./scripts/build-child-image.sh` |
| Node.js | `examples/nodejs/` | See below |
| .NET | `examples/dotnet/` | See below |

The examples pin checksum-verified SDK downloads for both `linux/amd64` and
`linux/arm64`. They never `COPY` or `ADD` project source. See
[child-images.md](child-images.md) for the inheritance contract.

### Building a non-Go child image

The `build-child-image.sh` wrapper is Go-specific. For Node.js or .NET, use
`docker buildx build` or `podman build` directly with the example Containerfile
and its `versions.env`:

```sh
. examples/nodejs/versions.env
docker buildx build --load \
  --file examples/nodejs/Containerfile \
  --build-arg BASE_IMAGE_REF=<digest> \
  --build-arg NODE_VERSION=$NODE_VERSION \
  --build-arg NODE_BASE_URL=$NODE_BASE_URL \
  --build-arg NODE_AMD64_ARCHIVE=$NODE_AMD64_ARCHIVE \
  --build-arg NODE_AMD64_SHA256=$NODE_AMD64_SHA256 \
  --build-arg NODE_ARM64_ARCHIVE=$NODE_ARM64_ARCHIVE \
  --build-arg NODE_ARM64_SHA256=$NODE_ARM64_SHA256 \
  --tag my-project-node:local .
```

## 3. Run with the project Dev Container template

Copy `templates/project-devcontainer/.devcontainer/` into the project root and
supply the canonical base manifest digest:

```sh
export CYCLESTONE_BASE_IMAGE_REF='ghcr.io/patrick-folster/cyclestone-dev-container-base@sha256:<reviewed-manifest-digest>'
devcontainer --docker-path podman up --workspace-folder "$PWD"
```

The template mounts the repository at `/workspace`, uses
`keep-id:uid=1000,gid=1000`, disables `updateRemoteUserUID`, and applies
`no-new-privileges`. See [devcontainers.md](devcontainers.md) for the full
workflow.

## 4. Request a provider (optional)

Provider access is value-free and requires explicit local authorization.

```sh
# Create a providers.json in the project root
cat > providers.json << 'JSON'
{ "version": 1, "providers": { "codex": { "enabled": true, "mode": "read-write" } } }
JSON

# Review and authorize (requires a controlling terminal)
scripts/devcontainer-permissions.sh review "$PWD" providers.json codex linux
scripts/devcontainer-permissions.sh authorize "$PWD" providers.json codex linux

# Generate and validate the runtime configuration
scripts/devcontainer-generate.sh "$PWD" providers.json
scripts/devcontainer-validate.sh "$PWD" providers.json
```

See [providers.md](providers.md) for the registry,
[provider-authorization.md](provider-authorization.md) for consent, and
[provider-credentials.md](provider-credentials.md) for materialization.

## 5. Validate locally

Run the dependency-free contract checks:

```sh
./tests/contracts.sh
```

Validate documentation commands:

```sh
./scripts/validate-docs.sh
```

Finish the templates-and-examples milestone locally:

```sh
./scripts/validate-milestone-local.sh ms-pf-0014
```

## Where to go next

- [child-images.md](child-images.md) — extending the base image
- [devcontainers.md](devcontainers.md) — project Dev Container workflow
- [workspace-identity.md](workspace-identity.md) — UID/GID mapping modes
- [ollama.md](ollama.md) — Ollama host service setup
- [selinux.md](selinux.md) — Fedora SELinux configuration
- [upgrades.md](upgrades.md) — image and SDK upgrade steps
- [troubleshooting.md](troubleshooting.md) — common failure modes
