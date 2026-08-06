#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM

if PLATFORM=linux/s390x \
  BASE_IMAGE_REF=ghcr.io/patrick-folster/cyclestone-dev-container-base@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  "$repo_root/scripts/build-child-image.sh" >"$temporary/platform.log" 2>&1; then
  echo 'FAIL: unsupported child platform was accepted' >&2
  exit 1
fi
grep -Fq 'unsupported platform: linux/s390x' "$temporary/platform.log" \
  || { echo 'FAIL: unsupported child platform diagnostic missing' >&2; exit 1; }

if PLATFORM=linux/amd64 BASE_IMAGE_REF=cyclestone-base:latest \
  "$repo_root/scripts/build-child-image.sh" >"$temporary/base.log" 2>&1; then
  echo 'FAIL: floating child base reference was accepted' >&2
  exit 1
fi
grep -Fq 'canonical GHCR manifest digest or a local sha256 image ID' "$temporary/base.log" \
  || { echo 'FAIL: floating base diagnostic missing' >&2; exit 1; }

mock_dir=$temporary/bin
mkdir "$mock_dir"
ln -s "$repo_root/tests/fixtures/child-image-invalid/mock-docker.sh" "$mock_dir/docker"

local_id=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
docker_log=$temporary/docker.log
PATH=$mock_dir:$PATH MOCK_IMAGE_ID=$local_id MOCK_DOCKER_LOG=$docker_log \
  PLATFORM=linux/amd64 BASE_IMAGE_REF=$local_id LOCAL_BASE_IMAGE=cyclestone-base:loaded \
  IMAGE_TAG=fixture "$repo_root/scripts/build-child-image.sh"
grep -Fq 'buildx build --provenance=false --load --builder default' "$docker_log" \
  || { echo 'FAIL: local child build did not select the context-backed default builder' >&2; exit 1; }
if grep -Fq -- '--pull' "$docker_log"; then
  echo 'FAIL: local child build unexpectedly enabled pulling' >&2
  exit 1
fi

: > "$docker_log"
PATH=$mock_dir:$PATH MOCK_DOCKER_LOG=$docker_log PLATFORM=linux/amd64 \
  BASE_IMAGE_REF=ghcr.io/patrick-folster/cyclestone-dev-container-base@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
  IMAGE_TAG=fixture "$repo_root/scripts/build-child-image.sh"
grep -Fq 'buildx build --provenance=false --load --pull' "$docker_log" \
  || { echo 'FAIL: registry child build did not retain pull behavior' >&2; exit 1; }
if grep -Fq -- '--builder default' "$docker_log"; then
  echo 'FAIL: registry child build unexpectedly replaced the selected builder' >&2
  exit 1
fi

if PATH=$mock_dir:$PATH MOCK_DOCKER_LOG=$docker_log PLATFORM=linux/amd64 \
  BASE_IMAGE_REF=$local_id LOCAL_BASE_IMAGE=missing \
  "$repo_root/scripts/build-child-image.sh" >"$temporary/missing.log" 2>&1; then
  echo 'FAIL: missing local base locator was accepted' >&2
  exit 1
fi
grep -Fq 'local base image locator is not loaded' "$temporary/missing.log" \
  || { echo 'FAIL: missing local base diagnostic missing' >&2; exit 1; }

if PATH=$mock_dir:$PATH MOCK_IMAGE_ID=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
  MOCK_DOCKER_LOG=$docker_log PLATFORM=linux/amd64 BASE_IMAGE_REF=$local_id \
  LOCAL_BASE_IMAGE=wrong "$repo_root/scripts/build-child-image.sh" \
  >"$temporary/mismatch.log" 2>&1; then
  echo 'FAIL: mismatched local base locator was accepted' >&2
  exit 1
fi
grep -Fq 'local base image locator does not match BASE_IMAGE_REF' "$temporary/mismatch.log" \
  || { echo 'FAIL: mismatched local base diagnostic missing' >&2; exit 1; }

for record in \
  'root|final USER must be developer' \
  'home|identity, HOME, or public configuration paths' \
  'workdir|WORKDIR must be /workspace' \
  'cyclestone|keep the Cyclestone command available'; do
  case_name=${record%%|*}
  diagnostic=${record#*|}
  if PATH=$mock_dir:$PATH MOCK_CASE=$case_name IMAGE=fixture \
    "$repo_root/tests/child-image-contract.sh" >"$temporary/$case_name.log" 2>&1; then
    echo "FAIL: invalid $case_name fixture was accepted" >&2
    exit 1
  fi
  grep -Fq "$diagnostic" "$temporary/$case_name.log" \
    || { echo "FAIL: invalid $case_name diagnostic missing" >&2; exit 1; }
done

echo 'PASS: child builder selection, trust checks, and negative contract regressions'
