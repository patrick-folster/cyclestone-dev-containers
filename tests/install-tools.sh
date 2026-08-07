#!/bin/sh
# Tests for the uniform native tool installer (scripts/install-tools.sh).
#
# Covers:
#   - empty selection no-op
#   - cyclestone install with mocked GitHub API + fixtures (pinned v-tag)
#   - cyclestone hostile-fixture rejection (tampered archive, checksum mismatch,
#     symlink member, missing publisher record, duplicate record)
#   - paired Codex install/update/repair, rollback, and architecture mapping
#   - selection parsing (INSTALL_TOOLS env, --tool args, dedupe, unknown tool)
#
# All network access is mocked via a curl stub that serves local fixtures.
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
installer=$repo_root/scripts/install-tools.sh
test_root=$(mktemp -d)
cleanup() {
  test -n "${test_root:-}" && test "$test_root" != / && rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

make_cyclestone_archive() {
  fixture=$1
  kind=${2:-regular}
  version=${3:-0.0.4}
  tag=v$version
  mkdir -p "$fixture/content"
  printf '#!/bin/sh\necho "Cyclestone v%s"\n' "$version" > "$fixture/content/cyclestone"
  chmod 0755 "$fixture/content/cyclestone"
  printf 'license\n' > "$fixture/content/LICENSE.md"
  printf 'readme\n' > "$fixture/content/README.md"
  printf 'changes\n' > "$fixture/content/CHANGELOG.md"
  if test "$kind" = symlink; then
    rm -f "$fixture/content/cyclestone"
    ln -s README.md "$fixture/content/cyclestone"
  fi
  archive_name=cyclestone_${version}_linux_amd64.tar.gz
  tar -czf "$fixture/$archive_name" \
    -C "$fixture/content" CHANGELOG.md LICENSE.md README.md cyclestone
  # GitHub API JSON fixture: releases/latest returns tag_name + assets.
  cat > "$fixture/cyclestone-release.json" <<EOF
{"tag_name":"$tag","name":"$version","assets":[]}
EOF
}

make_cyclestone_checksums() {
  fixture=$1
  version=${2:-0.0.4}
  archive_name=cyclestone_${version}_linux_amd64.tar.gz
  archive_sha=$(sha256sum "$fixture/$archive_name" | awk '{print $1}')
  printf '%s  %s\n' "$archive_sha" "$archive_name" > "$fixture/checksums.txt"
  printf '%s\n' "$archive_sha"
}

make_codex_pair() {
  fixture=$1
  version=${2:-0.146.0}
  target=${3:-x86_64-unknown-linux-musl}
  marker=${4:-$version}
  mkdir -p "$fixture/codex-content-$target"
  printf '#!/bin/sh\necho "codex-cli %s"\n# %s\n' "$version" "$marker" \
    > "$fixture/codex-content-$target/codex-$target"
  printf '#!/bin/sh\necho "code-mode-host %s"\n' "$marker" \
    > "$fixture/codex-content-$target/codex-code-mode-host-$target"
  chmod 0755 \
    "$fixture/codex-content-$target/codex-$target" \
    "$fixture/codex-content-$target/codex-code-mode-host-$target"
  tar -czf "$fixture/codex-$target.tar.gz" \
    -C "$fixture/codex-content-$target" "codex-$target"
  tar -czf "$fixture/codex-code-mode-host-$target.tar.gz" \
    -C "$fixture/codex-content-$target" "codex-code-mode-host-$target"
  cat > "$fixture/codex-release.json" <<EOF
{"tag_name":"rust-v$version","name":"$version","assets":[]}
EOF
}

# ---------------------------------------------------------------------------
# curl stub: serves local fixture files by URL and basename
# ---------------------------------------------------------------------------

make_curl_stub() {
  stub_dir=$1
  mkdir -p "$stub_dir"
  cat > "$stub_dir/curl" <<'EOF'
#!/bin/sh
set -eu
output=
url=
while test "$#" -gt 0; do
  case "$1" in
    --output) output=$2; shift 2 ;;
    -o) output=$2; shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
