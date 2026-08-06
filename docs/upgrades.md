# Image-Contract Upgrades

This page covers how to upgrade the base image, SDK pins, provider registry,
and Dev Container template while preserving the public contract. Every change
that affects consumers requires maintainer review, migration notes, and the
Semantic Versioning classification in
[architecture/versioning.md](architecture/versioning.md).

## Base image digest migration

The base image pins a reviewed multi-architecture Ubuntu 24.04 OCI index digest
with separate amd64 and arm64 manifest digests in `images/base/versions.env`.
To update the base:

1. Obtain the new Ubuntu 24.04 index digest and platform manifest digests from
   the Docker Official Image.
2. Verify both `linux/amd64` and `linux/arm64` manifests are present.
3. Update `BASE_IMAGE`, `BASE_AMD64_MANIFEST`, and `BASE_ARM64_MANIFEST` in
   `images/base/versions.env`.
4. Run the full native C1-C3 matrix build, package-closure, size, and
   compatibility validation.
5. Update architectural decision D-010 with the replacement index and platform
   evidence.
6. Classify the change: a base refresh within the same LTS is a patch or minor
   bump; a distribution or LTS move is a major change.

```sh
# Verify the new base contains both supported platforms
docker manifest inspect ubuntu:24.04@sha256:<new-index-digest>
```

## SDK version bumps

Each SDK example pins its download URL, version, architecture-specific archive
names, and publisher checksum in its `versions.env`. To update an SDK:

1. Download the publisher checksum document for the new version.
2. Verify the checksums for both `linux/amd64` and `linux/arm64`.
3. Update the version, archive names, and checksums in the example's
   `versions.env`.
4. Update the corresponding `.devcontainer/devcontainer.json` build args.
5. Run the example build and contract validation on both native architectures.

### Go

Go publishes SHA-256 checksums at `https://go.dev/dl/SHASUMS256`:

```sh
curl -fsSL https://go.dev/dl/SHASUMS256 | grep 'go<VERSION>.linux-'
```

### Node.js

Node.js publishes SHA-256 checksums in the release directory:

```sh
curl -fsSL https://nodejs.org/dist/v<VERSION>/SHASUMS256.txt | grep 'linux-'
```

### .NET

.NET publishes SHA-512 checksums in the release metadata:

```sh
curl -fsSL https://dotnetcli.azureedge.net/dotnet/release-metadata/8.0/releases.json \
  | jq '.releases[] | select(.release-version=="<VERSION>") | .sdk'
```

.NET uses `sha512sum --check --strict` instead of `sha256sum` because the
publisher's native checksum format is SHA-512.

## Provider registry changes

The trusted registry (`providers/registry.json`) is repository-owned
reviewed code. Expansion requires:

1. Maintainer security review of the new provider definition.
2. Schema and hostile fixture updates in `tests/fixtures/providers/`.
3. Snapshot review in `tests/fixtures/providers/snapshots/`.
4. A `providers/CHANGELOG.md` entry.
5. Release classification under the version policy.

Existing provider definitions, adapter metadata, source paths, destinations,
environment names, and endpoints are frozen. Changing any of these invalidates
existing authorization grants (exact-plan matching) and may require a plan
version migration.

## Template updates

The project Dev Container template
(`templates/project-devcontainer/.devcontainer/`) is a reviewed structural input
for runtime generation. Privilege-bearing fields (`privileged`,
`updateRemoteUserUID`, `runArgs`, `mounts`) cannot be overridden through
provider input. To update the template:

1. Preserve all contract fields verified by `tests/contracts.sh`.
2. Update `templates/README.md` to document the change.
3. Run `tests/contracts.sh` and `tests/devcontainer-podman.sh` on both identity
   cases.

## Deprecation handling

Deprecated inherited elements remain for all later minors in a major line.
Incompatible removal waits for a major release except under the existing urgent
security process. A deprecation must be:

1. Documented in the relevant doc page and `providers/CHANGELOG.md`.
2. Accompanied by a replacement or migration path.
3. Classified as a minor (deprecation) or major (removal) version change.

## Version classification

The highest applicable OS/tool/provider/template/contract or security
classification determines the image version. See
[architecture/versioning.md](architecture/versioning.md) for the complete
category list and [architecture/compatibility.md](architecture/compatibility.md)
for the supported matrix.

## Provenance verification

Release images include SBOM and SLSA build provenance. After a release is
published, consumers can verify:

```sh
# Verify build provenance (requires cosign or gh attestation)
gh attestation verify <image> --owner patrick-folster
```

See [base-image.md](base-image.md) for local build and inspection, and
[architecture/release-reproduction.md](architecture/release-reproduction.md)
for provenance verification details.
