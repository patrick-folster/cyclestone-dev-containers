#!/bin/sh
set -eu
repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_root/scripts/runtime-config-lib.sh"
runtime_config_init

project_arg=
request_arg=
while test "$#" -gt 0; do
  case "$1" in
    --safe-mode) safe_mode=true;;
    *)
      if test -z "${project_arg:-}"; then project_arg=$1
      elif test -z "${request_arg:-}"; then request_arg=$1
      else runtime_fail E_USAGE "unknown option or extra argument: $1"; fi
      ;;
  esac
  shift
done
test -n "${project_arg:-}" && test -n "${request_arg:-}" || runtime_fail E_USAGE 'usage: devcontainer-validate.sh PROJECT_ROOT REQUEST_FILE [--safe-mode]'
render_dir=$(mktemp -d)
trap 'rm -rf -- "$render_dir"' EXIT HUP INT TERM
runtime_prepare_render

for candidate in "$portable_output" "$local_output"; do
  test -e "$candidate" || runtime_fail E_OUTPUT_MISSING 'both generated output files are required; run devcontainer-generate.sh first'
  test ! -L "$candidate" && test -f "$candidate" || runtime_fail E_OUTPUT_PATH 'generated output must be a regular file, not a link or directory'
done
runtime_validate_generated_pair "$portable_output" "$local_output"
cmp -s "$portable_output" "$render_dir/portable.json" || runtime_fail E_METADATA_STALE 'portable generated output is stale, tampered, or inconsistent'
cmp -s "$local_output" "$render_dir/local.json" || runtime_fail E_METADATA_STALE 'local generated output is stale, tampered, or inconsistent'
printf 'PASS: runtime configuration inputs, grants, prerequisites, rendered JSON, and Dev Container CLI 0.86.0 validation\n'
