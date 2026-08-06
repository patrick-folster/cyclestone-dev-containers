#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
versions_file=$repo_root/images/base/versions.env
test -r "$versions_file" || { echo "build-base-podman: missing $versions_file" >&2; exit 1; }
# versions.env is repository-controlled data containing only shell-safe scalars.
# shellcheck source=images/base/versions.env
. "$versions_file"

fail() {
  echo "build-base-podman: $*" >&2
  exit 1
}

command -v podman >/dev/null 2>&1 || fail 'Podman is unavailable'
test "$(id -u)" -ne 0 || fail 'the Podman build must run as a non-root user'
test "$(podman info --format '{{.Host.Security.Rootless}}')" = true \
  || fail 'Podman is not rootless'

: "${IMAGE_VERSION:?set IMAGE_VERSION to MAJOR.MINOR.PATCH}"
: "${IMAGE_REVISION:?set IMAGE_REVISION to a 40-character Git commit}"
: "${IMAGE_CREATED:?set IMAGE_CREATED to an RFC 3339 UTC timestamp}"
: "${IMAGE_LICENSES:?set IMAGE_LICENSES to the reviewed whole-image license expression}"
printf '%s\n' "$IMAGE_VERSION" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' \
  || fail 'IMAGE_VERSION is not Semantic Versioning'
printf '%s\n' "$IMAGE_REVISION" | grep -Eq '^[0-9a-f]{40}$' \
  || fail 'IMAGE_REVISION must be a lowercase 40-character Git commit'
printf '%s\n' "$IMAGE_CREATED" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
  || fail 'IMAGE_CREATED must be RFC 3339 UTC (YYYY-MM-DDTHH:MM:SSZ)'
printf '%s\n' "$IMAGE_LICENSES" | grep -Eq '^[A-Za-z0-9._+():/ -]+$' \
  || fail 'IMAGE_LICENSES contains unsupported characters'

image_source=https://github.com/patrick-folster/cyclestone-dev-containers
image_url=https://github.com/patrick-folster/cyclestone-dev-containers/pkgs/container/cyclestone-dev-container-base
image_documentation=$image_source/blob/$IMAGE_REVISION/docs/base-image.md
image_tag=${IMAGE_TAG:-cyclestone-base:local-validation}
iid_file=${IID_FILE:-$repo_root/dist/evidence/local/podman-base.iid}
mkdir -p "$(dirname -- "$iid_file")"

set -- podman build --pull=always --format oci \
  --file "$repo_root/images/base/Containerfile" \
  --iidfile "$iid_file" --tag "$image_tag" \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "BASE_DIGEST=$BASE_DIGEST" \
  --build-arg "TARGETOS=linux" \
  --build-arg "TARGETARCH=amd64" \
  --build-arg "INSTALL_TOOLS=${INSTALL_TOOLS:-${INSTALL_TOOLS_DEFAULT:-}}" \
  --build-arg "DEVELOPER_UID=1000" \
  --build-arg "DEVELOPER_GID=1000" \
  --build-arg "IMAGE_TITLE=Cyclestone Development Base" \
  --build-arg "IMAGE_DESCRIPTION=Toolset non-root Cyclestone development base image" \
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
  *) fail 'BUILD_NO_CACHE must be 0 or 1' ;;
esac
"$@" "$repo_root"

built_id=$(sed -n '1p' "$iid_file")
case "$built_id" in sha256:*) ;; *) built_id=sha256:$built_id ;; esac
resolved_id=$(podman image inspect --format '{{.Id}}' "$image_tag")
case "$resolved_id" in sha256:*) ;; *) resolved_id=sha256:$resolved_id ;; esac
test "$built_id" = "$resolved_id" || fail 'built tag does not resolve to the builder-reported image ID'
printf '%s\n' "$built_id" > "$iid_file"
echo "PASS: rootless Podman built $image_tag as $built_id"
