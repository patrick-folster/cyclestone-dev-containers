#!/bin/sh
set -eu

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

workspace=${1:?usage: workspace-identity.sh WORKSPACE EXPECTED_UID EXPECTED_GID}
expected_uid=${2:?missing expected UID}
expected_gid=${3:?missing expected GID}

for path in create.txt edit.txt build build/artifact.txt .git .git/objects; do
  test -e "$workspace/$path" || fail "filesystem: expected workspace output is missing: $path"
done
test ! -e "$workspace/delete.txt" || fail 'filesystem: delete operation did not remove its probe'
test "$(cat "$workspace/build/artifact.txt")" = artifact || fail 'filesystem: build artifact content is wrong'

find "$workspace" \( -path "$workspace/ownership-mismatch" -o -path "$workspace/ownership-mismatch/*" \) -prune -o \
  \( -type f -o -type d \) -print | while IFS= read -r path; do
    owner=$(stat -c '%u:%g' "$path")
    test "$owner" = "$expected_uid:$expected_gid" \
      || fail "filesystem: host owner for ${path#"$workspace"/} is $owner, expected $expected_uid:$expected_gid"
  done

test -s "$workspace/.identity-evidence/identity-first.txt" || fail 'client mutation: identity evidence is missing'
test -s "$workspace/.identity-evidence/uid-map-first.txt" || fail 'namespace map: UID evidence is missing'
test -s "$workspace/.identity-evidence/gid-map-first.txt" || fail 'group map: GID evidence is missing'
test -s "$workspace/.identity-evidence/mounts-first.txt" || fail 'filesystem: mount evidence is missing'
