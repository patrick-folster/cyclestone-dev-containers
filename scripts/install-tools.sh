#!/bin/sh
# Uniform native installer/updater for Cyclestone base-image tools.
#
# Tools (all opt-in via INSTALL_TOOLS env or repeated --tool args):
#   cyclestone  GitHub releases latest v-tag, publisher checksums.txt verified
#   codex       GitHub releases latest, publisher-trusted (no client checksum)
#   agy         antigravity.google installer, --dir override, internal SHA-512 manifest
#   ollama      ollama.com installer, publisher-trusted (no client checksum)
#   opencode    opencode.ai installer, --no-modify-path, publisher-trusted (no client checksum)
#
# Subcommands:
#   install [--tool <name>]...   install selected tools (build-time default)
#   update  [--tool <name>]...   update selected tools (runtime)
#   status                         list installed tools and versions
#
# Selection defaults:
#   install           INSTALL_TOOLS env (empty default = no-op)
#   update            all user-installable tools: cyclestone,codex,agy,opencode
#                     (ollama excluded: root system install, requires rebuild)
#   --tool <name>     overrides the per-command default; repeatable
#
# Environment:
#   INSTALL_TOOLS   comma-separated tool selection (read only by `install`)
#   DESTDIR         staging root for build-time install (default empty = /)
#   TARGETOS        build target OS (default derived from uname)
#   TARGETARCH      build target arch (default derived from uname)
#   PATH            used to locate curl, tar, etc.
#
# Exit codes: 0 success; 1 generic failure; 64 usage error.
set -eu

fail() {
  echo "install-tools: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

detect_os() {
  os=$(uname -s)
  case "$os" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) fail "unsupported OS: $os" ;;
  esac
  printf '%s' "$os"
}

detect_arch() {
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) fail "unsupported architecture: $arch" ;;
  esac
  printf '%s' "$arch"
}

TARGETOS=${TARGETOS:-$(detect_os)}
TARGETARCH=${TARGETARCH:-$(detect_arch)}
test "$TARGETOS" = linux || fail "unsupported target OS: $TARGETOS"

# ---------------------------------------------------------------------------
# Tool selection parsing
# ---------------------------------------------------------------------------

VALID_TOOLS="cyclestone codex agy ollama opencode"

# Tools that `cyclestone-tools update` can update at runtime as the non-root
# developer user. Ollama is excluded: it installs to /usr/local/bin as root
# and runtime updates are unsupported (requires image rebuild).
USER_INSTALLABLE_TOOLS="cyclestone,codex,agy,opencode"

is_valid_tool() {
  candidate=$1
  case " $VALID_TOOLS " in
    *" $candidate "*) return 0 ;;
    *) return 1 ;;
  esac
}

# normalize_tools <default> <read_env> [--tool <name>]...
#
# Build a normalized, deduped, order-preserving comma-list of tools on stdout.
#   $1 default  selection used when no --tool args yield anything (may be empty)
#   $2 read_env 1 = seed selection from INSTALL_TOOLS env (build-time install);
#               0 = ignore INSTALL_TOOLS (runtime update: it is a build record,
#                     not a runtime update selector)
# Remaining args are parsed for repeatable --tool <name> options.
# Empty final selection is valid (caller decides whether to no-op).
normalize_tools() {
  default=$1; shift
  read_env=$1; shift
  raw=
  if test "$read_env" = 1; then raw=${INSTALL_TOOLS:-}; fi
  for arg in "$@"; do
    case "$arg" in
      --tool) shift_next=1 ;;
      *) test -n "${shift_next:-}" || continue
         shift_next=
         test -n "$arg" || continue
         if test -z "$raw"; then raw=$arg; else raw="$raw,$arg"; fi ;;
    esac
  done
  test -z "${shift_next:-}" || fail "--tool requires a value"
  test -n "$raw" || raw=$default
  # Normalize: strip whitespace, dedupe, preserve order, drop empties
  seen=
  result=
  IFS=','
  for item in $raw; do
    item=$(printf '%s' "$item" | tr -d ' \t\n')
    test -n "$item" || continue
    is_valid_tool "$item" || fail "unknown tool: $item"
    case ",$seen," in
      *",$item,"*) ;;
      *) if test -z "$result"; then result=$item; else result="$result,$item"; fi
         seen="$seen,$item" ;;
    esac
  done
  unset IFS
  printf '%s' "$result"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

secure_curl() {
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --fail --silent --show-error --location "$@"
}

