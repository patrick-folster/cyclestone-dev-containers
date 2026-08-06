#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
cleanup() {
  test -n "${test_root:-}" && test "$test_root" != / && rm -rf -- "$test_root"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cat > "$test_root/docker" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$DOCKER_ARGUMENT_LOG"
EOF
chmod 0755 "$test_root/docker"

run_build() {
  PATH="$test_root:$PATH" DOCKER_ARGUMENT_LOG="$test_root/arguments" \
    IMAGE_VERSION=1.0.0 IMAGE_REVISION=5f303ed9f56e7ed319b5de656405c567f868a8a9 \
    IMAGE_CREATED=2026-07-31T17:00:00Z \
    IMAGE_LICENSES=LicenseRef-Container-Image-Review-Required \
    OCI_OUTPUT="$test_root/base.oci.tar" "$repo_root/scripts/build-base.sh" "$@"
}

run_build load
grep -Fx -- '--platform' "$test_root/arguments" >/dev/null || fail 'platform flag missing'
grep -Fx -- 'linux/amd64' "$test_root/arguments" >/dev/null || fail 'load platform missing'
grep -Fx -- '--load' "$test_root/arguments" >/dev/null || fail 'load output missing'
grep -F -- 'BASE_IMAGE=ubuntu:24.04@sha256:' "$test_root/arguments" >/dev/null || fail 'pinned base missing'
grep -F -- 'INSTALL_TOOLS=' "$test_root/arguments" >/dev/null || fail 'INSTALL_TOOLS build-arg missing'
grep -Fx -- 'IMAGE_VERSION=1.0.0' "$test_root/arguments" >/dev/null || fail 'image version missing'

PLATFORMS=linux/arm64 run_build load
grep -Fx -- 'linux/arm64' "$test_root/arguments" >/dev/null || fail 'explicit arm64 load platform missing'
grep -Fx -- '--load' "$test_root/arguments" >/dev/null || fail 'arm64 load output missing'

BUILD_NO_CACHE=1 run_build load
grep -Fx -- '--no-cache' "$test_root/arguments" >/dev/null || fail 'clean-build flag missing'

run_build oci
grep -Fx -- 'linux/amd64,linux/arm64' "$test_root/arguments" >/dev/null || fail 'OCI platforms missing'
grep -Fx -- "type=oci,dest=$test_root/base.oci.tar" "$test_root/arguments" >/dev/null || fail 'OCI output missing'

if PLATFORMS=linux/riscv64 run_build load >/dev/null 2>&1; then
  fail 'unsupported platform unexpectedly succeeded'
fi
if PATH="$test_root:$PATH" IMAGE_VERSION=not-semver \
  IMAGE_REVISION=5f303ed9f56e7ed319b5de656405c567f868a8a9 \
  IMAGE_CREATED=2026-07-31T17:00:00Z IMAGE_LICENSES=MIT \
  "$repo_root/scripts/build-base.sh" load >/dev/null 2>&1; then
  fail 'invalid image version unexpectedly succeeded'
fi
if PATH="$test_root:$PATH" IMAGE_VERSION=1.0.0 IMAGE_REVISION=short \
  IMAGE_CREATED=2026-07-31T17:00:00Z IMAGE_LICENSES=MIT \
  "$repo_root/scripts/build-base.sh" load >/dev/null 2>&1; then
  fail 'invalid revision unexpectedly succeeded'
fi

echo 'PASS: build wrapper validates metadata/platforms and emits load/OCI Buildx commands'
