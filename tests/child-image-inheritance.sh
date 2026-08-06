#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
base_image=${BASE_IMAGE:?set BASE_IMAGE to a loaded base image}
platform=${PLATFORM:-linux/amd64}
child_image=${CHILD_IMAGE:-cyclestone-child:inheritance}

base_id=$(docker image inspect --format '{{.Id}}' "$base_image")
case "$base_id" in sha256:*) ;; *) echo 'FAIL: loaded base did not resolve to a content-addressed image ID' >&2; exit 1 ;; esac

BASE_IMAGE_REF=$base_id LOCAL_BASE_IMAGE=$base_image PLATFORM=$platform IMAGE_TAG=$child_image \
  "$repo_root/scripts/build-child-image.sh"
IMAGE=$child_image "$repo_root/tests/child-image-contract.sh"

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

# The cyclestone invalid-case is only meaningful when the base installed
# cyclestone; an empty-toolset base has no preserved cyclestone command to
# remove (docs/architecture/image-contract.md).
base_tools=$(docker image inspect --format '{{ index .Config.Labels "io.cyclestone.tools" }}' "$base_image")
base_tools=${base_tools:-}

set -- \
  'root|final USER must be developer' \
  'home|identity, HOME, or public configuration paths' \
  'workdir|WORKDIR must be /workspace'
case ",${base_tools}," in *,cyclestone,*)
  set -- "$@" 'cyclestone|keep the Cyclestone command available'
;; esac

for record in "$@"; do
  case_name=${record%%|*}
  diagnostic=${record#*|}
  invalid_image=cyclestone-child-invalid:$case_name
  docker buildx build --builder default --provenance=false --load \
    --file "$repo_root/tests/fixtures/child-image-invalid/$case_name/Containerfile" \
    --build-arg "BASE_IMAGE_REF=$child_image" --tag "$invalid_image" "$repo_root" >/dev/null
  if IMAGE=$invalid_image "$repo_root/tests/child-image-contract.sh" \
    >"$temporary/$case_name.log" 2>&1; then
    echo "FAIL: invalid $case_name child image was accepted" >&2
    exit 1
  fi
  grep -Fq "$diagnostic" "$temporary/$case_name.log" \
    || { echo "FAIL: invalid $case_name child produced the wrong diagnostic" >&2; exit 1; }
  echo "PASS: rejected invalid $case_name child ($diagnostic)"
done
rm -rf "$temporary"
trap - EXIT HUP INT TERM

container_name=cyclestone-child-signal-$$
cleanup() {
  docker rm -f "$container_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM
docker run --name "$container_name" -d "$child_image" sh -c \
  'trap "exit 42" TERM; while :; do sleep 1; done' >/dev/null
docker kill --signal TERM "$container_name" >/dev/null
exit_code=$(docker wait "$container_name")
test "$exit_code" -eq 42 || { echo "FAIL: child PID 1 did not receive TERM (exit $exit_code)" >&2; exit 1; }
echo 'PASS: child PID-1 TERM forwarding (exit 42)'
docker rm "$container_name" >/dev/null
trap - EXIT HUP INT TERM

echo "PASS: child build, SDK execution, and signal inheritance ($platform)"