gh_latest_tag() {
  # $1 = repo (e.g. patrick-folster/cyclestone)
  # Prints tag_name (e.g. v0.0.4 or rust-v0.146.0)
  repo=$1
  require_cmd curl
  secure_curl --output - "https://api.github.com/repos/$repo/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
}

temp_dir() {
  mktemp -d
}

cleanup_temp() {
  test -n "${1:-}" && test "$1" != / && rm -rf -- "$1"
}

install_file() {
  # install_file <src> <dest> <mode>
  src=$1 dest=$2 mode=$3
  mkdir -p "$(dirname -- "$dest")"
  install -m "$mode" "$src" "$dest.new"
  mv -f "$dest.new" "$dest"
}

prefix_for_system() {
  printf '%s' "${DESTDIR:-}/usr/local/bin"
}

prefix_for_user() {
  # Per-user install root, honoring HOME
  printf '%s' "${HOME:-/home/developer}/.local/bin"
}

# ---------------------------------------------------------------------------
# Cyclestone (GitHub releases, publisher checksums.txt verified)
# ---------------------------------------------------------------------------

install_cyclestone() {
  prefix=$1
  require_cmd curl
  require_cmd tar
  require_cmd sha256sum

  tag=$(gh_latest_tag patrick-folster/cyclestone)
  test -n "$tag" || fail "could not resolve latest cyclestone release tag"
  case "$tag" in v*) version=${tag#v} ;; *) version=$tag ;; esac

  base_url="https://github.com/patrick-folster/cyclestone/releases/download/$tag"
  case "$TARGETARCH" in
    amd64) archive=cyclestone_${version}_linux_amd64.tar.gz ;;
    arm64) archive=cyclestone_${version}_linux_arm64.tar.gz ;;
    *) fail "unsupported cyclestone architecture: $TARGETARCH" ;;
  esac
  checksums_file=checksums.txt

  work=$(temp_dir)
  trap "cleanup_temp '$work'" EXIT HUP INT TERM

  # Download publisher checksum document
  secure_curl --output "$work/$checksums_file" "$base_url/$checksums_file"
  test -s "$work/$checksums_file" || fail "empty publisher checksum document"

  # Parse exactly one matching record
  record_count=$(awk -v fn="$archive" \
    '$2 == fn || $2 == "*" fn { count++ } END { print count + 0 }' \
    "$work/$checksums_file")
  test "$record_count" -eq 1 || fail "publisher checksum document must contain exactly one record for $archive"
  published_sha=$(awk -v fn="$archive" \
    '$2 == fn || $2 == "*" fn { print $1 }' "$work/$checksums_file")

  # Download archive
  archive_path=$work/$archive
  secure_curl --output "$archive_path" "$base_url/$archive"

  # Verify archive digest against publisher checksum
  printf '%s  %s\n' "$published_sha" "$archive_path" | sha256sum -c - >/dev/null \
    || fail "cyclestone archive digest mismatch"

  # Inspect archive members
  members=$work/members
  tar -tzf "$archive_path" | LC_ALL=C sort > "$members"
  expected_members=$work/expected
  cat > "$expected_members" <<'EOF'
CHANGELOG.md
LICENSE.md
README.md
cyclestone
EOF
  cmp -s "$expected_members" "$members" || fail "cyclestone archive contains unexpected or missing members"
  tar -tzvf "$archive_path" \
    | awk 'substr($1, 1, 1) != "-" { bad=1 } END { exit bad }' \
    || fail "cyclestone archive contains a non-regular member"

  # Extract and install
  # License directory tracks the install prefix: user installs (the only
  # context now) go to ${prefix_parent}/share/licenses/cyclestone, i.e.
  # ~/.local/share/licenses/cyclestone (writable by developer).
  case "$prefix" in
    */bin) license_dir=$(dirname -- "$prefix")/share/licenses/cyclestone ;;
    *) license_dir=${DESTDIR:-}/usr/local/share/licenses/cyclestone ;;
  esac
  extracted=$work/extracted
  mkdir -p "$extracted" "$prefix" "$license_dir"
  tar -xzf "$archive_path" --no-same-owner --no-same-permissions \
    -C "$extracted" -- cyclestone LICENSE.md
  test -f "$extracted/cyclestone" && ! test -L "$extracted/cyclestone" \
    || fail "expected regular cyclestone executable was not extracted"
  install_file "$extracted/cyclestone" "$prefix/cyclestone" 0755
  install -m 0644 "$extracted/LICENSE.md" "$license_dir/LICENSE.md"

  # Verify installed version reports the resolved tag version
  # Verify installed version reports the resolved tag version.
  # Strip SemVer build metadata (e.g. "0.0.4+dirty" -> "0.0.4") for comparison.
  installed_version=$("$prefix/cyclestone" --version | awk '{print $NF}' | sed 's/^v//' | sed 's/+.*//')
  test "$installed_version" = "$version" \
    || fail "installed cyclestone version mismatch: $installed_version != $version"

  trap - EXIT HUP INT TERM
  cleanup_temp "$work"
}

