#!/bin/sh
set -eu

for variable in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME \
  CYCLESTONE_CONFIG_DIR CYCLESTONE_DATA_DIR; do
  value=
  eval "value=\${$variable-}"
  test -n "$value" || {
    echo "entrypoint: required environment variable $variable is empty" >&2
    exit 64
  }
done

for directory in "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" \
  "$CYCLESTONE_CONFIG_DIR" "$CYCLESTONE_DATA_DIR" /workspace; do
  case "$directory" in /*) ;; *)
    echo "entrypoint: contract path is not absolute: $directory" >&2
    exit 64
  esac
  if ! test -d "$directory" || ! test -w "$directory" || ! test -x "$directory"; then
    echo "entrypoint: contract directory is not writable and searchable: $directory" >&2
    exit 73
  fi
done

exec "$@"
