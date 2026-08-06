#!/bin/sh
set -eu

image=${IMAGE:-cyclestone-base:1.0.0}
test_root=$(mktemp -d)
cleanup() {
  test -n "${test_root:-}" && test "$test_root" != / && rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

docker info --format '{{json .SecurityOptions}}' | grep -q rootless \
  || fail 'Docker daemon is not rootless'
docker image inspect "$image" >/dev/null 2>&1 || fail "image is not loaded: $image"
command -v setfacl >/dev/null 2>&1 || fail 'setfacl is unavailable'

workspace=$test_root/workspace
mkdir "$workspace"
chmod 0755 "$workspace"
printf 'host-owned\n' > "$workspace/from-host"
before_owner=$(stat -c '%u:%g' "$workspace")
developer_uid=$(docker run --rm "$image" id -u)
rootless_user=$(id -un)
subuid_start=$(awk -F: -v user="$rootless_user" '$1 == user { print $2; exit }' /etc/subuid)
test -n "$subuid_start" || fail "no subordinate UID range for $rootless_user"
case "$developer_uid" in
  0) mapped_developer_uid=$(id -u) ;;
  *[!0-9]*|'') fail "invalid developer UID: $developer_uid" ;;
  *) mapped_developer_uid=$((subuid_start + developer_uid - 1)) ;;
esac

# Rootless Docker maps container UID n>0 to subuid+(n-1). Grant only that
# mapped identity access; retain host ownership and do not modify it at startup.
setfacl -m "u:$mapped_developer_uid:rwx" "$workspace"

docker run --rm --mount "type=bind,src=$workspace,dst=/workspace" "$image" sh -eu -c '
  test "$(id -un)" = developer
  test "$(cat /workspace/from-host)" = host-owned
  printf "container-written\n" > /workspace/from-container
' || fail 'developer could not read and write the host-owned workspace'

test "$(cat "$workspace/from-container")" = container-written \
  || fail 'container write was not visible on the host'
after_owner=$(stat -c '%u:%g' "$workspace")
test "$after_owner" = "$before_owner" \
  || fail "workspace ownership changed from $before_owner to $after_owner"

echo "PASS: rootless host-owned bind mount is writable through a narrow mapped-UID ACL without startup chown ($image)"