update_cyclestone() {
  # RT update installs to user prefix; system copy left as-is.
  user_prefix=$(prefix_for_user)
  install_cyclestone "$user_prefix"
}

status_cyclestone() {
  bin=
  for candidate in /usr/local/bin/cyclestone "$(prefix_for_user)/cyclestone"; do
    if command -v "$candidate" >/dev/null 2>&1 || test -x "$candidate"; then
      bin=$candidate
      break
    fi
  done
  if test -n "$bin"; then
    ver=$("$bin" --version 2>/dev/null | awk '{print $NF}' | sed 's/^v//') || ver=unknown
    printf 'cyclestone\t%s\t%s\n' "$ver" "$bin"
  fi
}

# ---------------------------------------------------------------------------
# Codex (GitHub releases latest, publisher-trusted, no client checksum)
# ---------------------------------------------------------------------------

install_codex() {
  prefix=$1
  require_cmd curl
  require_cmd tar

  case "$TARGETARCH" in
    amd64) target=x86_64-unknown-linux-musl ;;
    arm64) target=aarch64-unknown-linux-musl ;;
    *) fail "unsupported codex architecture: $TARGETARCH" ;;
  esac
  archive=codex-$target.tar.gz
  url="https://github.com/openai/codex/releases/latest/download/$archive"

  work=$(temp_dir)
  trap "cleanup_temp '$work'" EXIT HUP INT TERM

  secure_curl --output "$work/$archive" "$url"
  test -s "$work/$archive" || fail "empty codex archive download"

  # Inspect members: reject unsafe paths; expect a single binary member.
  members=$work/members
  tar -tzf "$work/$archive" > "$members" || fail "unreadable codex archive"
  # Reject absolute/parent/symlink/device members
  if awk '/^\// { exit 1 } { split($0, c, "/"); for (i=1; i<=length(c); i++) if (c[i] == "..") exit 1 }' "$members"; then
    :
  else
    fail "codex archive contains unsafe absolute or parent path"
  fi
  tar -tzvf "$work/$archive" \
    | awk 'substr($1, 1, 1) != "-" { bad=1 } END { exit bad }' \
    || fail "codex archive contains a non-regular member"

  mkdir -p "$prefix"
  # Extract and rename the single binary member to 'codex'.
  extracted=$work/extracted
  mkdir -p "$extracted"
  tar -xzf "$work/$archive" --no-same-owner --no-same-permissions -C "$extracted"
  member=$(cd "$extracted" && ls -1 | head -n 1)
  test -n "$member" || fail "codex archive is empty"
  test -f "$extracted/$member" || fail "codex archive member is not a regular file"
  install_file "$extracted/$member" "$prefix/codex" 0755

  trap - EXIT HUP INT TERM
  cleanup_temp "$work"
}

update_codex() {
  install_codex "$(prefix_for_user)"
}

status_codex() {
  bin=
  for candidate in /usr/local/bin/codex "$(prefix_for_user)/codex"; do
    if command -v "$candidate" >/dev/null 2>&1 || test -x "$candidate"; then
      bin=$candidate
      break
    fi
  done
  if test -n "$bin"; then
    ver=$("$bin" --version 2>/dev/null | head -n 1 | awk '{print $NF}' | sed 's/^v//') || ver=unknown
    printf 'codex\t%s\t%s\n' "$ver" "$bin"
  fi
}

# ---------------------------------------------------------------------------
# Agy (antigravity.google installer, --dir override, internal SHA-512)
# ---------------------------------------------------------------------------

install_agy() {
  prefix=$1
  require_cmd curl
  require_cmd tar

  installer_url="https://antigravity.google/cli/install.sh"
  work=$(temp_dir)
  trap "cleanup_temp '$work'" EXIT HUP INT TERM

  secure_curl --output "$work/install.sh" "$installer_url"
  test -s "$work/install.sh" || fail "empty agy installer download"
  # Shell-check the installer is a valid script header
  head -n 1 "$work/install.sh" | grep -Eq '^#! */(usr/bin/env +)?(usr/)?bin/(bash|sh)|^#! */usr/bin/env +(bash|sh)' \
    || fail "agy installer does not look like a shell script"

  # The installer honors --dir <path>; default is ~/.local/bin.
  # The agy installer uses bash-specific syntax (set -euo pipefail).
  require_cmd bash
  mkdir -p "$prefix"
  bash "$work/install.sh" --dir "$prefix"
  test -x "$prefix/agy" || fail "agy binary not installed at $prefix"

  trap - EXIT HUP INT TERM
  cleanup_temp "$work"
}

