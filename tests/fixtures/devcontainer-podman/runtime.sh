#!/bin/sh
set -eu

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

action=${1:-}
case "$action" in
  assert)
    phase=${2:?set the validation phase}
    IDENTITY_EXPECTED_UID=1000 \
    IDENTITY_EXPECTED_GID=1000 \
    IDENTITY_EXPECT_HOME_PERSISTENCE=false \
    IDENTITY_PHASE=$phase \
      /workspace/.identity/assertions.sh
    test -f /workspace/docs/top-level-sentinel
    test -f /workspace/tests/top-level-sentinel
    git -C /workspace ls-files --error-unmatch .host-workspace-sentinel >/dev/null
    git -C /workspace ls-files --error-unmatch docs/top-level-sentinel >/dev/null
    git -C /workspace ls-files --error-unmatch tests/top-level-sentinel >/dev/null
    test "$(id -un)" = developer
    test "$(id -u):$(id -g)" = 1000:1000
    test "$(cat "$HOME/.cache/go-build/.cyclestone-template-ready")" = ready
    if test "$phase" != first; then
      test "$(cat /home/developer/.cache/go-build/.cyclestone-persistence-sentinel)" = persistent
    fi
    ;;
  persist)
    printf '%s\n' persistent > /home/developer/.cache/go-build/.cyclestone-persistence-sentinel
    ;;
  *)
    fail 'usage: runtime.sh assert PHASE | persist'
    ;;
esac
