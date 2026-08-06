#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
template=$repo_root/templates/project-devcontainer
identity_fixture=$repo_root/tests/fixtures/workspace-identity/assertions.sh
runtime_fixture=$repo_root/tests/fixtures/devcontainer-podman/runtime.sh
evidence_dir=${EVIDENCE_DIR:-$repo_root/dist/evidence/devcontainer-podman}
base_id=${CYCLESTONE_BASE_IMAGE_ID:?set CYCLESTONE_BASE_IMAGE_ID to the verified loaded image ID}
base_locator=${CYCLESTONE_BASE_IMAGE_LOCAL:?set CYCLESTONE_BASE_IMAGE_LOCAL to its local-only Podman locator}
identity_case=${IDENTITY_CASE:?set IDENTITY_CASE to matching or differing}
test_root=$(mktemp -d)
cache_volume=cyclestone-project-go-cache-$identity_case-$$
container_id=

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

cleanup() {
  if test -n "$container_id"; then
    podman rm -f "$container_id" >/dev/null 2>&1 || true
  fi
  podman volume rm -f "$cache_volume" >/dev/null 2>&1 || true
  test -n "${test_root:-}" && test "$test_root" != / && rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

command -v devcontainer >/dev/null 2>&1 || fail 'Dev Container CLI is unavailable'
command -v jq >/dev/null 2>&1 || fail 'jq is unavailable'
command -v podman >/dev/null 2>&1 || fail 'Podman is unavailable'
test "$identity_case" = matching || test "$identity_case" = differing \
  || fail 'IDENTITY_CASE must be matching or differing'
test "$(podman info --format '{{.Host.Security.Rootless}}')" = true \
  || fail 'Podman is not rootless'
test "$(podman info --format json | jq -r '.host.ociRuntime.name')" = crun \
  || fail 'Podman must use crun'
resolved_base_id=$(podman image inspect --format '{{.Id}}' "$base_locator")
case "$resolved_base_id" in sha256:*) ;; *) resolved_base_id=sha256:$resolved_base_id ;; esac
test "$resolved_base_id" = "$base_id" \
  || fail 'local-only base locator does not resolve to the verified image ID'
printf '%s\n' "$base_id" | grep -Eq '^sha256:[0-9a-f]{64}$' \
  || fail 'verified base identity is not a content-addressed image ID'

host_uid=$(id -u)
host_gid=$(id -g)
test "$host_uid" -ne 0 || fail 'rootless validation cannot run as root'
case "$identity_case" in
  matching) test "$host_uid:$host_gid" = 1000:1000 || fail 'matching fixture is not 1000:1000' ;;
  differing) test "$host_uid:$host_gid" != 1000:1000 || fail 'differing fixture unexpectedly matches 1000:1000' ;;
esac

workspace=$test_root/workspace
mkdir -p "$workspace/.identity" "$workspace/docs" "$workspace/tests"
cp -R "$template/." "$workspace/"
cp "$identity_fixture" "$workspace/.identity/assertions.sh"
cp "$runtime_fixture" "$workspace/.identity/devcontainer-runtime.sh"
printf 'root sentinel\n' > "$workspace/.host-workspace-sentinel"
printf 'documentation sentinel\n' > "$workspace/docs/top-level-sentinel"
printf 'tests sentinel\n' > "$workspace/tests/top-level-sentinel"
printf 'original\n' > "$workspace/edit.txt"
git -C "$workspace" init -q
git -C "$workspace" config user.name 'Cyclestone local validation'
git -C "$workspace" config user.email 'validation@localhost.invalid'
git -C "$workspace" config commit.gpgsign false
git -C "$workspace" add .
git -C "$workspace" commit -q -m 'Create tracked validation workspace'
jq --arg volume "$cache_volume" '
  .mounts = ["source=" + $volume + ",target=/home/developer/.cache/go-build,type=volume"]
' "$workspace/.devcontainer/devcontainer.json" > "$test_root/config.json"
mv "$test_root/config.json" "$workspace/.devcontainer/devcontainer.json"

snapshot=$test_root/preexisting.snapshot
for path in .host-workspace-sentinel docs/top-level-sentinel tests/top-level-sentinel; do
  stat -c '%n %u:%g %a' "$workspace/$path"
  sha256sum "$workspace/$path"
done > "$snapshot"

mkdir -p "$evidence_dir"
devcontainer --version > "$evidence_dir/devcontainer-version.txt"
podman version > "$evidence_dir/podman-version.txt"
podman info > "$evidence_dir/podman-info.txt"
printf 'identity_case=%s\nhost_uid=%s\nhost_gid=%s\nbase_id=%s\n' \
  "$identity_case" "$host_uid" "$host_gid" "$base_id" > "$evidence_dir/request.txt"

