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

cat > "$test_root/podman" <<'EOF'
#!/bin/sh
case "$1 $2" in
  'info --format') printf '%s\n' true ;;
  'build --pull=always')
    printf '%s\n' "$@" > "$PODMAN_ARGUMENT_LOG"
    while test "$#" -gt 0; do
      if test "$1" = --iidfile; then
        shift
        printf '%s\n' sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa > "$1"
        break
      fi
      shift
    done
    ;;
  'image inspect') printf '%s\n' sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
  *) echo "unexpected podman command: $*" >&2; exit 1 ;;
esac
EOF
chmod 0755 "$test_root/podman"

iid_file=$test_root/base.iid
PATH="$test_root:$PATH" PODMAN_ARGUMENT_LOG=$test_root/arguments \
IMAGE_VERSION=1.0.0-local \
IMAGE_REVISION=5f303ed9f56e7ed319b5de656405c567f868a8a9 \
IMAGE_CREATED=2026-07-31T17:00:00Z \
IMAGE_LICENSES=LicenseRef-Container-Image-Review-Required \
IID_FILE=$iid_file IMAGE_TAG=cyclestone-base:test \
  "$repo_root/scripts/build-base-podman.sh" >/dev/null

grep -Fx -- '--iidfile' "$test_root/arguments" >/dev/null || fail 'iidfile flag missing'
grep -Fx -- "$iid_file" "$test_root/arguments" >/dev/null || fail 'iidfile path missing'
grep -Fx -- '--format' "$test_root/arguments" >/dev/null || fail 'OCI format flag missing'
grep -Fx -- 'TARGETARCH=amd64' "$test_root/arguments" >/dev/null || fail 'native architecture missing'
test "$(cat "$iid_file")" = sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  || fail 'builder image identity was not retained'

if PATH="$test_root:$PATH" PODMAN_ARGUMENT_LOG=$test_root/arguments \
  IMAGE_VERSION=1.0.0 IMAGE_REVISION=5f303ed9f56e7ed319b5de656405c567f868a8a9 \
  IMAGE_CREATED=2026-07-31T17:00:00Z IMAGE_LICENSES=MIT \
  IID_FILE=$iid_file BUILD_NO_CACHE=invalid \
  "$repo_root/scripts/build-base-podman.sh" >/dev/null 2>&1; then
  fail 'invalid no-cache value unexpectedly succeeded'
fi

echo 'PASS: Podman builder is rootless-only and retains an independent image ID'
