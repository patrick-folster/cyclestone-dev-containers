#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
versions_file=$repo_root/images/base/versions.env
test -r "$versions_file" || { echo "build-base: missing $versions_file" >&2; exit 1; }
# versions.env is repository-controlled data containing only shell-safe scalars.
# shellcheck source=images/base/versions.env
. "$versions_file"

mode=${1:-load}
case "$mode" in
  load) default_platforms=linux/amd64 ;;
  oci) default_platforms=linux/amd64,linux/arm64 ;;
  *) echo "usage: $0 [load|oci]" >&2; exit 64 ;;
esac

platforms=${PLATFORMS:-$default_platforms}
case "$platforms" in
  linux/amd64|linux/arm64) ;;
  linux/amd64,linux/arm64|linux/arm64,linux/amd64)
    test "$mode" = oci || { echo 'build-base: load mode accepts one platform' >&2; exit 64; }
    ;;
  *) echo "build-base: unsupported platform selection: $platforms" >&2; exit 64 ;;
esac

: "${IMAGE_VERSION:?set IMAGE_VERSION to MAJOR.MINOR.PATCH}"
: "${IMAGE_REVISION:?set IMAGE_REVISION to a 40-character Git commit}"
: "${IMAGE_CREATED:?set IMAGE_CREATED to an RFC 3339 UTC timestamp}"
: "${IMAGE_LICENSES:?set IMAGE_LICENSES to the reviewed whole-image license expression}"
printf '%s\n' "$IMAGE_VERSION" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' \
  || { echo 'build-base: IMAGE_VERSION is not Semantic Versioning' >&2; exit 64; }
printf '%s\n' "$IMAGE_REVISION" | grep -Eq '^[0-9a-f]{40}$' \
  || { echo 'build-base: IMAGE_REVISION must be a lowercase 40-character Git commit' >&2; exit 64; }
printf '%s\n' "$IMAGE_CREATED" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
  || { echo 'build-base: IMAGE_CREATED must be RFC 3339 UTC (YYYY-MM-DDTHH:MM:SSZ)' >&2; exit 64; }
printf '%s\n' "$IMAGE_LICENSES" | grep -Eq '^[A-Za-z0-9._+():/ -]+$' \
  || { echo 'build-base: IMAGE_LICENSES contains unsupported characters' >&2; exit 64; }

image_source=https://github.com/patrick-folster/cyclestone-dev-containers
image_url=https://github.com/patrick-folster/cyclestone-dev-containers/pkgs/container/cyclestone-dev-container-base
image_documentation=$image_source/blob/$IMAGE_REVISION/docs/base-image.md
image_title='Cyclestone Development Base'
image_description='Provider-free non-root Cyclestone development base image'
image_tag=${IMAGE_TAG:-cyclestone-base:$IMAGE_VERSION}

set -- docker buildx build --pull --provenance=false \
  --file "$repo_root/images/base/Containerfile" \
  --platform "$platforms" \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "BASE_DIGEST=$BASE_DIGEST" \
  --build-arg "INSTALL_TOOLS=${INSTALL_TOOLS:-${INSTALL_TOOLS_DEFAULT:-}}" \
  --build-arg "DEVELOPER_UID=${DEVELOPER_UID:-1000}" \
  --build-arg "DEVELOPER_GID=${DEVELOPER_GID:-1000}" \
  --build-arg "IMAGE_TITLE=$image_title" \
  --build-arg "IMAGE_DESCRIPTION=$image_description" \
  --build-arg "IMAGE_SOURCE=$image_source" \
  --build-arg "IMAGE_URL=$image_url" \
  --build-arg "IMAGE_DOCUMENTATION=$image_documentation" \
  --build-arg "IMAGE_LICENSES=$IMAGE_LICENSES" \
  --build-arg "IMAGE_VERSION=$IMAGE_VERSION" \
  --build-arg "IMAGE_REVISION=$IMAGE_REVISION" \
  --build-arg "IMAGE_CREATED=$IMAGE_CREATED"

case "${BUILD_NO_CACHE:-0}" in
  0) ;;
  1) set -- "$@" --no-cache ;;
  *) echo 'build-base: BUILD_NO_CACHE must be 0 or 1' >&2; exit 64 ;;
esac

case "$mode" in
  load) set -- "$@" --load --tag "$image_tag" ;;
  oci)
    oci_output=${OCI_OUTPUT:-$repo_root/dist/cyclestone-base-$IMAGE_VERSION.oci.tar}
    mkdir -p "$(dirname -- "$oci_output")"
    set -- "$@" --output "type=oci,dest=$oci_output"
    ;;
esac

set -- "$@" "$repo_root"
exec "$@"