# Resolve fixture by URL basename; GitHub API responses use a special map.
base=${url##*/}
if test "${CURL_FAIL_BASENAME:-}" = "$base"; then
  echo "injected curl failure for $base" >&2
  exit 22
fi
case "$base" in
  install.sh|install)
    case "$url" in
      *antigravity.google*) payload="$FIXTURE_DIR/agy-install.sh" ;;
      *opencode.ai*) payload="$FIXTURE_DIR/opencode-install.sh" ;;
      *ollama.com*) payload="$FIXTURE_DIR/ollama-install.sh" ;;
      *) payload="$FIXTURE_DIR/${INSTALLER_FIXTURE:-install.sh}" ;;
    esac
    ;;
  latest)
    case "$url" in
      *patrick-folster/cyclestone*) payload="$FIXTURE_DIR/cyclestone-release.json" ;;
      *openai/codex*) payload="$FIXTURE_DIR/codex-release.json" ;;
      *) payload="$FIXTURE_DIR/release.json" ;;
    esac
    ;;
  *)
    payload="$FIXTURE_DIR/$base"
    ;;
esac
if test -z "$output" || test "$output" = -; then
  cat "$payload"
else
  cp "$payload" "$output"
fi
EOF
  chmod 0755 "$stub_dir/curl"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_installer() {
  # run_installer <fixture_dir> <destination> <env...> -- <args...>
  # <destination> is used as a sandboxed HOME: all user tools now install under
  # $HOME (cyclestone/codex/agy to ~/.local/bin, opencode to ~/.opencode/bin),
  # so assertions check under <destination>/.local/bin (and .local/share, .opencode).
  # DESTDIR is also set for any future system-tool (ollama) test coverage.
  fixture=$1; shift
  destination=$1; shift
  env_vars=
  while test $# -gt 0; do
    case "$1" in
      --) shift; break ;;
      *) env_vars="$env_vars $1"; shift ;;
    esac
  done
  PATH="$test_root/bin:$PATH" \
    FIXTURE_DIR="$fixture" \
    DESTDIR="$destination" \
    HOME="$destination" \
    TARGETOS=linux TARGETARCH=amd64 \
    env $env_vars "$installer" "$@"
}

expect_failure() {
  description=$1
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$description unexpectedly succeeded"
  fi
}

assert_codex_pair() {
  destination=$1
  version=$2
  target=${3:-x86_64-unknown-linux-musl}
  bin_dir=$destination/.local/bin
  test -f "$bin_dir/codex" && test -x "$bin_dir/codex" \
    || fail 'codex is not a regular executable file'
  test -f "$bin_dir/codex-code-mode-host" && test -x "$bin_dir/codex-code-mode-host" \
    || fail 'codex-code-mode-host is not a regular executable file'
  test "$("$bin_dir/codex" --version | awk '{print $NF}')" = "$version" \
    || fail "codex does not report expected version $version"
  metadata=$bin_dir/.codex-install-metadata
  test -f "$metadata" || fail 'codex installation metadata is missing'
  grep -Fx "version=$version" "$metadata" >/dev/null \
    || fail "metadata does not record Codex $version"
  grep -Fx "target=$target" "$metadata" >/dev/null \
    || fail "metadata does not record Codex target $target"
  main_sha=$(sha256sum "$bin_dir/codex" | awk '{print $1}')
  host_sha=$(sha256sum "$bin_dir/codex-code-mode-host" | awk '{print $1}')
  grep -Fx "codex_sha256=$main_sha" "$metadata" >/dev/null \
    || fail 'metadata main-binary hash is stale'
  grep -Fx "codex_code_mode_host_sha256=$host_sha" "$metadata" >/dev/null \
    || fail 'metadata host hash is stale'
}

codex_pair_hashes() {
  destination=$1
  sha256sum \
    "$destination/.local/bin/codex" \
    "$destination/.local/bin/codex-code-mode-host" \
    "$destination/.local/bin/.codex-install-metadata"
}

