#!/bin/sh
set -eu
repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$repo_root/scripts/runtime-config-lib.sh"
runtime_config_init

test "$#" -ge 2 || runtime_fail E_USAGE 'usage: devcontainer-generate.sh PROJECT_ROOT REQUEST_FILE [--dry-run] [--replace] [--safe-mode]'
project_arg=$1
request_arg=$2
shift 2
dry_run=false
replace=false
while test "$#" -gt 0; do
  case "$1" in --dry-run) dry_run=true;; --replace) replace=true;; --safe-mode) safe_mode=true;; *) runtime_fail E_USAGE "unknown option: $1";; esac
  shift
done
render_dir=$(mktemp -d)
portable_tmp= local_tmp= portable_backup= local_backup= publish_active=false
runtime_cleanup() {
  status=$?
  if $publish_active; then
    if test -n "$local_backup" && test -f "$local_backup"; then mv -f -- "$local_backup" "$local_output" || :; else rm -f -- "$local_output"; fi
    if test -n "$portable_backup" && test -f "$portable_backup"; then mv -f -- "$portable_backup" "$portable_output" || :; else rm -f -- "$portable_output"; fi
    sync -f "$project_root/.cyclestone/runtime" >/dev/null 2>&1 || :
    sync -f "$project_root/.devcontainer" >/dev/null 2>&1 || :
  fi
  rm -f -- "${portable_tmp:-}" "${local_tmp:-}" "${portable_backup:-}" "${local_backup:-}"
  rm -rf -- "$render_dir"
  exit "$status"
}
trap runtime_cleanup EXIT HUP INT TERM
runtime_prepare_render

portable_managed=false
local_managed=false
portable_exists=false
local_exists=false
for pair in "$portable_output:$render_dir/portable.json:portable" "$local_output:$render_dir/local.json:local-runtime"; do
  destination=${pair%%:*}
  remainder=${pair#*:}; desired=${remainder%%:*}; kind=${remainder#*:}
  if test -e "$destination" || test -L "$destination"; then
    if test "$kind" = portable; then portable_exists=true; else local_exists=true; fi
    test ! -L "$destination" && test -f "$destination" || runtime_fail E_OUTPUT_PATH 'existing generated destination must be a regular file, not a link'
  fi
done
if $portable_exists && $local_exists && (runtime_validate_generated_pair "$portable_output" "$local_output") >/dev/null 2>&1; then
  portable_managed=true
  local_managed=true
elif $portable_exists || $local_exists; then
  $replace || runtime_fail E_UNMANAGED_OUTPUT 'refusing to replace an incomplete or inconsistent generated pair without --replace'
fi
if $dry_run; then
  if test -f "$portable_output"; then
    if cmp -s "$portable_output" "$render_dir/portable.json"; then :
    elif $portable_managed; then diff -u --label .devcontainer/devcontainer.json --label '.devcontainer/devcontainer.json (generated)' -- "$portable_output" "$render_dir/portable.json" || :
    elif $replace; then printf '%s\n' 'CHANGE .devcontainer/devcontainer.json (unmanaged content redacted; replacement authorized)'
    else printf '%s\n' 'CHANGE .devcontainer/devcontainer.json (unmanaged content redacted; --replace required)'; fi
  else printf '%s\n' 'CREATE .devcontainer/devcontainer.json'; fi
  if test -f "$local_output"; then
    cmp -s "$local_output" "$render_dir/local.json" || printf '%s\n' 'CHANGE .cyclestone/runtime/devcontainer.json (machine-local content redacted)'
  else printf '%s\n' 'CREATE .cyclestone/runtime/devcontainer.json (machine-local content redacted)'; fi
  exit 0
fi

runtime_test_fault before-stage
mkdir -p "$project_root/.devcontainer" "$project_root/.cyclestone/runtime"
for directory in "$project_root/.devcontainer" "$project_root/.cyclestone" "$project_root/.cyclestone/runtime"; do
  test ! -L "$directory" && test -d "$directory" || runtime_fail E_OUTPUT_PATH 'output directory must not be a symbolic link'
done
runtime_test_fault before-write
portable_tmp=$(mktemp "$project_root/.devcontainer/.devcontainer.json.XXXXXX")
local_tmp=$(mktemp "$project_root/.cyclestone/runtime/.devcontainer.json.XXXXXX")
cp "$render_dir/portable.json" "$portable_tmp" || runtime_fail E_WRITE 'cannot stage portable generated output'
runtime_test_fault after-portable-stage
cp "$render_dir/local.json" "$local_tmp" || runtime_fail E_WRITE 'cannot stage local generated output'
runtime_test_fault after-local-stage
chmod 644 "$portable_tmp"; chmod 600 "$local_tmp"
sync -f "$portable_tmp" >/dev/null 2>&1 && sync -f "$local_tmp" >/dev/null 2>&1 || runtime_fail E_WRITE 'cannot fsync staged generated output'
runtime_test_fault after-file-fsync
if test -f "$portable_output"; then
  portable_backup=$(mktemp "$project_root/.devcontainer/.devcontainer.backup.XXXXXX")
  cp -p "$portable_output" "$portable_backup" || runtime_fail E_WRITE 'cannot back up portable generated output'
fi
if test -f "$local_output"; then
  local_backup=$(mktemp "$project_root/.cyclestone/runtime/.devcontainer.backup.XXXXXX")
  cp -p "$local_output" "$local_backup" || runtime_fail E_WRITE 'cannot back up local generated output'
fi
runtime_test_pause_for_source_swap
while IFS= read -r source; do
  test -n "$source" || continue
  path=$(printf '%s' "$source" | jq -r .path)
  runtime_test_fault before-source-recheck
  test ! -L "$path" && test "$(realpath -e -- "$path")" = "$path" || runtime_fail E_SOURCE_CHANGED 'credential source changed before output replacement'
  source_type=$(printf '%s' "$source" | jq -r .type)
  if test "$source_type" = file; then test -f "$path" || runtime_fail E_SOURCE_CHANGED 'credential source type changed before output replacement'
  else test "$source_type" = directory && test -d "$path" || runtime_fail E_SOURCE_CHANGED 'credential source type changed before output replacement'; fi
  test "$(stat -c %d "$path")" = "$(printf '%s' "$source" | jq -r .device)" && test "$(stat -c %i "$path")" = "$(printf '%s' "$source" | jq -r .inode)" || runtime_fail E_SOURCE_CHANGED 'credential source identity changed before output replacement'
done <<EOF
$(jq -c '.[]' "$render_dir/sources.json")
EOF
publish_active=true
runtime_test_fault before-first-rename
mv -f -- "$local_tmp" "$local_output"; local_tmp=
runtime_test_fault after-first-rename
mv -f -- "$portable_tmp" "$portable_output"; portable_tmp=
runtime_test_fault after-second-rename
sync -f "$project_root/.cyclestone/runtime" >/dev/null 2>&1 && sync -f "$project_root/.devcontainer" >/dev/null 2>&1 || runtime_fail E_WRITE 'cannot fsync generated output directories'
runtime_test_fault after-directory-fsync
publish_active=false
rm -f -- "${portable_backup:-}" "${local_backup:-}"; portable_backup= local_backup=
printf '%s\n' 'GENERATED .devcontainer/devcontainer.json' 'GENERATED .cyclestone/runtime/devcontainer.json'