export CYCLESTONE_BASE_IMAGE_REF="$base_id"
up() {
  phase=$1
  shift
  devcontainer --docker-path podman up --workspace-folder "$workspace" "$@" \
    > "$evidence_dir/up-$phase.json" 2> "$evidence_dir/up-$phase.log"
  container_id=$(jq -r '.containerId // empty' "$evidence_dir/up-$phase.json")
  test -n "$container_id" || fail "Dev Container did not report a container ID during $phase"
}

assert_runtime() {
  phase=$1
  podman exec "$container_id" \
    /workspace/.identity/devcontainer-runtime.sh assert "$phase"
  podman inspect "$container_id" > "$evidence_dir/inspect-$phase.json"
}

up first
assert_runtime first
child_image=$(podman inspect --format '{{.Image}}' "$container_id")
CONTAINER_CLI=podman IMAGE=$child_image "$repo_root/tests/child-image-contract.sh"
podman exec "$container_id" \
  /workspace/.identity/devcontainer-runtime.sh persist
podman exec "$container_id" \
  /workspace/.devcontainer/lifecycle.sh postCreate > "$evidence_dir/lifecycle-rerun-first.txt"

podman stop "$container_id" >/dev/null
container_id=
up reopen
assert_runtime second

# Optional editor customizations are not part of CLI correctness.
jq 'del(.customizations) | .build.options = ["--pull=never"]' \
  "$workspace/.devcontainer/devcontainer.json" > "$test_root/config-without-customizations.json"
mv "$test_root/config-without-customizations.json" "$workspace/.devcontainer/devcontainer.json"
up rebuild --remove-existing-container --build-no-cache
assert_runtime third
podman exec "$container_id" \
  /workspace/.devcontainer/lifecycle.sh postCreate > "$evidence_dir/lifecycle-rerun-rebuild.txt"
podman stop "$container_id" >/dev/null
container_id=
up post-rebuild-reopen
assert_runtime fourth

test "$(stat -c '%u:%g' "$workspace/create.txt")" = "$host_uid:$host_gid" \
  || fail 'workspace file does not belong to the invoking host identity'
test "$(stat -c '%u:%g' "$workspace/build/artifact.txt")" = "$host_uid:$host_gid" \
  || fail 'build artifact does not belong to the invoking host identity'
for path in .host-workspace-sentinel docs/top-level-sentinel tests/top-level-sentinel; do
  stat -c '%n %u:%g %a' "$workspace/$path"
  sha256sum "$workspace/$path"
done > "$test_root/preexisting-after.snapshot"
cmp "$snapshot" "$test_root/preexisting-after.snapshot" >/dev/null \
  || fail 'reopen or rebuild changed pre-existing repository content or metadata'
podman volume inspect "$cache_volume" > "$evidence_dir/cache-volume.json"

# Exercise the conflicting setting to record actual CLI/Podman behavior. It is
# never accepted as a supported configuration, regardless of observed outcome.
conflict=$test_root/conflict
cp -R "$workspace" "$conflict"
jq '.updateRemoteUserUID = true | .mounts = []' \
  "$conflict/.devcontainer/devcontainer.json" > "$test_root/conflict.json"
mv "$test_root/conflict.json" "$conflict/.devcontainer/devcontainer.json"
set +e
devcontainer --docker-path podman up --workspace-folder "$conflict" \
  > "$evidence_dir/conflict-up.json" 2> "$evidence_dir/conflict-up.log"
conflict_status=$?
set -e
printf 'updateRemoteUserUID=true up_status=%s\n' "$conflict_status" \
  > "$evidence_dir/conflict-observation.txt"
if test "$conflict_status" -eq 0; then
  conflict_id=$(jq -r '.containerId // empty' "$evidence_dir/conflict-up.json")
  if test -n "$conflict_id"; then
    podman exec "$conflict_id" sh -c 'id; getent passwd developer; cat /proc/self/uid_map; cat /proc/self/gid_map' \
      >> "$evidence_dir/conflict-observation.txt" 2>&1 || true
    podman rm -f "$conflict_id" >/dev/null
  fi
fi

credential_matches=$test_root/prohibited-credential-matches.txt
grep -R -I -Eni \
  '(authorization:|bearer[[:space:]]|api[_-]?key|access[_-]?token|client[_-]?secret|private[_-]?key)' \
  "$workspace/.devcontainer" "$evidence_dir" \
  | grep -Ev '[[:space:]]authorization:[[:space:]]+null[[:space:]]*$' \
  > "$credential_matches" || true
if test -s "$credential_matches"; then
  cut -d: -f1 "$credential_matches" | LC_ALL=C sort -u >&2
  fail 'lifecycle configuration or captured output contains a prohibited credential pattern'
fi

echo "PASS: rootless Podman Dev Container build, lifecycle, ownership, reopen, and rebuild ($identity_case)"
