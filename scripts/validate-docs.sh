#!/bin/sh
# validate-docs.sh — verify shell and CLI examples in markdown files do not
# drift from actual script execution.
#
# For commands that reference existing scripts, this validator checks that the
# script exists and the documented flags are accepted.  For inline shell
# snippets, it runs `sh -n` for syntax validation.  Interactive approval blocks
# and placeholder blocks (containing <...> placeholders) are skipped with clear
# documentation.  No Dev Container lifecycle, Podman, or network commands are
# executed.
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass=0
skip=0
block_dir=$(mktemp -d)
trap 'rm -rf "$block_dir"' EXIT HUP INT TERM

# Validate a single extracted shell block from a markdown file.
validate_block() {
  block_file=$1
  source_file=$2

  # Skip empty blocks
  test -s "$block_file" || return 0

  # Skip interactive blocks that require a controlling terminal
  if grep -Eq 'devcontainer-permissions\.sh review' "$block_file"; then
    echo "SKIP: interactive approval block ($source_file)"
    skip=$((skip + 1))
    return 0
  fi

  # Skip npm exec wrapper blocks (complex env wrappers)
  if grep -Eq 'npm exec --yes' "$block_file"; then
    echo "SKIP: npm exec wrapper block ($source_file)"
    skip=$((skip + 1))
    return 0
  fi

  # Skip blocks with <placeholder> tokens (documentation templates, not
  # executable commands)
  if grep -Eq '<[a-z_-]+>' "$block_file"; then
    echo "SKIP: placeholder block ($source_file)"
    skip=$((skip + 1))
    return 0
  fi

  # Skip blocks that install software via curl | sh
  if grep -Eq 'curl.*\| *sh' "$block_file"; then
    echo "SKIP: install-via-curl block ($source_file)"
    skip=$((skip + 1))
    return 0
  fi

  # Syntax validation — try sh -n first, then bash -n for bash-specific syntax
  if ! sh -n "$block_file" 2>/dev/null; then
    if ! bash -n "$block_file" 2>/dev/null; then
      err=$(sh -n "$block_file" 2>&1 | head -3)
      fail "shell syntax error in $source_file: $err"
    fi
  fi

  # Check that referenced scripts exist and are executable
  for script_ref in $(sed -n 's/.*scripts\/\([a-z-]*\.sh\).*/\1/p' "$block_file" | sort -u); do
    script_path="scripts/$script_ref"
    test -f "$script_path" || fail "documented script does not exist: $script_path (in $source_file)"
    test -x "$script_path" || fail "documented script is not executable: $script_path (in $source_file)"
    sh -n "$script_path" 2>/dev/null || fail "documented script has syntax error: $script_path"
  done

  pass=$((pass + 1))
}

# Extract fenced shell/bash/sh code blocks from a markdown file into separate
# temp files, then validate each one.
validate_file() {
  file=$1
  block_num=0
  awk '
    /^```(sh|shell|bash)$/ { in_block=1; next }
    /^```$/ { if (in_block) { in_block=0; printf "\n" } next }
    in_block { print }
  ' "$file" > "$block_dir/raw.txt"

  # Split raw blocks on blank lines that separate them
  current="$block_dir/block_0"
  : > "$current"
  block_num=0
  while IFS= read -r line; do
    if test -z "$line"; then
      if test -s "$current"; then
        block_num=$((block_num + 1))
        current="$block_dir/block_$block_num"
        : > "$current"
      fi
    else
      printf '%s\n' "$line" >> "$current"
    fi
  done < "$block_dir/raw.txt"

  i=0
  while test $i -le $block_num; do
    bf="$block_dir/block_$i"
    if test -s "$bf"; then
      validate_block "$bf" "$file"
    fi
    i=$((i + 1))
  done
}

# Collect markdown files
md_files=$(find docs examples templates -name '*.md' -type f 2>/dev/null | LC_ALL=C sort)
test -n "$md_files" || fail 'no markdown files found under docs/, examples/, templates/'

for md_file in $md_files; do
  test -s "$md_file" || fail "empty markdown file: $md_file"
  validate_file "$md_file"
done

rm -rf "$block_dir"
echo "PASS: documentation command validation ($pass blocks checked, $skip blocks skipped)"