# ---------------------------------------------------------------------------
# Test 1: empty selection is a valid no-op
# ---------------------------------------------------------------------------

make_curl_stub "$test_root/bin"

empty_out=$test_root/out-empty
INSTALL_TOOLS="" run_installer "$test_root" "$empty_out" -- install
test ! -e "$empty_out/.local/bin/cyclestone" || fail 'empty selection installed a tool'
echo "PASS: empty selection is a no-op"

# ---------------------------------------------------------------------------
# Test 2: cyclestone install with valid fixture
# ---------------------------------------------------------------------------

good=$test_root/good
make_cyclestone_archive "$good" regular 0.0.4
good_archive_sha=$(make_cyclestone_checksums "$good" 0.0.4)
good_out=$test_root/out-good
INSTALL_TOOLS="cyclestone" run_installer "$good" "$good_out" -- install
test -x "$good_out/.local/bin/cyclestone" || fail 'valid cyclestone executable was not installed'
test -f "$good_out/.local/share/licenses/cyclestone/LICENSE.md" || fail 'cyclestone license was not retained'
echo "PASS: cyclestone install with valid fixture"

# ---------------------------------------------------------------------------
# Test 3: cyclestone hostile fixtures
# ---------------------------------------------------------------------------

# 3a: altered archive (checksum mismatch)
altered=$test_root/altered
make_cyclestone_archive "$altered" regular 0.0.4
printf 'tampered\n' >> "$altered/content/README.md"
tar -czf "$altered/cyclestone_0.0.4_linux_amd64.tar.gz" \
  -C "$altered/content" CHANGELOG.md LICENSE.md README.md cyclestone
altered_archive_sha=$(sha256sum "$altered/cyclestone_0.0.4_linux_amd64.tar.gz" | awk '{print $1}')
printf '%s  %s\n' "$good_archive_sha" cyclestone_0.0.4_linux_amd64.tar.gz > "$altered/checksums.txt"
expect_failure 'altered archive rejected' \
  env INSTALL_TOOLS="cyclestone" run_installer "$altered" "$test_root/out-altered" -- install

# 3b: missing publisher record
missing=$test_root/missing
make_cyclestone_archive "$missing" regular 0.0.4
printf '%s  unrelated.tar.gz\n' "$good_archive_sha" > "$missing/checksums.txt"
expect_failure 'missing publisher record rejected' \
  env INSTALL_TOOLS="cyclestone" run_installer "$missing" "$test_root/out-missing" -- install

# 3c: duplicate publisher record
duplicate=$test_root/duplicate
make_cyclestone_archive "$duplicate" regular 0.0.4
printf '%s  %s\n%s  %s\n' \
  "$good_archive_sha" cyclestone_0.0.4_linux_amd64.tar.gz \
  "$good_archive_sha" cyclestone_0.0.4_linux_amd64.tar.gz > "$duplicate/checksums.txt"
expect_failure 'duplicate publisher record rejected' \
  env INSTALL_TOOLS="cyclestone" run_installer "$duplicate" "$test_root/out-duplicate" -- install

# 3d: unsafe archive member (symlink)
unsafe=$test_root/unsafe
make_cyclestone_archive "$unsafe" symlink 0.0.4
unsafe_archive_sha=$(sha256sum "$unsafe/cyclestone_0.0.4_linux_amd64.tar.gz" | awk '{print $1}')
printf '%s  %s\n' "$unsafe_archive_sha" cyclestone_0.0.4_linux_amd64.tar.gz > "$unsafe/checksums.txt"
expect_failure 'unsafe archive member rejected' \
  env INSTALL_TOOLS="cyclestone" run_installer "$unsafe" "$test_root/out-unsafe" -- install

echo "PASS: cyclestone hostile-fixture rejection"

# ---------------------------------------------------------------------------
# Test 4: Codex installs and repairs one release-matched executable pair
# ---------------------------------------------------------------------------

