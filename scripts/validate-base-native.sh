#!/bin/sh
set -eu
# pipefail makes the child-image-inheritance tee pipeline (below) propagate the
# real exit status so a hidden failure cannot be masked by tee's success. dash
# (the Ubuntu /bin/sh) supports pipefail; SC3040 flags it as undefined in POSIX.
# shellcheck disable=SC3040
set -o pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
validation_id=${VALIDATION_ID:?set VALIDATION_ID to C1, C2, or C3}
platform=${VALIDATION_PLATFORM:?set VALIDATION_PLATFORM to linux/amd64 or linux/arm64}
evidence_dir=${EVIDENCE_DIR:-$repo_root/dist/evidence/$validation_id}

case "$validation_id:$platform" in
  C1:linux/amd64) expected_version=22.04; expected_machine=x86_64; expected_rootless=0 ;;
  C2:linux/amd64) expected_version=24.04; expected_machine=x86_64; expected_rootless=1 ;;
  C3:linux/arm64) expected_version=24.04; expected_machine=aarch64; expected_rootless=0 ;;
  *) echo "validate-base-native: unsupported validation target: $validation_id ($platform)" >&2; exit 64 ;;
esac

: "${IMAGE_VERSION:?set IMAGE_VERSION}"
: "${IMAGE_REVISION:?set IMAGE_REVISION}"
: "${IMAGE_CREATED:?set IMAGE_CREATED}"
: "${IMAGE_LICENSES:?set IMAGE_LICENSES}"

mkdir -p "$evidence_dir"
# shellcheck source=/dev/null
. /etc/os-release
test "${ID:-}" = ubuntu || { echo "FAIL: $validation_id requires Ubuntu" >&2; exit 1; }
test "${VERSION_ID:-}" = "$expected_version" \
  || { echo "FAIL: $validation_id requires Ubuntu $expected_version" >&2; exit 1; }
test "$(uname -m)" = "$expected_machine" \
  || { echo "FAIL: $validation_id requires $expected_machine" >&2; exit 1; }

security_options=$(docker info --format '{{json .SecurityOptions}}')
case "$expected_rootless:$security_options" in
  1:*rootless*) ;;
  1:*) echo "FAIL: $validation_id requires rootless Docker" >&2; exit 1 ;;
  0:*rootless*) echo "FAIL: $validation_id requires rootful Docker" >&2; exit 1 ;;
  0:*) ;;
esac

cached_image=cyclestone-base:validation-$(printf '%s' "$validation_id" | tr '[:upper:]' '[:lower:]')-cached
clean_image=cyclestone-base:validation-$(printf '%s' "$validation_id" | tr '[:upper:]' '[:lower:]')-clean

{
  printf 'validation_id=%s\nplatform=%s\n' "$validation_id" "$platform"
  uname -a
  sed -n '1,20p' /etc/os-release
  docker version
  docker info
  docker buildx inspect --bootstrap
} > "$evidence_dir/environment.txt"

PLATFORMS=$platform IMAGE_TAG=$cached_image "$repo_root/scripts/build-base.sh" load
PLATFORMS=$platform IMAGE_TAG=$clean_image BUILD_NO_CACHE=1 "$repo_root/scripts/build-base.sh" load

IMAGE=$cached_image IMAGE_NETWORK_TESTS=1 "$repo_root/tests/image-smoke.sh"
IMAGE=$cached_image COMPARE_IMAGE=$clean_image "$repo_root/tests/image-inspect.sh"

BASE_IMAGE=$cached_image PLATFORM=$platform \
  "$repo_root/tests/child-image-inheritance.sh" \
  2>&1 | tee "$evidence_dir/child-image-inheritance.txt"

docker run --rm --network none "$cached_image" sh -eu -c '
  test ! -e /root/.aws
  test ! -e /root/.config
  test ! -e /home/developer/.aws
  test ! -e /home/developer/.azure
  test ! -e /home/developer/.kube
  test ! -e /home/developer/.docker
  git init -q /workspace/provider-free
  cd /workspace/provider-free
  if printf "%s" ",${INSTALL_TOOLS:-}," | grep -q ",cyclestone,"; then
    cyclestone --version
    cyclestone --help >/dev/null
  fi
'

if test "$validation_id" = C2; then
  IMAGE=$cached_image "$repo_root/tests/rootless-bind-mount.sh"
fi

docker image inspect "$cached_image" > "$evidence_dir/image-inspect.json"
docker image inspect --format '{{.Id}} {{.RepoDigests}} size={{.Size}}' "$cached_image" \
  > "$evidence_dir/image-identity.txt"
docker run --rm --user 0 --entrypoint sh "$cached_image" -eu -c '
  if printf "%s" ",${INSTALL_TOOLS:-}," | grep -q ",cyclestone,"; then
    sha256sum /home/developer/.local/bin/cyclestone
    cyclestone --version
    file /home/developer/.local/bin/cyclestone
    ldd /home/developer/.local/bin/cyclestone 2>&1 || true
  fi
  dpkg-query -W -f="\${Package}\t\${Version}\n" | LC_ALL=C sort
' > "$evidence_dir/runtime-inventory.txt"

echo "PASS: native $validation_id validation ($platform)"