update_agy() {
  prefix=$(prefix_for_user)
  # agy installer refuses to overwrite an existing binary; remove first for fresh install.
  rm -f "$prefix/agy"
  install_agy "$prefix"
}

status_agy() {
  bin=
  for candidate in /usr/local/bin/agy "$(prefix_for_user)/agy"; do
    if command -v "$candidate" >/dev/null 2>&1 || test -x "$candidate"; then
      bin=$candidate
      break
    fi
  done
  if test -n "$bin"; then
    ver=$("$bin" --version 2>/dev/null | head -n 1 | awk '{print $NF}' | sed 's/^v//') || ver=unknown
    printf 'agy\t%s\t%s\n' "$ver" "$bin"
  fi
}

# ---------------------------------------------------------------------------
# Ollama (ollama.com installer, root-aware, publisher-trusted)
# ---------------------------------------------------------------------------

install_ollama() {
  prefix=$1
  require_cmd curl

  installer_url="https://ollama.com/install.sh"
  work=$(temp_dir)
  trap "cleanup_temp '$work'" EXIT HUP INT TERM

  secure_curl --output "$work/install.sh" "$installer_url"
  test -s "$work/install.sh" || fail "empty ollama installer download"
  head -n 1 "$work/install.sh" | grep -Eq '^#! */(usr/bin/env +)?(usr/)?bin/(bash|sh)|^#! */usr/bin/env +(bash|sh)' \
    || fail "ollama installer does not look like a shell script"

  # The ollama installer writes to /usr/local/bin/ollama when root.
  # When non-root it may fail or install to a user path; document root requirement.
  if [ "$(id -u)" != 0 ]; then
    fail "ollama install requires root (system service binary at $prefix)"
  fi
  sh "$work/install.sh"
  test -x "$prefix/ollama" || fail "ollama binary not installed at $prefix"

  trap - EXIT HUP INT TERM
  cleanup_temp "$work"
}

update_ollama() {
  fail "ollama runtime update is not supported (system install requires root and image rebuild)"
}

status_ollama() {
  bin=
  for candidate in /usr/local/bin/ollama "$(prefix_for_user)/ollama"; do
    if command -v "$candidate" >/dev/null 2>&1 || test -x "$candidate"; then
      bin=$candidate
      break
    fi
  done
  if test -n "$bin"; then
    ver=$("$bin" --version 2>/dev/null | head -n 1 | awk '{print $NF}' | sed 's/^v//') || ver=unknown
    printf 'ollama\t%s\t%s\n' "$ver" "$bin"
  fi
}

# ---------------------------------------------------------------------------
# OpenCode (opencode.ai installer, --no-modify-path, publisher-trusted)
# ---------------------------------------------------------------------------

install_opencode() {
  # opencode installer hardcodes $HOME/.opencode/bin; no --dir override.
  # Installs into the current user's home. Caller should ensure HOME is set.
  require_cmd curl
  require_cmd tar

  installer_url="https://opencode.ai/install"
  work=$(temp_dir)
  trap "cleanup_temp '$work'" EXIT HUP INT TERM

  secure_curl --output "$work/install.sh" "$installer_url"
  test -s "$work/install.sh" || fail "empty opencode installer download"
  head -n 1 "$work/install.sh" | grep -Eq '^#! */(usr/bin/env +)?(usr/)?bin/(bash|sh)|^#! */usr/bin/env +(bash|sh)' \
    || fail "opencode installer does not look like a shell script"

  # Use --no-modify-path: we set PATH via ENV in the image.
  # The opencode installer uses bash-specific syntax (set -euo pipefail).
  require_cmd bash
  bash "$work/install.sh" --no-modify-path
  opencode_bin="${HOME:-/home/developer}/.opencode/bin/opencode"
  test -x "$opencode_bin" || fail "opencode binary not installed at $opencode_bin"

  trap - EXIT HUP INT TERM
  cleanup_temp "$work"
}

update_opencode() {
  # Re-run installer; it self-updates if version already current.
  install_opencode
}