codex_fixture=$test_root/codex
make_codex_pair "$codex_fixture" 0.146.0
codex_out=$test_root/out-codex
INSTALL_TOOLS="codex" run_installer "$codex_fixture" "$codex_out" -- install
assert_codex_pair "$codex_out" 0.146.0

# Repeating install is idempotent and retains a complete, matching pair.
first_pair_hashes=$(codex_pair_hashes "$codex_out")
INSTALL_TOOLS="codex" run_installer "$codex_fixture" "$codex_out" -- install
test "$(codex_pair_hashes "$codex_out")" = "$first_pair_hashes" \
  || fail 'repeated Codex install changed identical release contents'

# Updating an older matching pair replaces both artifacts from one new release.
make_codex_pair "$codex_fixture" 0.147.0 x86_64-unknown-linux-musl fresh-0.147.0
run_installer "$codex_fixture" "$codex_out" -- update --tool codex
assert_codex_pair "$codex_out" 0.147.0
grep -F 'fresh-0.147.0' "$codex_out/.local/bin/codex" >/dev/null \
  || fail 'Codex main binary was not updated'
test "$("$codex_out/.local/bin/codex-code-mode-host")" = 'code-mode-host fresh-0.147.0' \
  || fail 'Codex code-mode host was not updated'

# A current main with a missing or non-executable host must be repaired.
rm -f "$codex_out/.local/bin/codex-code-mode-host"
run_installer "$codex_fixture" "$codex_out" -- update --tool codex
assert_codex_pair "$codex_out" 0.147.0
chmod 0644 "$codex_out/.local/bin/codex-code-mode-host"
run_installer "$codex_fixture" "$codex_out" -- update --tool codex
assert_codex_pair "$codex_out" 0.147.0

# Stale/mismatched contents and metadata are replaced as a complete unit.
printf '#!/bin/sh\necho stale-host\n' > "$codex_out/.local/bin/codex-code-mode-host"
chmod 0755 "$codex_out/.local/bin/codex-code-mode-host"
sed 's/version=0.147.0/version=0.145.0/' \
  "$codex_out/.local/bin/.codex-install-metadata" \
  > "$codex_out/.local/bin/.codex-install-metadata.tmp"
mv "$codex_out/.local/bin/.codex-install-metadata.tmp" \
  "$codex_out/.local/bin/.codex-install-metadata"
run_installer "$codex_fixture" "$codex_out" -- update --tool codex
assert_codex_pair "$codex_out" 0.147.0
echo "PASS: Codex fresh install, idempotence, update, and repair"

# Download and validation failures must leave all installed state unchanged.
stable_pair_hashes=$(codex_pair_hashes "$codex_out")
main_archive=codex-x86_64-unknown-linux-musl.tar.gz
host_archive=codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz
expect_failure 'Codex main download failure' \
  env CURL_FAIL_BASENAME="$main_archive" INSTALL_TOOLS=codex \
  run_installer "$codex_fixture" "$codex_out" -- update --tool codex
test "$(codex_pair_hashes "$codex_out")" = "$stable_pair_hashes" \
  || fail 'main download failure changed the installed Codex pair'
expect_failure 'Codex host download failure' \
  env CURL_FAIL_BASENAME="$host_archive" INSTALL_TOOLS=codex \
  run_installer "$codex_fixture" "$codex_out" -- update --tool codex
test "$(codex_pair_hashes "$codex_out")" = "$stable_pair_hashes" \
  || fail 'host download failure changed the installed Codex pair'

validation_fixture=$test_root/codex-invalid
make_codex_pair "$validation_fixture" 0.148.0
mkdir -p "$validation_fixture/invalid"
printf 'not-the-host\n' > "$validation_fixture/invalid/unexpected"
tar -czf "$validation_fixture/$host_archive" \
  -C "$validation_fixture/invalid" unexpected
expect_failure 'Codex host validation failure' \
  env INSTALL_TOOLS=codex \
  run_installer "$validation_fixture" "$codex_out" -- update --tool codex
