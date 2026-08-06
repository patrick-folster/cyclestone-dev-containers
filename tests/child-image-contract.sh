#!/bin/sh
set -eu

image=${IMAGE:?set IMAGE to a loaded child image}
container_cli=${CONTAINER_CLI:-docker}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

case "$container_cli" in docker|podman) ;; *) fail 'CONTAINER_CLI must be docker or podman' ;; esac

# The child inherits the base's selected toolset. cyclestone is an opt-in
# tool (INSTALL_TOOLS build arg); an empty-toolset base is contract-valid
# (docs/architecture/image-contract.md), so the cyclestone command is only a
# preserved-command requirement when the base actually installed it.
base_tools=$("$container_cli" image inspect --format '{{ index .Config.Labels "io.cyclestone.tools" }}' "$image")
base_tools=${base_tools:-}

test "$("$container_cli" image inspect --format '{{.Config.User}}' "$image")" = developer \
  || fail 'child image final USER must be developer'
test "$("$container_cli" image inspect --format '{{.Config.WorkingDir}}' "$image")" = /workspace \
  || fail 'child image WORKDIR must be /workspace'
test "$("$container_cli" image inspect --format '{{json .Config.Entrypoint}}' "$image")" = '["/usr/local/bin/cyclestone-entrypoint"]' \
  || fail 'child image must preserve the base ENTRYPOINT'
test "$("$container_cli" image inspect --format '{{json .Config.Cmd}}' "$image")" = '["/bin/bash","-l"]' \
  || fail 'child image must preserve the base CMD'

"$container_cli" run --rm "$image" sh -eu -c '
  test "$(id -un)" = developer
  test "$(id -u)" -gt 0
  test "$(id -g)" -gt 0
  test "$HOME" = /home/developer
  test "$PWD" = /workspace
  test "$XDG_CONFIG_HOME" = /home/developer/.config
  test "$XDG_CACHE_HOME" = /home/developer/.cache
  test "$XDG_DATA_HOME" = /home/developer/.local/share
  test "$CYCLESTONE_CONFIG_DIR" = /home/developer/.config/cyclestone
  test "$CYCLESTONE_DATA_DIR" = /home/developer/.local/share/cyclestone
' || fail 'child image changed identity, HOME, or public configuration paths'

# cyclestone is a preserved-command requirement only when the base installed it.
case ",${base_tools}," in *,cyclestone,*)
  "$container_cli" run --rm "$image" sh -eu -c '
    command -v cyclestone >/dev/null
    cyclestone --version >/dev/null
  ' || fail 'child image must keep the Cyclestone command available'
;; esac

"$container_cli" run --rm "$image" sh -eu -c '
  for directory in "$HOME" /workspace "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
    "$XDG_DATA_HOME" "$CYCLESTONE_CONFIG_DIR" "$CYCLESTONE_DATA_DIR"; do
    probe=$directory/.child-write-probe
    : > "$probe"
    rm -f "$probe"
  done
  actual_go_version=$(go version)
  test "$(printf "%s\n" "$actual_go_version" | awk "{print \$3}")" = "go$GO_VERSION"
  printf "go_version=%s\n" "$actual_go_version"
  temporary=$(mktemp -d /workspace/go-contract.XXXXXX)
  trap "rm -rf \"$temporary\"" EXIT
  printf "%s\n" "package main" "import \"fmt\"" "func main() { fmt.Print(\"child-sdk-ok\") }" > "$temporary/main.go"
  go build -o "$temporary/probe" "$temporary/main.go"
  probe_result=$("$temporary/probe")
  test "$probe_result" = child-sdk-ok
  printf "sdk_probe=%s\n" "$probe_result"
' || fail 'child image SDK or writable-directory contract failed'

echo "PASS: child image inheritance contract ($image)"
