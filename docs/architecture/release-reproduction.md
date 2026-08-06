# Release Reproduction and Provenance Verification

This guide explains how to reproduce image builds locally and verify the authenticity and build provenance of published images.

## 1. Local Image Build Reproduction

To build the development base image locally and replicate the release environment:

1. **Check out the release tag or commit:**
   ```bash
   git checkout v0.0.1
   ```

2. **Verify pinned dependencies:**
   Inspect [versions.env](../../images/base/versions.env) to check the pinned base image digest and tool source URL constants.
   Tool versions are resolved at build time to the latest v-tag or publisher release; they are not pre-pinned. Record the resolved versions in release evidence per build.

3. **Compile the image locally:**
   Run the build script to load the image into the local Docker daemon:
   ```bash
   ./scripts/build-base.sh load
   ```
   *Note: Set `IMAGE_VERSION` and `IMAGE_REVISION` to match your target revision.*
   ```bash
   export IMAGE_VERSION=1.0.0
   export IMAGE_REVISION=$(git rev-parse HEAD)
   export IMAGE_CREATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
   export IMAGE_LICENSES="LicenseRef-Container-Image-Review-Required"
   
   ./scripts/build-base.sh load
   ```

4. **Verify multi-architecture OCI archive:**
   To build for both `amd64` and `arm64` platform architectures and generate an OCI tarball:
   ```bash
   export PLATFORMS=linux/amd64,linux/arm64
   ./scripts/build-base.sh oci
   ```

---

## 2. Verifying Provenance and Attestations

All container images pushed to GitHub Container Registry (GHCR) include cryptographically signed build provenance and SBOM attestations. You can verify these details using the GitHub CLI (`gh`).

### Verify Build Attestations
To verify that the container image was built via the canonical GitHub Actions workflow and has not been tampered with, run:

```bash
gh attestation verify ghcr.io/patrick-folster/cyclestone-dev-container-base@sha256:<IMAGE_DIGEST> \
  --owner patrick-folster
```

This verification ensures:
* The image was built in the trusted GitHub Actions environment.
* The image revision matches the canonical repository.
* The builder identity and workflow files are authentic.

### Inspect the SBOM (Software Bill of Materials)
To retrieve the attested Software Bill of Materials containing the list of installed OS packages, dependencies, and tools:

```bash
gh attestation verify ghcr.io/patrick-folster/cyclestone-dev-container-base@sha256:<IMAGE_DIGEST> \
  --owner patrick-folster \
  --format json
```
This prints the full signed attestation details, including the embedded SBOM references and provenance details.