test "$(codex_pair_hashes "$codex_out")" = "$stable_pair_hashes" \
  || fail 'validation failure changed the installed Codex pair'
expect_failure 'Codex partial publication failure' \
  env CYCLESTONE_TOOLS_TESTING=1 \
  CYCLESTONE_TOOLS_TEST_FAULT=codex-after-main-publish INSTALL_TOOLS=codex \
  run_installer "$codex_fixture" "$codex_out" -- update --tool codex
test "$(codex_pair_hashes "$codex_out")" = "$stable_pair_hashes" \
  || fail 'partial publication failure did not restore the previous Codex pair'
echo "PASS: Codex failures preserve the previous pair"

# Both supported architecture mappings select their matching artifact pair.
arm_fixture=$test_root/codex-arm64
make_codex_pair "$arm_fixture" 0.147.0 aarch64-unknown-linux-musl arm64
arm_out=$test_root/out-codex-arm64
run_installer "$arm_fixture" "$arm_out" TARGETARCH=arm64 -- install --tool codex
assert_codex_pair "$arm_out" 0.147.0 aarch64-unknown-linux-musl
unsupported_log=$test_root/codex-unsupported.log
if run_installer "$codex_fixture" "$test_root/out-codex-unsupported" TARGETARCH=s390x \
    -- install --tool codex >"$unsupported_log" 2>&1; then
  fail 'unsupported Codex architecture unexpectedly succeeded'
fi
grep -F 'unsupported codex architecture: s390x' "$unsupported_log" >/dev/null \
  || fail 'unsupported Codex architecture did not produce a clear error'
echo "PASS: Codex architecture mapping and unsupported-platform error"

# ---------------------------------------------------------------------------
# Test 4b: agy install targets the user prefix, not the system prefix
#
# Regression: agy's installer hardcodes a staging tree under
# $HOME/.cache/antigravity and leaves the dirs behind on exit. Installing as
# root would persist root-owned staging the non-root developer cannot write
# into at runtime, breaking `cyclestone-tools update` with curl exit 23. The
# install dispatch must therefore route agy to the user prefix
# ($HOME/.local/bin/agy) so it runs as the developer user at build time.
# HOME is sandboxed so the real user's home is never touched.
# ---------------------------------------------------------------------------

agy_fixture=$test_root/agy
mkdir -p "$agy_fixture"
cat > "$agy_fixture/agy-install.sh" <<'AGY_INSTALLER_FIXTURE'
#!/bin/bash
set -euo pipefail
prefix=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) prefix="$2"; shift 2 ;;
    *) shift ;;
  esac
done
# Mirror the official installer: hardcode staging to
# $HOME/.cache/antigravity/staging (left behind on exit by design) and write
# the binary to the --dir prefix. The official installer refuses to overwrite
# an existing target; the fixture mirrors that so update_agy's `rm -f` is
# exercised.
staging="$HOME/.cache/antigravity/staging"
mkdir -p "$staging" "$prefix"
if [ -e "$prefix/agy" ]; then
  echo "agy: refusing to overwrite existing binary at $prefix/agy" >&2
  exit 1
fi
printf '#!/bin/sh\necho 1.1.10\n' > "$prefix/agy"
chmod +x "$prefix/agy"
AGY_INSTALLER_FIXTURE
chmod +x "$agy_fixture/agy-install.sh"

# run_installer already sandboxes HOME to the destination; pass the fixture
# dir and a fresh destination. INSTALLER_FIXTURE selects install.sh.
agy_out=$test_root/out-agy
INSTALL_TOOLS="agy" \
  run_installer "$agy_fixture" "$agy_out" -- install
# agy must land in the user prefix under HOME, not the system prefix.
test -x "$agy_out/.local/bin/agy" \
  || fail 'agy was not installed in the user prefix ($HOME/.local/bin/agy)'
test ! -e "$agy_out/usr/local/bin/agy" \
  || fail 'agy was installed to the system prefix (must be user-only)'
echo "PASS: agy install targets the user prefix, not the system prefix"