status_opencode() {
  bin="${HOME:-/home/developer}/.opencode/bin/opencode"
  if command -v "$bin" >/dev/null 2>&1 || test -x "$bin"; then
    ver=$("$bin" --version 2>/dev/null | head -n 1 | awk '{print $NF}' | sed 's/^v//') || ver=unknown
    printf 'opencode\t%s\t%s\n' "$ver" "$bin"
  fi
}

# ---------------------------------------------------------------------------
# Per-tool dispatch
# ---------------------------------------------------------------------------

run_install_tool() {
  tool=$1
  case "$tool" in
    ollama)
      # System tool: install to DESTDIR/usr/local/bin at build, or /usr/local/bin at RT root.
      # Ollama is a system service binary and requires root at build time.
      prefix=$(prefix_for_system)
      "install_$tool" "$prefix"
      ;;
    cyclestone|codex|agy|opencode)
      # User tools: install under $HOME (cyclestone/codex/agy to
      # ~/.local/bin/<tool>; opencode to ~/.opencode/bin/opencode hardcoded).
      # These must run as the developer user, not root, so the resulting
      # files/dirs are owned by developer and the runtime
      # `cyclestone-tools update` shadowing works. agy in particular hardcodes
      # a staging tree under $HOME/.cache/antigravity and leaves the dirs
      # behind on exit; a root install would persist root-owned staging the
      # non-root developer cannot write into at runtime (curl exit 23).
      "install_$tool" "$(prefix_for_user)"
      ;;
    *) fail "unknown tool in install dispatch: $tool" ;;
  esac
}

run_update_tool() {
  tool=$1
  case "$tool" in
    ollama) "update_$tool" ;;
    *) "update_$tool" ;;
  esac
}

run_status_tool() {
  tool=$1
  "status_$tool" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_install() {
  tools=$(normalize_tools "" 1 "$@")
  test -n "$tools" || { echo "install-tools: no tools selected; nothing to do"; return 0; }
  IFS=','
  set -- $tools
  unset IFS
  for tool in "$@"; do
    echo "install-tools: installing $tool ..."
    run_install_tool "$tool"
    echo "install-tools: installed $tool"
  done
}

cmd_update() {
  # Runtime update default: all user-installable tools (cyclestone, codex,
  # agy, opencode). Ollama is excluded (root system install; requires
  # rebuild). INSTALL_TOOLS is a build-time record, not a runtime update
  # selector, so it is ignored by `update`.
  tools=$(normalize_tools "$USER_INSTALLABLE_TOOLS" 0 "$@")
  test -n "$tools" || { echo "install-tools: no tools selected; nothing to do"; return 0; }
  IFS=','
  set -- $tools
  unset IFS
  for tool in "$@"; do
    echo "install-tools: updating $tool ..."
    run_update_tool "$tool"
    echo "install-tools: updated $tool"
  done
}

cmd_status() {
  for tool in cyclestone codex agy ollama opencode; do
    run_status_tool "$tool"
  done
}

usage() {
  cat <<'EOF'
Usage: install-tools.sh <command> [options]

Commands:
  install [--tool <name>]...   Install selected tools (build-time)
  update  [--tool <name>]...   Update selected tools (runtime)
  status                        List installed tools and versions

Tools: cyclestone codex agy ollama opencode

Selection:
  --tool <name>     Repeatable; overrides the per-command default
  INSTALL_TOOLS     Comma-separated tool list, read only by `install`
                   (build-time selection; ignored by `update`)

Defaults:
  install           INSTALL_TOOLS env (empty default = no-op)
  update            cyclestone,codex,agy,opencode (ollama excluded;
                    requires root and image rebuild)

Environment:
  DESTDIR           Staging root for build-time install (default empty = /)
  TARGETOS          Target OS (default derived)
  TARGETARCH        Target arch (default derived)
  HOME              User home for per-user tool installs (opencode)

Exit codes: 0 success; 1 failure; 64 usage error
EOF
}

# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

subcommand=${1:-}
test $# -gt 0 && shift || true
case "$subcommand" in
  install) cmd_install "$@" ;;
  update)  cmd_update "$@" ;;
  status)  cmd_status ;;
  # Test passthrough: forward <default> <read_env> [--tool <name>]... to
  # normalize_tools and print the result. Used by tests/install-tools.sh to
  # unit-test selection logic without invoking network-touching installs.
  _normalize_test) normalize_tools "$@" ;;
  -h|--help|help) usage ;;
  "") usage; exit 64 ;;
  *) echo "install-tools: unknown subcommand: $subcommand" >&2; usage >&2; exit 64 ;;
esac