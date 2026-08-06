#!/bin/sh
# examples-build.sh — validate all five example projects.
#
# SDK examples (Go, Node.js, .NET) are built and contract-checked when a
# container engine and base image are available.  Provider examples (Codex,
# Ollama) are validated statically through resolve-providers.sh and the
# noninteractive fail-closed authorization path.
#
# Environment:
#   BASE_IMAGE       — loaded base image tag (required for SDK builds)
#   CONTAINER_CLI    — docker or podman (default: docker)
#   PLATFORM         — linux/amd64 or linux/arm64 (default: linux/amd64)
#   SKIP_SDK_BUILDS  — set to 1 to skip SDK image builds
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

container_cli=${CONTAINER_CLI:-docker}
platform=${PLATFORM:-linux/amd64}
case "$container_cli" in docker|podman) ;; *) fail 'CONTAINER_CLI must be docker or podman' ;; esac
case "$platform" in linux/amd64|linux/arm64) ;; *) fail "unsupported platform: $platform" ;; esac

# ---------------------------------------------------------------------------
# Provider examples — static validation (no container engine required)
# ---------------------------------------------------------------------------

validate_provider_example() {
  example_dir=$1
  provider_id=$2
  expected_mode=$3

  request_file="$example_dir/providers.json"
  test -s "$request_file" || fail "missing provider request: $request_file"
  jq empty "$request_file" >/dev/null 2>&1 || fail "invalid JSON: $request_file"

  # Resolve the provider plan
  plan=$("$repo_root/scripts/resolve-providers.sh" "$request_file" "$provider_id" linux)
  plan_mode=$(printf '%s\n' "$plan" | jq -r '.mode')
  test "$plan_mode" = "$expected_mode" \
    || fail "$example_dir: resolved mode '$plan_mode' != expected '$expected_mode'"
  plan_provider=$(printf '%s\n' "$plan" | jq -r '.provider_id')
  test "$plan_provider" = "$provider_id" \
    || fail "$example_dir: resolved provider '$plan_provider' != expected '$provider_id'"

  # Verify noninteractive authorization fails closed (no grant exists)
  temp_project=$(mktemp -d)
  trap 'rm -rf "$temp_project"' EXIT HUP INT TERM
  cp "$request_file" "$temp_project/providers.json"
  cd "$temp_project"
  git init -q
  git add providers.json
  git -c user.email=test@example.com -c user.name=test commit -q -m test
  if "$repo_root/scripts/devcontainer-permissions.sh" authorize "$temp_project" providers.json "$provider_id" linux >/dev/null 2>&1; then
    cd "$repo_root"
    fail "$example_dir: noninteractive authorize succeeded without a grant (fail-closed violated)"
  fi
  cd "$repo_root"
  rm -rf "$temp_project"
  trap - EXIT HUP INT TERM

  echo "PASS: provider example $example_dir ($provider_id $expected_mode)"
}

validate_provider_example "$repo_root/examples/codex" codex read-write
validate_provider_example "$repo_root/examples/ollama" ollama host-service
validate_provider_example "$repo_root/examples/agy" agy environment

# ---------------------------------------------------------------------------
# SDK examples — runtime build and contract (requires container engine + base)
# ---------------------------------------------------------------------------

if test "${SKIP_SDK_BUILDS:-0}" = 1; then
  echo "SKIP: SDK example builds (SKIP_SDK_BUILDS=1)"
  echo "PASS: provider examples validated, SDK builds skipped"
  exit 0
fi

base_image=${BASE_IMAGE:-}
if test -z "$base_image"; then
  echo "SKIP: SDK example builds (BASE_IMAGE not set)"
  echo "PASS: provider examples validated, SDK builds skipped (no base image)"
  exit 0
fi

if ! command -v "$container_cli" >/dev/null 2>&1; then
  echo "SKIP: SDK example builds ($container_cli not available)"
  echo "PASS: provider examples validated, SDK builds skipped (no $container_cli)"
  exit 0
fi

base_id=$("$container_cli" image inspect --format '{{.Id}}' "$base_image") \
  || fail "base image not loaded: $base_image"
case "$base_id" in sha256:*) ;; *) base_id=sha256:$base_id ;; esac

# Build command varies by engine: Docker buildx supports --provenance/--load/--builder;
# Podman build does not and loads locally by default.
build_cmd() {
  if test "$container_cli" = docker; then
    "$container_cli" buildx build --provenance=false --load --builder default "$@"
  else
    "$container_cli" build "$@"
  fi
}

