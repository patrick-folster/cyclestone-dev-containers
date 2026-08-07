#!/bin/sh
# Scripts to build a local/offline-friendly base image.
# Sets defaults for all metadata requirements and tags the resulting image
# as localhost/cyclestone-base:local (the default BASE_IMAGE_REF).
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
versions_file=$repo_root/images/base/versions.env
test -r "$versions_file" || { echo "build-base-local: missing $versions_file" >&2; exit 1; }
# shellcheck source=images/base/versions.env
. "$versions_file"

# Auto-detect or default metadata variables
IMAGE_VERSION=${IMAGE_VERSION:-1.0.0-local}
IMAGE_REVISION=${IMAGE_REVISION:-$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo "0000000000000000000000000000000000000000")}
IMAGE_CREATED=${IMAGE_CREATED:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}
IMAGE_LICENSES=${IMAGE_LICENSES:-MIT}

# Default settings for local/offline dev builds
IMAGE_TAG=${IMAGE_TAG:-localhost/cyclestone-base:local}
PULL_POLICY=${PULL_POLICY:-missing} # default to 'missing' for offline/local resilience

# Determine container engine
if command -v podman >/dev/null 2>&1; then
  engine=podman
elif command -v docker >/dev/null 2>&1; then
  engine=docker
else
  echo "build-base-local: neither podman nor docker was found on PATH" >&2
  exit 1
fi

# Configure pull argument based on engine support
pull_arg=
if [ "$engine" = "podman" ]; then
  pull_arg="--pull=$PULL_POLICY"
else
  if [ "$PULL_POLICY" = "always" ]; then
    pull_arg="--pull"
  fi
fi

echo "Building local base image using $engine..."
echo "  Tag:      $IMAGE_TAG"
echo "  Pull:     $PULL_POLICY"
echo "  Version:  $IMAGE_VERSION"
echo "  Revision: $IMAGE_REVISION"
echo "  Created:  $IMAGE_CREATED"

# Build arguments and execution
set -- $engine build $pull_arg \
  --file "$repo_root/images/base/Containerfile" \
  --tag "$IMAGE_TAG" \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "BASE_DIGEST=$BASE_DIGEST" \
  --build-arg "TARGETOS=linux" \
  --build-arg "TARGETARCH=amd64" \
  --build-arg "INSTALL_TOOLS=${INSTALL_TOOLS:-}" \
  --build-arg "DEVELOPER_UID=1000" \
  --build-arg "DEVELOPER_GID=1000" \
  --build-arg "IMAGE_TITLE=Cyclestone Development Base (Local)" \
  --build-arg "IMAGE_DESCRIPTION=Local development base image" \
  --build-arg "IMAGE_SOURCE=local" \
  --build-arg "IMAGE_URL=local" \
  --build-arg "IMAGE_DOCUMENTATION=local" \
  --build-arg "IMAGE_LICENSES=$IMAGE_LICENSES" \
  --build-arg "IMAGE_VERSION=$IMAGE_VERSION" \
  --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
  --build-arg "IMAGE_CREATED=$IMAGE_CREATED"

set -- "$@" "$repo_root"
exec "$@"