# ---------------------------------------------------------------------------
# Test 4c: agy update removes the existing binary before installing
#
# Regression: the agy installer refuses to overwrite an existing binary at
# $prefix/agy. `cyclestone-tools update` must remove it first so a fresh
# install succeeds even when an older agy is already present.
# ---------------------------------------------------------------------------

# Pre-populate the user prefix with a stale agy binary that the installer
# fixture would refuse to overwrite (the real installer errors out on an
# existing target; the fixture mirrors that by always writing fresh, so we
# simulate the pre-existing target by placing a sentinel file first).
agy_update_out=$test_root/out-agy-update
mkdir -p "$agy_update_out/.local/bin"
printf '#!/bin/sh\necho stale\n' > "$agy_update_out/.local/bin/agy"
chmod +x "$agy_update_out/.local/bin/agy"
test -x "$agy_update_out/.local/bin/agy" || fail 'stale agy sentinel was not planted'

INSTALL_TOOLS="agy" \
  run_installer "$agy_fixture" "$agy_update_out" -- update --tool agy
# update must have replaced the stale sentinel with the fixture's 1.1.10 build.
new_ver=$("$agy_update_out/.local/bin/agy" 2>/dev/null || true)
test "$new_ver" = "1.1.10" \
  || fail "agy update did not replace stale binary (got: $new_ver)"
echo "PASS: agy update removes the existing binary before installing"

# ---------------------------------------------------------------------------
# Test 5: selection parsing
# ---------------------------------------------------------------------------

# 5a: --tool repeated args
good2=$test_root/good2
make_cyclestone_archive "$good2" regular 0.0.4
make_cyclestone_checksums "$good2" 0.0.4
good2_out=$test_root/out-good2
INSTALL_TOOLS="" run_installer "$good2" "$good2_out" -- install --tool cyclestone
test -x "$good2_out/.local/bin/cyclestone" || fail '--tool arg did not install cyclestone'

# 5b: dedupe (cyclestone listed twice)
good3=$test_root/good3
make_cyclestone_archive "$good3" regular 0.0.4
make_cyclestone_checksums "$good3" 0.0.4
good3_out=$test_root/out-good3
INSTALL_TOOLS="cyclestone,cyclestone" run_installer "$good3" "$good3_out" -- install
test -x "$good3_out/.local/bin/cyclestone" || fail 'dedupe did not install cyclestone'

# 5c: unknown tool rejected
expect_failure 'unknown tool rejected' \
  env INSTALL_TOOLS="bogus" run_installer "$test_root" "$test_root/out-bogus" -- install

# 5d: comma-list in INSTALL_TOOLS env installs the complete Codex pair
mixed=$test_root/mixed
make_cyclestone_archive "$mixed" regular 0.0.4
make_cyclestone_checksums "$mixed" 0.0.4
make_codex_pair "$mixed" 0.146.0
mixed_out=$test_root/out-mixed
INSTALL_TOOLS="cyclestone,codex" run_installer "$mixed" "$mixed_out" -- install
test -x "$mixed_out/.local/bin/cyclestone" || fail 'mixed: cyclestone not installed'
assert_codex_pair "$mixed_out" 0.146.0

# The no-selector general update path dispatches through the same paired Codex
# updater while preserving the existing behavior of all other user tools.
cp "$agy_fixture/agy-install.sh" "$mixed/agy-install.sh"
cat > "$mixed/opencode-install.sh" <<'OPENCODE_INSTALLER_FIXTURE'
#!/bin/bash
set -euo pipefail
mkdir -p "$HOME/.opencode/bin"
printf '#!/bin/sh\necho 1.2.3\n' > "$HOME/.opencode/bin/opencode"
chmod 0755 "$HOME/.opencode/bin/opencode"
OPENCODE_INSTALLER_FIXTURE
chmod 0755 "$mixed/opencode-install.sh"
all_tools_out=$test_root/out-all-tools
INSTALL_TOOLS="cyclestone,codex,agy,opencode" \
  run_installer "$mixed" "$all_tools_out" -- install