# --- Common contract check for any built child image ---
check_child_contract() {
  image=$1
  sdk_check_cmd=$2

  test "$("$container_cli" image inspect --format '{{.Config.User}}' "$image")" = developer \
    || fail "$image: final USER must be developer"
  test "$("$container_cli" image inspect --format '{{.Config.WorkingDir}}' "$image")" = /workspace \
    || fail "$image: WORKDIR must be /workspace"
  test "$("$container_cli" image inspect --format '{{json .Config.Entrypoint}}' "$image")" = '["/usr/local/bin/cyclestone-entrypoint"]' \
    || fail "$image: must preserve base ENTRYPOINT"
  test "$("$container_cli" image inspect --format '{{json .Config.Cmd}}' "$image")" = '["/bin/bash","-l"]' \
    || fail "$image: must preserve base CMD"

  "$container_cli" run --rm "$image" sh -eu -c '
    test "$(id -un)" = developer
    test "$(id -u)" -gt 0
    test "$HOME" = /home/developer
    test "$PWD" = /workspace
    command -v cyclestone >/dev/null
    cyclestone --version >/dev/null
  ' || fail "$image: identity or cyclestone contract failed"

  "$container_cli" run --rm "$image" sh -eu -c "$sdk_check_cmd" \
    || fail "$image: SDK contract failed"
}

# --- Build and check the Go example ---
go_tag=cyclestone-example-go:$$
. "$repo_root/examples/child-image/versions.env"
build_cmd \
  --file "$repo_root/examples/child-image/Containerfile" \
  --platform "$platform" \
  --build-arg "BASE_IMAGE_REF=$base_image" \
  --build-arg "GO_VERSION=$GO_VERSION" \
  --build-arg "GO_BASE_URL=$GO_BASE_URL" \
  --build-arg "GO_AMD64_ARCHIVE=$GO_AMD64_ARCHIVE" \
  --build-arg "GO_AMD64_SHA256=$GO_AMD64_SHA256" \
  --build-arg "GO_ARM64_ARCHIVE=$GO_ARM64_ARCHIVE" \
  --build-arg "GO_ARM64_SHA256=$GO_ARM64_SHA256" \
  --tag "$go_tag" "$repo_root" >/dev/null
check_child_contract "$go_tag" '
  actual=$(go version)
  test "$(printf "%s" "$actual" | awk "{print \$3}")" = "go'"$GO_VERSION"'"
  printf "go_version=%s\n" "$actual"
'
"$container_cli" rmi "$go_tag" >/dev/null 2>&1 || true
echo "PASS: Go example build and contract"

# --- Build and check the Node.js example ---
node_tag=cyclestone-example-node:$$
. "$repo_root/examples/nodejs/versions.env"
build_cmd \
  --file "$repo_root/examples/nodejs/Containerfile" \
  --platform "$platform" \
  --build-arg "BASE_IMAGE_REF=$base_image" \
  --build-arg "NODE_VERSION=$NODE_VERSION" \
  --build-arg "NODE_BASE_URL=$NODE_BASE_URL" \
  --build-arg "NODE_AMD64_ARCHIVE=$NODE_AMD64_ARCHIVE" \
  --build-arg "NODE_AMD64_SHA256=$NODE_AMD64_SHA256" \
  --build-arg "NODE_ARM64_ARCHIVE=$NODE_ARM64_ARCHIVE" \
  --build-arg "NODE_ARM64_SHA256=$NODE_ARM64_SHA256" \
  --tag "$node_tag" "$repo_root" >/dev/null
check_child_contract "$node_tag" '
  actual=$(node --version)
  test "$actual" = "v'"$NODE_VERSION"'"
  npm --version >/dev/null
  printf "node_version=%s\n" "$actual"
'
"$container_cli" rmi "$node_tag" >/dev/null 2>&1 || true
echo "PASS: Node.js example build and contract"

# --- Build and check the .NET example ---
dotnet_tag=cyclestone-example-dotnet:$$
. "$repo_root/examples/dotnet/versions.env"
build_cmd \
  --file "$repo_root/examples/dotnet/Containerfile" \
  --platform "$platform" \
  --build-arg "BASE_IMAGE_REF=$base_image" \
  --build-arg "DOTNET_VERSION=$DOTNET_VERSION" \
  --build-arg "DOTNET_BASE_URL=$DOTNET_BASE_URL" \
  --build-arg "DOTNET_AMD64_ARCHIVE=$DOTNET_AMD64_ARCHIVE" \
  --build-arg "DOTNET_AMD64_SHA512=$DOTNET_AMD64_SHA512" \
  --build-arg "DOTNET_ARM64_ARCHIVE=$DOTNET_ARM64_ARCHIVE" \
  --build-arg "DOTNET_ARM64_SHA512=$DOTNET_ARM64_SHA512" \
  --tag "$dotnet_tag" "$repo_root" >/dev/null
check_child_contract "$dotnet_tag" '
  actual=$(dotnet --version)
  test "$actual" = "'"$DOTNET_VERSION"'"
  printf "dotnet_version=%s\n" "$actual"
'
"$container_cli" rmi "$dotnet_tag" >/dev/null 2>&1 || true
echo "PASS: .NET example build and contract"

echo "PASS: all five examples validated ($platform)"
