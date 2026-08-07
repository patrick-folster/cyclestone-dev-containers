#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck source=images/base/versions.env
. "$repo_root/images/base/versions.env"
image=${IMAGE:-cyclestone-base:1.0.0}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

docker image inspect "$image" >/dev/null 2>&1 || fail "image is not loaded: $image"

# Read the BA-selected tool list from the image label.
installed_tools=$(docker image inspect --format '{{ index .Config.Labels "io.cyclestone.tools" }}' "$image")
test -n "$installed_tools" || installed_tools=

docker run --rm "$image" sh -eu -c '
  test "$(id -un)" = developer
  test "$(id -u)" != 0
  test "$HOME" = /home/developer
  test "$PWD" = /workspace
  test "$XDG_CONFIG_HOME" = /home/developer/.config
  test "$XDG_CACHE_HOME" = /home/developer/.cache
  test "$XDG_DATA_HOME" = /home/developer/.local/share
  test "$CYCLESTONE_CONFIG_DIR" = /home/developer/.config/cyclestone
  test "$CYCLESTONE_DATA_DIR" = /home/developer/.local/share/cyclestone
  for directory in "$HOME" /workspace "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
    "$XDG_DATA_HOME" "$CYCLESTONE_CONFIG_DIR" "$CYCLESTONE_DATA_DIR"; do
    test "$(stat -c %U:%G "$directory")" = developer:developer
    probe=$directory/.cyclestone-write-probe
    : > "$probe"
    rm -f "$probe"
  done
  for command in git ssh bash curl tar gzip unzip xz rg jq file less ps; do
    command -v "$command" >/dev/null
  done
  test -s /etc/ssl/certs/ca-certificates.crt
  ! command -v sudo >/dev/null 2>&1
' || fail 'runtime contract checks failed'

# Verify each selected tool is on PATH and reports a version.
docker run --rm "$image" sh -eu -c '
  tools="'"$installed_tools"'"
  for tool in $(printf "%s" "$tools" | tr "," " "); do
    case "$tool" in
      opencode) bin="$HOME/.opencode/bin/opencode" ;;
      codex)
        bin="$HOME/.local/bin/codex"
        test -f "$HOME/.local/bin/codex-code-mode-host"
        test -x "$HOME/.local/bin/codex-code-mode-host"
        test "$(stat -c %U:%G "$HOME/.local/bin/codex-code-mode-host")" = developer:developer
        ;;
      *) bin="$tool" ;;
    esac
    command -v "$bin" >/dev/null 2>&1 || { echo "selected tool not on PATH: $tool" >&2; exit 1; }
    "$bin" --version >/dev/null 2>&1 || { echo "selected tool failed --version: $tool" >&2; exit 1; }
  done
' || fail 'selected tool verification failed'

docker run --rm "$image" >/dev/null || fail 'default login-capable shell command failed'

if test "${IMAGE_NETWORK_TESTS:-0}" = 1; then
  docker run --rm "$image" curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
    --output /dev/null https://github.com/ || fail 'HTTPS certificate validation failed'
fi

container_name=cyclestone-signal-$$
cleanup() {
  if docker container inspect "$container_name" >/dev/null 2>&1; then
    docker rm -f "$container_name" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT HUP INT TERM
docker run --name "$container_name" -d "$image" sh -c \
  'trap "exit 42" TERM; while :; do sleep 1; done' >/dev/null
docker kill --signal TERM "$container_name" >/dev/null
exit_code=$(docker wait "$container_name")
test "$exit_code" -eq 42 || fail "PID 1 did not receive TERM (exit $exit_code)"
docker rm "$container_name" >/dev/null
trap - EXIT HUP INT TERM

echo "PASS: runtime image contract and signal forwarding ($image)"
