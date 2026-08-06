#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
versions_file=$repo_root/examples/child-image/versions.env
test -r "$versions_file" || { echo "build-child-image: missing $versions_file" >&2; exit 1; }
# versions.env is reviewed repository data containing shell-safe scalars.
# shellcheck source=examples/child-image/versions.env
. "$versions_file"

platform=${PLATFORM:-linux/amd64}
case "$platform" in
  linux/amd64|linux/arm64) ;;
  *) echo "build-child-image: unsupported platform: $platform" >&2; exit 64 ;;
esac

: "${BASE_IMAGE_REF:?set BASE_IMAGE_REF to the canonical manifest digest or a local image ID}"
case "$BASE_IMAGE_REF" in
  ghcr.io/patrick-folster/cyclestone-dev-container-base@sha256:*)
    digest=${BASE_IMAGE_REF##*@sha256:}
    build_base=$BASE_IMAGE_REF
    pull_base=1
    ;;
  sha256:*)
    digest=${BASE_IMAGE_REF#sha256:}
    : "${LOCAL_BASE_IMAGE:?set LOCAL_BASE_IMAGE to the loaded tag resolving to BASE_IMAGE_REF}"
    local_id=$(docker image inspect --format '{{.Id}}' "$LOCAL_BASE_IMAGE" 2>/dev/null) \
      || { echo 'build-child-image: local base image locator is not loaded' >&2; exit 1; }
    test "$local_id" = "$BASE_IMAGE_REF" \
      || { echo 'build-child-image: local base image locator does not match BASE_IMAGE_REF' >&2; exit 1; }
    build_base=$LOCAL_BASE_IMAGE
    local_builder=default
    pull_base=0
    ;;
  *)
    echo 'build-child-image: BASE_IMAGE_REF must be the canonical GHCR manifest digest or a local sha256 image ID' >&2
    exit 64
    ;;
esac
printf '%s\n' "$digest" | grep -Eq '^[0-9a-f]{64}$' \
  || { echo 'build-child-image: base digest must be 64 lowercase hexadecimal characters' >&2; exit 64; }

for value in "$GO_AMD64_SHA256" "$GO_ARM64_SHA256"; do
  printf '%s\n' "$value" | grep -Eq '^[0-9a-f]{64}$' \
    || { echo 'build-child-image: malformed Go archive SHA-256' >&2; exit 64; }
done

image_tag=${IMAGE_TAG:-cyclestone-child:inheritance}
set -- docker buildx build --provenance=false --load
test "$pull_base" -eq 1 || set -- "$@" --builder "$local_builder"
test "$pull_base" -eq 0 || set -- "$@" --pull
set -- "$@" \
  --file "$repo_root/examples/child-image/Containerfile" \
  --platform "$platform" \
  --build-arg "BASE_IMAGE_REF=$build_base" \
  --build-arg "GO_VERSION=$GO_VERSION" \
  --build-arg "GO_BASE_URL=$GO_BASE_URL" \
  --build-arg "GO_AMD64_ARCHIVE=$GO_AMD64_ARCHIVE" \
  --build-arg "GO_AMD64_SHA256=$GO_AMD64_SHA256" \
  --build-arg "GO_ARM64_ARCHIVE=$GO_ARM64_ARCHIVE" \
  --build-arg "GO_ARM64_SHA256=$GO_ARM64_SHA256" \
  --tag "$image_tag" "$repo_root"
exec "$@"
