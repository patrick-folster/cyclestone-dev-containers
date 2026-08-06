#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
identity_fixture=$repo_root/tests/fixtures/workspace-identity/assertions.sh
image=${IMAGE:-cyclestone-base:1.0.0}
evidence_dir=${EVIDENCE_DIR:-$repo_root/dist/evidence/rootless-podman}
test_root=$(mktemp -d)
home_volume=cyclestone-podman-home-$$
container_name=cyclestone-podman-identity-$$

cleanup() {
  podman rm -f "$container_name" >/dev/null 2>&1 || true
  podman volume rm -f "$home_volume" >/dev/null 2>&1 || true
  test -n "${test_root:-}" && test "$test_root" != / && rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

command -v podman >/dev/null 2>&1 || fail 'namespace map: Podman is unavailable'
command -v jq >/dev/null 2>&1 || fail 'namespace map: jq is unavailable'
test "$(podman info --format '{{.Host.Security.Rootless}}')" = true \
  || fail 'namespace map: Podman is not running rootless'
podman image inspect "$image" >/dev/null 2>&1 || fail "namespace map: image is not loaded: $image"

podman_version=$(podman version --format '{{.Client.Version}}')
minimum_version=4.9.0
test "$(printf '%s\n%s\n' "$minimum_version" "$podman_version" | sort -V | head -n 1)" = "$minimum_version" \
  || fail "namespace map: Podman $podman_version is older than tested minimum $minimum_version"
runtime=$(podman info --format json | jq -r '.host.ociRuntime.name // empty')
test "$runtime" = crun || fail "group map: OCI runtime is $runtime; supplementary keep-groups requires crun"

host_user=$(id -un)
host_uid=$(id -u)
host_gid=$(id -g)
test "$host_uid" -ne 0 || fail 'namespace map: rootless Podman validation cannot run as root'
grep -Eq "^$host_user:[0-9]+:[0-9]+$" /etc/subuid \
  || fail "namespace map: no subordinate UID range for $host_user in /etc/subuid"
grep -Eq "^$host_user:[0-9]+:[0-9]+$" /etc/subgid \
  || fail "group map: no subordinate GID range for $host_user in /etc/subgid"

developer_uid=$(podman run --rm "$image" id -u)
developer_gid=$(podman run --rm "$image" id -g)
test "$developer_uid:$developer_gid" = 1000:1000 \
  || fail "namespace map: keep-id command expects image developer 1000:1000, found $developer_uid:$developer_gid"

workspace=$test_root/workspace
mkdir -p "$workspace/.identity"
cp "$identity_fixture" "$workspace/.identity/assertions.sh"
printf 'host bind mount\n' > "$workspace/.host-workspace-sentinel"
printf 'original\n' > "$workspace/edit.txt"

group_path=${IDENTITY_GROUP_PATH:?set IDENTITY_GROUP_PATH to a host group-writable test directory}
group_gid=${IDENTITY_GROUP_GID:?set IDENTITY_GROUP_GID to the supplementary group of that directory}
test -d "$group_path" || fail "filesystem: supplementary-group path does not exist: $group_path"
id -G | tr ' ' '\n' | grep -Fx "$group_gid" >/dev/null \
  || fail "group map: invoking user is not a member of supplementary GID $group_gid"
test ! -e "$group_path/from-developer" \
  || fail 'filesystem: supplementary-group probe already exists'

snapshot=$test_root/preexisting.snapshot
for path in .identity/assertions.sh .host-workspace-sentinel; do
  stat -c '%n %u:%g %a' "$workspace/$path"
  sha256sum "$workspace/$path"
done > "$snapshot"

mkdir -p "$evidence_dir"
podman version > "$evidence_dir/podman-version.txt"
podman info > "$evidence_dir/podman-info.txt"
stat -c '%n uid=%u gid=%g mode=%a' "$group_path" \
  > "$evidence_dir/group-access-before.txt"
podman volume create "$home_volume" >/dev/null

run_identity() {
  phase=$1
  podman run --name "$container_name" \
    --user developer \
    --userns=keep-id:uid=1000,gid=1000 \
    --group-add keep-groups \
    --security-opt=no-new-privileges \
    --mount "type=bind,source=$workspace,destination=/workspace,relabel=private" \
    --mount "type=bind,source=$group_path,destination=/group-access,relabel=private" \
    --volume "$home_volume:/home/developer" \
    --env "IDENTITY_EXPECTED_UID=1000" \
    --env "IDENTITY_EXPECTED_GID=1000" \
    --env "IDENTITY_GROUP_GID=$group_gid" \
    --env "IDENTITY_PHASE=$phase" \
    "$image" /workspace/.identity/assertions.sh
  podman inspect "$container_name" > "$evidence_dir/podman-inspect-$phase.json"
  jq -e '
    .[0].Config.User == "developer"
    and .[0].HostConfig.Privileged == false
    and (.[0].HostConfig.SecurityOpt | index("no-new-privileges") != null)
  ' "$evidence_dir/podman-inspect-$phase.json" >/dev/null \
    || fail 'namespace map: Podman user or privilege settings differ from the supported command'
  podman rm "$container_name" >/dev/null
}

run_identity first
test "$(stat -c '%u:%g' "$group_path/from-developer")" = "$host_uid:$group_gid" \
  || fail 'group map: supplementary-group probe has unexpected host ownership'
probe_mode=$(stat -c '%a' "$group_path/from-developer")
test "$probe_mode" = 664 || test "$probe_mode" = 660 \
  || fail "group map: supplementary-group probe has unexpected host mode: $probe_mode"
run_identity second
stat -c '%n uid=%u gid=%g mode=%a' "$group_path" "$group_path/from-developer" \
  > "$evidence_dir/group-access-after.txt"
test "$(sed -n '1p' "$evidence_dir/group-access-after.txt")" = \
  "$(sed -n '1p' "$evidence_dir/group-access-before.txt")" \
  || fail 'group map: supplementary-group directory ownership or mode changed'

"$repo_root/tests/workspace-identity.sh" "$workspace" "$host_uid" "$host_gid"
mkdir -p "$evidence_dir/runtime"
cp -R "$workspace/.identity-evidence/." "$evidence_dir/runtime/"
after_snapshot=$test_root/preexisting-after.snapshot
for path in .identity/assertions.sh .host-workspace-sentinel; do
  stat -c '%n %u:%g %a' "$workspace/$path"
  sha256sum "$workspace/$path"
done > "$after_snapshot"
cmp "$snapshot" "$after_snapshot" >/dev/null \
  || fail 'filesystem: startup mutated ownership, mode, or content of pre-existing workspace paths'
podman volume inspect "$home_volume" > "$evidence_dir/podman-home-volume.json"

echo "PASS: rootless Podman keep-id developer identity, ownership, Git, HOME persistence, and supplementary groups ($image)"
