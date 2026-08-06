#!/bin/sh
set -eu

phase=${1:-}
test "$phase" = postCreate || { echo 'lifecycle: expected postCreate phase' >&2; exit 64; }
test "$(id -un)" = developer || { echo 'lifecycle: expected developer user' >&2; exit 1; }
test "$(id -u)" -ne 0 || { echo 'lifecycle: root is not permitted' >&2; exit 1; }
test "$PWD" = /workspace || { echo 'lifecycle: expected /workspace' >&2; exit 1; }
test -w /workspace || { echo 'lifecycle: workspace is not writable' >&2; exit 1; }

cache_dir=${GOCACHE:-$HOME/.cache/go-build}
mkdir -p "$cache_dir"
test -w "$cache_dir" || { echo 'lifecycle: Go cache is not writable' >&2; exit 1; }
printf '%s\n' ready > "$cache_dir/.cyclestone-template-ready"
printf '%s\n' 'lifecycle phase=postCreate user=developer workspace=/workspace cache=ready'