assert_codex_pair "$all_tools_out" 0.146.0
test -x "$all_tools_out/.local/bin/cyclestone" || fail 'all-tools install missed cyclestone'
test -x "$all_tools_out/.local/bin/agy" || fail 'all-tools install missed agy'
test -x "$all_tools_out/.opencode/bin/opencode" || fail 'all-tools install missed opencode'
run_installer "$mixed" "$mixed_out" -- update
assert_codex_pair "$mixed_out" 0.146.0
test -x "$mixed_out/.local/bin/cyclestone" || fail 'general update broke cyclestone'
test -x "$mixed_out/.local/bin/agy" || fail 'general update did not update agy'
test -x "$mixed_out/.opencode/bin/opencode" || fail 'general update did not update opencode'

echo "PASS: selection parsing (env, --tool, dedupe, unknown, comma-list)"

# ---------------------------------------------------------------------------
# Test 6: status subcommand runs without error
# ---------------------------------------------------------------------------

status_out=$test_root/out-status
make_cyclestone_archive "$mixed" regular 0.0.4
make_cyclestone_checksums "$mixed" 0.0.4
INSTALL_TOOLS="cyclestone" run_installer "$mixed" "$status_out" -- install
PATH="$status_out/.local/bin:$PATH" "$installer" status >/dev/null \
  || fail 'status subcommand failed'
echo "PASS: status subcommand"

# ---------------------------------------------------------------------------
# Test 7: normalize_tools selection defaults (install vs update)
#
# Regression: `cyclestone-tools update` with no --tool args must default to
# the user-installable set (cyclestone,codex,agy,opencode) and ignore the
# INSTALL_TOOLS env, which is a build-time record only. `install` with no
# args must still honor INSTALL_TOOLS (empty = no-op).
# ---------------------------------------------------------------------------

# Source the installer in a subshell to unit-test normalize_tools directly.
# The entry guard forwards the _normalize_test passthrough to normalize_tools
# using the install/update convention (<default> <read_env> -- ...).

# 7a: install with no --tool, empty INSTALL_TOOLS -> empty (no-op)
got=$(INSTALL_TOOLS="" "$installer" _normalize_test "" 1)
test "$got" = "" || fail "install empty default expected empty, got [$got]"

# 7b: install with no --tool, INSTALL_TOOLS=cyclestone -> cyclestone
got=$(INSTALL_TOOLS="cyclestone" "$installer" _normalize_test "" 1)
test "$got" = "cyclestone" || fail "install env read expected [cyclestone], got [$got]"

# 7c: update with no --tool ignores INSTALL_TOOLS=opencode -> all four
got=$(INSTALL_TOOLS="opencode" "$installer" _normalize_test "cyclestone,codex,agy,opencode" 0)
test "$got" = "cyclestone,codex,agy,opencode" \
  || fail "update default expected [cyclestone,codex,agy,opencode], got [$got]"

# 7d: update --tool codex overrides default, ignores INSTALL_TOOLS
got=$(INSTALL_TOOLS="cyclestone" "$installer" _normalize_test "cyclestone,codex,agy,opencode" 0 --tool codex)
test "$got" = "codex" || fail "update --tool override expected [codex], got [$got]"

# 7e: update --tool cyclestone --tool opencode (dedupe + order preserved)
got=$(INSTALL_TOOLS="" "$installer" _normalize_test "cyclestone,codex,agy,opencode" 0 --tool opencode --tool cyclestone --tool opencode)
test "$got" = "opencode,cyclestone" \
  || fail "update multi --tool expected [opencode,cyclestone], got [$got]"

# 7f: unknown tool rejected under update too
expect_failure 'update unknown tool rejected' \
  env INSTALL_TOOLS="" "$installer" _normalize_test "cyclestone,codex,agy,opencode" 0 --tool bogus

echo "PASS: normalize_tools install vs update selection defaults"

echo 'PASS: install-tools accepts valid input and rejects unsafe or inconsistent input'
