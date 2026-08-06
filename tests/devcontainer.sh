#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$repo_root/tests/fixtures/devcontainer
identity_fixture=$repo_root/tests/fixtures/workspace-identity/assertions.sh
image=${CYCLESTONE_VALIDATION_IMAGE:-cyclestone-base:1.0.0}
evidence_dir=${EVIDENCE_DIR:-$repo_root/dist/evidence/devcontainer}
test_root=$(mktemp -d)
container_id=
home_volume=cyclestone-devcontainer-home-$$

cleanup() {
  if test -n "$container_id" && docker container inspect "$container_id" >/dev/null 2>&1; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
  if test -n "${workspace:-}" && test -d "$workspace/ownership-mismatch"; then
    docker run --rm --entrypoint sh --user 0 \
      --mount "type=bind,src=$workspace,dst=/target" "$image" \
      -c 'rm -rf /target/ownership-mismatch' >/dev/null 2>&1 || true
  fi
  docker volume rm -f "$home_volume" >/dev/null 2>&1 || true
  test -n "${test_root:-}" && test "$test_root" != / && rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

has_keep_id() {
  jq -e '[(.runArgs // [])[] | select(test("(^|[=:])keep-id([,:=]|$)"))] | length > 0' "$1" >/dev/null
}

command -v devcontainer >/dev/null 2>&1 || fail 'client mutation: Dev Container CLI is unavailable'
command -v jq >/dev/null 2>&1 || fail 'client mutation: jq is unavailable'
docker image inspect "$image" >/dev/null 2>&1 || fail "client mutation: image is not loaded: $image"

host_uid=$(id -u)
host_gid=$(id -g)
test "$host_uid" -ne 0 || fail 'client mutation: Dev Container identity validation cannot run as host root'

config=$fixture/.devcontainer/devcontainer.json
jq -e '
  .remoteUser == "developer"
  and .containerUser == "developer"
  and .updateRemoteUserUID == true
  and .workspaceFolder == "/workspace"
  and .privileged == false
  and (.mounts | length == 1)
  and (.runArgs == [])
' "$config" >/dev/null || fail 'client mutation: Dev Container fixture weakens the runtime contract'
has_keep_id "$config" && fail 'client mutation: updateRemoteUserUID cannot be combined with Podman keep-id'
conflict=$test_root/conflicting.json
jq '.runArgs = ["--userns=keep-id"]' "$config" > "$conflict"
has_keep_id "$conflict" || fail 'client mutation: conflicting Podman keep-id configuration was not diagnosed'
grep -Eq 'docker\.sock|podman\.sock|--privileged' "$config" \
  && fail 'client mutation: fixture contains a privileged or daemon-socket default'

workspace=$test_root/workspace
mkdir -p "$workspace/.identity"
cp -R "$fixture/." "$workspace/"
cp "$identity_fixture" "$workspace/.identity/assertions.sh"
printf 'host bind mount\n' > "$workspace/.host-workspace-sentinel"
printf 'original\n' > "$workspace/edit.txt"

# A root-owned repository must retain Git's dubious-ownership failure. Rootless
# Docker maps container root to the host user, so that separate C2 mode skips
# this rootful-only negative fixture.
if ! docker info --format '{{json .SecurityOptions}}' | grep -q rootless; then
  docker run --rm --entrypoint sh --user 0 \
    --mount "type=bind,src=$workspace,dst=/target" "$image" -eu -c '
      mkdir /target/ownership-mismatch
      git init -q /target/ownership-mismatch
      printf "mismatch\n" > /target/ownership-mismatch/tracked
      git -C /target/ownership-mismatch add tracked
    '
fi

snapshot=$test_root/preexisting.snapshot
for path in .devcontainer/devcontainer.json .identity/assertions.sh .host-workspace-sentinel; do
  stat -c '%n %u:%g %a' "$workspace/$path"
  sha256sum "$workspace/$path"
done > "$snapshot"

mkdir -p "$evidence_dir"
export CYCLESTONE_VALIDATION_IMAGE="$image"
export CYCLESTONE_HOME_VOLUME="$home_volume"
docker volume create "$home_volume" >/dev/null

devcontainer up --workspace-folder "$workspace" > "$evidence_dir/devcontainer-up-first.json"
container_id=$(jq -r '.containerId // empty' "$evidence_dir/devcontainer-up-first.json")
test -n "$container_id" || fail 'client mutation: Dev Container CLI did not report a container ID'

docker exec "$container_id" /usr/bin/env \
  "IDENTITY_EXPECTED_UID=$host_uid" "IDENTITY_EXPECTED_GID=$host_gid" IDENTITY_PHASE=first \
  /workspace/.identity/assertions.sh

test "$(docker inspect --format '{{.HostConfig.Privileged}}' "$container_id")" = false \
  || fail 'client mutation: Dev Container started privileged'
docker inspect "$container_id" | jq -e '
  .[0].Config.User == "developer"
  and ([.[0].Mounts[].Destination] | index("/var/run/docker.sock") | not)
  and ([.[0].Mounts[].Destination] | index("/run/podman/podman.sock") | not)
' >/dev/null || fail 'client mutation: container user or mount contract is invalid'
docker inspect "$container_id" > "$evidence_dir/devcontainer-inspect-first.json"

docker stop "$container_id" >/dev/null
container_id=
devcontainer up --workspace-folder "$workspace" > "$evidence_dir/devcontainer-up-second.json"
container_id=$(jq -r '.containerId // empty' "$evidence_dir/devcontainer-up-second.json")
test -n "$container_id" || fail 'client mutation: Dev Container did not restart'
docker exec "$container_id" /usr/bin/env \
  "IDENTITY_EXPECTED_UID=$host_uid" "IDENTITY_EXPECTED_GID=$host_gid" IDENTITY_PHASE=second \
  /workspace/.identity/assertions.sh

"$repo_root/tests/workspace-identity.sh" "$workspace" "$host_uid" "$host_gid"
mkdir -p "$evidence_dir/runtime"
cp -R "$workspace/.identity-evidence/." "$evidence_dir/runtime/"
after_snapshot=$test_root/preexisting-after.snapshot
for path in .devcontainer/devcontainer.json .identity/assertions.sh .host-workspace-sentinel; do
  stat -c '%n %u:%g %a' "$workspace/$path"
  sha256sum "$workspace/$path"
done > "$after_snapshot"
cmp "$snapshot" "$after_snapshot" >/dev/null \
  || fail 'filesystem: startup mutated ownership, mode, or content of pre-existing workspace paths'

docker inspect "$container_id" > "$evidence_dir/devcontainer-inspect-second.json"
docker volume inspect "$home_volume" > "$evidence_dir/devcontainer-home-volume.json"
devcontainer --version > "$evidence_dir/devcontainer-version.txt"

echo "PASS: Dev Container developer identity, host ownership, Git, HOME persistence, and diagnostics ($image)"
