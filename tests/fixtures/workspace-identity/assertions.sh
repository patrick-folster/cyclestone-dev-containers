#!/bin/sh
set -eu

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

expected_uid=${IDENTITY_EXPECTED_UID:?set IDENTITY_EXPECTED_UID}
expected_gid=${IDENTITY_EXPECTED_GID:?set IDENTITY_EXPECTED_GID}
phase=${IDENTITY_PHASE:-first}
expect_home_persistence=${IDENTITY_EXPECT_HOME_PERSISTENCE:-true}
evidence=/workspace/.identity-evidence

mkdir -p "$evidence"
{
  id
  printf 'user=%s\nuid=%s\ngid=%s\nhome=%s\npwd=%s\n' \
    "$(id -un)" "$(id -u)" "$(id -g)" "$HOME" "$PWD"
  stat -c '%n uid=%u gid=%g mode=%a' "$HOME" /workspace
} > "$evidence/identity-$phase.txt"
cat /proc/self/uid_map > "$evidence/uid-map-$phase.txt"
cat /proc/self/gid_map > "$evidence/gid-map-$phase.txt"
sed -n '\| /workspace |p;\| /home/developer |p' /proc/self/mountinfo \
  > "$evidence/mounts-$phase.txt"

test "$(id -un)" = developer || fail 'client mutation: username is not developer'
test "$(id -u)" = "$expected_uid" || fail 'client mutation: effective UID differs from the selected mode'
test "$(id -g)" = "$expected_gid" || fail 'group map: effective GID differs from the selected mode'
test "$HOME" = /home/developer || fail 'volume: HOME is not /home/developer'
test "$PWD" = /workspace || fail 'filesystem: working directory is not /workspace'
test "$(stat -c %u "$HOME")" = "$expected_uid" || fail 'volume: HOME owner does not match the effective UID'
test "$(stat -c %g "$HOME")" = "$expected_gid" || fail 'volume: HOME group does not match the effective GID'
test -f /workspace/.host-workspace-sentinel || fail 'filesystem: host bind mount did not replace /workspace'
test ! -e /workspace/.image-workspace-sentinel || fail 'filesystem: image seed content leaked through bind mount'

if test -n "${IDENTITY_GROUP_GID:-}"; then
  if id -G | tr ' ' '\n' | grep -Fx "$IDENTITY_GROUP_GID" >/dev/null; then
    group_presentation=mapped
  else
    group_presentation=unmapped-or-overflow
  fi
  printf 'requested-host-gid=%s\ncontainer-presentation=%s\ncontainer-groups=%s\n' \
    "$IDENTITY_GROUP_GID" "$group_presentation" "$(id -G)" \
    > "$evidence/supplementary-groups-$phase.txt"
  umask 0002
  printf 'supplementary group\n' > /group-access/from-developer \
    || fail 'filesystem: supplementary-group path is not writable; check group mapping and filesystem policy'
fi

if git config --global --get-all safe.directory 2>/dev/null | grep -Fx '*' >/dev/null; then
  fail 'filesystem: unsafe global safe.directory wildcard is configured'
fi
if test -d /workspace/ownership-mismatch/.git; then
  if git -C /workspace/ownership-mismatch status > "$evidence/mismatch-$phase.txt" 2>&1; then
    fail 'filesystem: Git accepted the intentionally mismatched repository'
  fi
  grep -Eiq 'dubious ownership|safe\.directory' "$evidence/mismatch-$phase.txt" \
    || fail 'filesystem: ownership-mismatch diagnostic was not actionable'
fi

if test "$phase" = first; then
  printf 'created\n' > /workspace/create.txt
  printf 'modified\n' >> /workspace/edit.txt
  printf 'deleted\n' > /workspace/delete.txt
  rm /workspace/delete.txt
  mkdir -p /workspace/build
  printf 'artifact\n' > /workspace/build/artifact.txt

  git init -q /workspace
  git -C /workspace config user.name 'Cyclestone Identity Test'
  git -C /workspace config user.email identity@example.invalid
  printf '.identity-evidence/\nownership-mismatch/\n' >> /workspace/.git/info/exclude
  git -C /workspace add .host-workspace-sentinel create.txt edit.txt build/artifact.txt
  git -C /workspace commit -qm 'exercise workspace identity'

  if test "$expect_home_persistence" = true; then
    git config --global user.name 'Cyclestone Developer'
    git config --global user.email developer@example.invalid
    mkdir -p "$XDG_CONFIG_HOME/cyclestone-test" "$XDG_CACHE_HOME/cyclestone-test" \
      "$XDG_DATA_HOME/cyclestone-test"
    printf 'config\n' > "$XDG_CONFIG_HOME/cyclestone-test/probe"
    printf 'cache\n' > "$XDG_CACHE_HOME/cyclestone-test/probe"
    printf 'data\n' > "$XDG_DATA_HOME/cyclestone-test/probe"
    printf 'persistent\n' > "$HOME/.identity-volume-probe"
  fi
elif test "$expect_home_persistence" = true; then
  test "$(cat "$HOME/.identity-volume-probe")" = persistent \
    || fail 'volume: HOME probe did not survive restart'
  test "$(git config --global user.name)" = 'Cyclestone Developer' \
    || fail 'volume: Git configuration did not survive restart'
  if ! test -w "$XDG_CONFIG_HOME/cyclestone-test/probe" \
    || ! test -w "$XDG_CACHE_HOME/cyclestone-test/probe" \
    || ! test -w "$XDG_DATA_HOME/cyclestone-test/probe"; then
    fail 'volume: XDG probes are not writable after restart'
  fi
  printf 'updated\n' >> "$HOME/.identity-volume-probe"
fi
