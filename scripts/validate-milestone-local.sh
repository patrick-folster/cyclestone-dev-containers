#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
milestone=${1:-}
case "$milestone" in
  ms-pf-0005|ms-pf-0005-integrate-devcontainer-workflows) ;;
  ms-pf-0008|ms-pf-0008-secure-provider-credentials) credential_milestone=true ;;
  ms-pf-0009|ms-pf-0009-generate-validate-runtime-config) runtime_config_milestone=true ;;
  ms-pf-0010|ms-pf-0010-support-host-services-selinux) host_services_selinux_milestone=true ;;
  ms-pf-0011|ms-pf-0011-harden-end-to-end-security-boundary) security_boundary_milestone=true ;;
  ms-pf-0012|ms-pf-0012-automate-testing) automate_testing_milestone=true ;;
  ms-pf-0014|ms-pf-0014-templates-examples-documentation) templates_examples_milestone=true ;;
  ms-pf-0015|ms-pf-0015-qualify-mvp-delivery-roadmap) mvp_qualification_milestone=true ;;
  *) echo "usage: $0 ms-pf-0005|ms-pf-0008|ms-pf-0009|ms-pf-0010|ms-pf-0011|ms-pf-0012|ms-pf-0014|ms-pf-0015" >&2; exit 64 ;;
esac

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if test "${automate_testing_milestone:-false}" = true; then
  test "$(uname -s)" = Linux || fail 'local milestone validation requires Linux'
  test "$(uname -m)" = x86_64 || fail 'local milestone validation requires amd64'
  test "$(id -u)" -ne 0 || fail 'run this command as the non-root Podman user'
  for command in git jq podman devcontainer socat realpath stat sha256sum flock sync base64; do
    command -v "$command" >/dev/null 2>&1 || fail "$command is unavailable"
  done
  test "$(podman info --format '{{.Host.Security.Rootless}}')" = true \
    || fail 'Podman is not rootless'
  test "$(podman info --format json | jq -r '.host.ociRuntime.name')" = crun \
    || fail 'Podman must use crun'
  podman_version=$(podman version --format '{{.Client.Version}}')
  podman_major=$(printf '%s\n' "$podman_version" | cut -d. -f1)
  podman_minor=$(printf '%s\n' "$podman_version" | cut -d. -f2)
  case "$podman_major:$podman_minor" in
    *[!0-9:]*|:*|*:) fail "cannot parse Podman version: $podman_version" ;;
  esac
  test "$podman_major" -gt 4 || { test "$podman_major" -eq 4 && test "$podman_minor" -ge 9; } \
    || fail 'Podman 4.9 or newer is required'
  test "$(devcontainer --version)" = 0.86.0 \
    || fail 'Dev Container CLI 0.86.0 is required'
  grep -q "^$(id -un):" /etc/subuid || fail 'the invoking user has no /etc/subuid range'
  grep -q "^$(id -un):" /etc/subgid || fail 'the invoking user has no /etc/subgid range'

  host_uid=$(id -u)
  host_gid=$(id -g)
  case "$host_uid:$host_gid" in
    1000:1000) identity_case=matching ;;
    *) identity_case=differing ;;
  esac
  if test -n "${IDENTITY_CASE:-}" && test "$IDENTITY_CASE" != "$identity_case"; then
    fail "IDENTITY_CASE=$IDENTITY_CASE does not match host identity $host_uid:$host_gid ($identity_case)"
  fi

  revision=$(git -C "$repo_root" rev-parse HEAD)
  source_digest=$(
    git -C "$repo_root" ls-files --cached --others --exclude-standard \
      | LC_ALL=C sort \
      | while IFS= read -r path; do
          test -f "$repo_root/$path" || continue
          printf '%s %s %s\n' \
            "$(stat -c %a "$repo_root/$path")" \
            "$(sha256sum "$repo_root/$path" | awk '{print $1}')" \
            "$path"
        done \
      | sha256sum \
      | awk '{print $1}'
  )
  created=$(date -u -d "$(git -C "$repo_root" show -s --format=%cI HEAD)" +%Y-%m-%dT%H:%M:%SZ)
  evidence_root=${EVIDENCE_DIR:-$repo_root/dist/evidence/ms-pf-0012/local}
  case_dir=$evidence_root/$identity_case
  iid_file=$case_dir/base-image.iid
  if ! test -d "$evidence_root"; then
    mkdir -p "$evidence_root"
    chmod 1777 "$evidence_root"
  fi
  test -w "$evidence_root" \
    || fail "evidence directory is not writable: $evidence_root"
  if test -d "$case_dir"; then
    test "$(stat -c %u "$case_dir")" = "$host_uid" \
      || fail "identity evidence directory is owned by another account: $case_dir"
  else
    mkdir "$case_dir"
  fi
  printf 'milestone=%s\ncommit=%s\nsource_digest=%s\nhost_uid=%s\nhost_gid=%s\nidentity_case=%s\n' \
    ms-pf-0012-automate-testing "$revision" "$source_digest" "$host_uid" "$host_gid" "$identity_case" \
    > "$case_dir/local-request.txt"

  primary_gid=$(id -g)
  supplementary_gid=""
  for gid in $(id -G); do
    if test "$gid" != "$primary_gid"; then
      supplementary_gid=$gid
      break
    fi
  done
  if test -z "$supplementary_gid"; then
    supplementary_gid=$primary_gid
  fi

  group_path=$case_dir/group-access
  rm -rf "$group_path"
  mkdir -p "$group_path"
  chgrp "$supplementary_gid" "$group_path"
  chmod 2770 "$group_path"

  IMAGE_VERSION=1.0.0-local \
  IMAGE_REVISION=$revision \
  IMAGE_CREATED=$created \
  IMAGE_LICENSES=LicenseRef-Container-Image-Review-Required \
  IMAGE_TAG=cyclestone-base:project-devcontainer-local-$identity_case \
  IID_FILE=$iid_file \
    "$repo_root/scripts/build-base-podman.sh" > "$case_dir/base-build.log" 2>&1 \
    || { status=$?; sed -n '1,240p' "$case_dir/base-build.log" >&2; exit "$status"; }
  sed -n '1,240p' "$case_dir/base-build.log"

  base_id=$(sed -n '1p' "$iid_file")

  scrub_log() {
    log_file=$1
    test -f "$log_file" || return 0
    sed -E \
      -e 's/[0-9a-f]{64}/[REDACTED_HEX64]/g' \
      -e 's/[0-9a-f]{32}/[REDACTED_HEX32]/g' \
      -e 's/(key|token|pass|secret|auth|api)[^[:space:]=]*[[:space:]]*[=:][[:space:]]*[^[:space:]]+/& -> [REDACTED]/gi' \
      "$log_file" > "$log_file.tmp" && mv -f "$log_file.tmp" "$log_file"
  }

  echo "Running static contracts checks..."
  "$repo_root/tests/contracts.sh" > "$case_dir/contracts.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/contracts.log" >&2; scrub_log "$case_dir/contracts.log"; exit "$status"; }
  scrub_log "$case_dir/contracts.log"

  echo "Running provider registry checks..."
  "$repo_root/tests/provider-registry.sh" > "$case_dir/provider-registry.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/provider-registry.log" >&2; scrub_log "$case_dir/provider-registry.log"; exit "$status"; }
  scrub_log "$case_dir/provider-registry.log"

  echo "Running provider authorization checks..."
  "$repo_root/tests/provider-authorization.sh" > "$case_dir/provider-authorization.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/provider-authorization.log" >&2; scrub_log "$case_dir/provider-authorization.log"; exit "$status"; }
  scrub_log "$case_dir/provider-authorization.log"

  echo "Running child image static checks..."
  "$repo_root/tests/child-image-static.sh" > "$case_dir/child-image-static.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/child-image-static.log" >&2; scrub_log "$case_dir/child-image-static.log"; exit "$status"; }
  scrub_log "$case_dir/child-image-static.log"

  echo "Running runtime configuration checks..."
  "$repo_root/tests/runtime-config.sh" > "$case_dir/runtime-config.log" 2>&1 \
    || { status=$?; sed -n '1,200p' "$case_dir/runtime-config.log" >&2; scrub_log "$case_dir/runtime-config.log"; exit "$status"; }
  scrub_log "$case_dir/runtime-config.log"

  echo "Running provider credentials tests..."
  CREDENTIAL_TEST_IMAGE=cyclestone-base:project-devcontainer-local-$identity_case \
    "$repo_root/tests/provider-credentials.sh" > "$case_dir/provider-credentials.log" 2>&1 \
    || { status=$?; sed -n '1,200p' "$case_dir/provider-credentials.log" >&2; scrub_log "$case_dir/provider-credentials.log"; exit "$status"; }
  scrub_log "$case_dir/provider-credentials.log"

  echo "Running rootless Podman execution tests..."
  IMAGE=cyclestone-base:project-devcontainer-local-$identity_case \
  IDENTITY_GROUP_PATH=$group_path \
  IDENTITY_GROUP_GID=$supplementary_gid \
  EVIDENCE_DIR=$case_dir \
    "$repo_root/tests/rootless-podman.sh" > "$case_dir/rootless-podman.log" 2>&1 \
    || { status=$?; sed -n '1,200p' "$case_dir/rootless-podman.log" >&2; scrub_log "$case_dir/rootless-podman.log"; exit "$status"; }
  scrub_log "$case_dir/rootless-podman.log"

  echo "Running Dev Container integrations tests..."
  IDENTITY_CASE=$identity_case \
  CYCLESTONE_BASE_IMAGE_ID=$base_id \
  CYCLESTONE_BASE_IMAGE_LOCAL=cyclestone-base:project-devcontainer-local-$identity_case \
  EVIDENCE_DIR=$case_dir \
    "$repo_root/tests/devcontainer-podman.sh" > "$case_dir/devcontainer-podman.log" 2>&1 \
    || { status=$?; sed -n '1,320p' "$case_dir/devcontainer-podman.log" >&2; scrub_log "$case_dir/devcontainer-podman.log"; exit "$status"; }
  scrub_log "$case_dir/devcontainer-podman.log"

  printf 'status=pass\ncommit=%s\nsource_digest=%s\nidentity_case=%s\nbase_id=%s\n' \
    "$revision" "$source_digest" "$identity_case" "$base_id" > "$case_dir/result.txt"
  echo "PASS: local Podman milestone validation ($identity_case)"

  for required_case in matching differing; do
    result=$evidence_root/$required_case/result.txt
    test -f "$result" \
      || fail "the $required_case local identity case has not passed; run this command as the corresponding local account"
    grep -Fx "status=pass" "$result" >/dev/null \
      || fail "the $required_case result is not successful"
    grep -Fx "commit=$revision" "$result" >/dev/null \
      || fail "the $required_case result belongs to another commit"
    grep -Fx "source_digest=$source_digest" "$result" >/dev/null \
      || fail "the $required_case result belongs to different source content"
    test -s "$evidence_root/$required_case/conflict-observation.txt" \
      || fail "the $required_case result lacks updateRemoteUserUID evidence"
  done
  echo 'PASS: both local rootless-Podman identity cases qualify the milestone cycle'
  exit 0
fi


if test "${templates_examples_milestone:-false}" = true; then
  test "$(uname -s)" = Linux || fail 'templates and examples validation requires Linux'
  for command in git jq; do
    command -v "$command" >/dev/null 2>&1 || fail "$command is unavailable"
  done
  evidence_dir=${EVIDENCE_DIR:-$repo_root/dist/evidence/ms-pf-0014/local}
  mkdir -p "$evidence_dir"
  revision=$(git -C "$repo_root" rev-parse HEAD)
  source_digest=$(git -C "$repo_root" ls-files --cached --others --exclude-standard | LC_ALL=C sort | while IFS= read -r path; do test -f "$repo_root/$path" || continue; printf '%s %s %s\n' "$(stat -c %a "$repo_root/$path")" "$(sha256sum "$repo_root/$path"|awk '{print $1}')" "$path"; done | sha256sum | awk '{print $1}')

  echo "Running static contracts checks..."
  "$repo_root/tests/contracts.sh" >"$evidence_dir/contracts.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/contracts.log" >&2; exit "$status"; }

  echo "Running documentation command validation..."
  "$repo_root/scripts/validate-docs.sh" >"$evidence_dir/validate-docs.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/validate-docs.log" >&2; exit "$status"; }

  echo "Running child image static checks..."
  "$repo_root/tests/child-image-static.sh" >"$evidence_dir/child-image-static.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/child-image-static.log" >&2; exit "$status"; }

  echo "Running provider example checks..."
  SKIP_SDK_BUILDS=1 "$repo_root/tests/examples-build.sh" >"$evidence_dir/examples-build.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/examples-build.log" >&2; exit "$status"; }

  # SDK example builds are gated on container engine and base image availability.
  base_image=${BASE_IMAGE:-}
  container_cli=${CONTAINER_CLI:-docker}
  if test -n "$base_image" && command -v "$container_cli" >/dev/null 2>&1; then
    echo "Running SDK example builds ($container_cli)..."
    BASE_IMAGE="$base_image" CONTAINER_CLI="$container_cli"       "$repo_root/tests/examples-build.sh" >"$evidence_dir/examples-build-runtime.log" 2>&1       || { status=$?; sed -n '1,200p' "$evidence_dir/examples-build-runtime.log" >&2; exit "$status"; }
  else
    echo "SKIP: SDK example builds (no base image or container engine)"
  fi

  printf 'status=pass\ncommit=%s\nsource_digest=%s\n' "$revision" "$source_digest" >"$evidence_dir/result.txt"
  echo 'PASS: local templates-and-examples milestone validation'
  exit 0
fi


if test "${mvp_qualification_milestone:-false}" = true; then
  test "$(uname -s)" = Linux || fail 'MVP qualification requires Linux'
  test "$(uname -m)" = x86_64 || fail 'MVP qualification requires amd64'
  test "$(id -u)" -ne 0 || fail 'run MVP qualification as the non-root Podman user'
  for command in git jq podman devcontainer socat realpath stat sha256sum flock sync base64; do
    command -v "$command" >/dev/null 2>&1 || fail "$command is unavailable"
  done
  test "$(podman info --format '{{.Host.Security.Rootless}}')" = true \
    || fail 'Podman is not rootless'
  test "$(podman info --format json | jq -r '.host.ociRuntime.name')" = crun \
    || fail 'Podman must use crun'
  podman_version=$(podman version --format '{{.Client.Version}}')
  podman_major=$(printf '%s\n' "$podman_version" | cut -d. -f1)
  podman_minor=$(printf '%s\n' "$podman_version" | cut -d. -f2)
  case "$podman_major:$podman_minor" in
    *[!0-9:]*|:*|*:) fail "cannot parse Podman version: $podman_version" ;;
  esac
  test "$podman_major" -gt 4 || { test "$podman_major" -eq 4 && test "$podman_minor" -ge 9; } \
    || fail 'Podman 4.9 or newer is required'
  test "$(devcontainer --version)" = 0.86.0 \
    || fail 'Dev Container CLI 0.86.0 is required'
  grep -q "^$(id -un):" /etc/subuid || fail 'the invoking user has no /etc/subuid range'
  grep -q "^$(id -un):" /etc/subgid || fail 'the invoking user has no /etc/subgid range'

  host_uid=$(id -u)
  host_gid=$(id -g)
  case "$host_uid:$host_gid" in
    1000:1000) identity_case=matching ;;
    *) identity_case=differing ;;
  esac
  if test -n "${IDENTITY_CASE:-}" && test "$IDENTITY_CASE" != "$identity_case"; then
    fail "IDENTITY_CASE=$IDENTITY_CASE does not match host identity $host_uid:$host_gid ($identity_case)"
  fi

  revision=$(git -C "$repo_root" rev-parse HEAD)
  source_digest=$(
    git -C "$repo_root" ls-files --cached --others --exclude-standard \
      | LC_ALL=C sort \
      | while IFS= read -r path; do
          test -f "$repo_root/$path" || continue
          printf '%s %s %s\n' \
            "$(stat -c %a "$repo_root/$path")" \
            "$(sha256sum "$repo_root/$path" | awk '{print $1}')" \
            "$path"
        done \
      | sha256sum \
      | awk '{print $1}'
  )
  created=$(date -u -d "$(git -C "$repo_root" show -s --format=%cI HEAD)" +%Y-%m-%dT%H:%M:%SZ)
  evidence_root=${EVIDENCE_DIR:-$repo_root/dist/evidence/ms-pf-0015/local}
  case_dir=$evidence_root/$identity_case
  iid_file=$case_dir/base-image.iid
  if ! test -d "$evidence_root"; then
    mkdir -p "$evidence_root"
    chmod 1777 "$evidence_root"
  fi
  test -w "$evidence_root" \
    || fail "evidence directory is not writable: $evidence_root"
  if test -d "$case_dir"; then
    test "$(stat -c %u "$case_dir")" = "$host_uid" \
      || fail "identity evidence directory is owned by another account: $case_dir"
  else
    mkdir "$case_dir"
  fi
  printf 'milestone=%s\ncommit=%s\nsource_digest=%s\nhost_uid=%s\nhost_gid=%s\nidentity_case=%s\n' \
    ms-pf-0015-qualify-mvp-delivery-roadmap "$revision" "$source_digest" "$host_uid" "$host_gid" "$identity_case" \
    > "$case_dir/local-request.txt"

  primary_gid=$(id -g)
  supplementary_gid=""
  for gid in $(id -G); do
    if test "$gid" != "$primary_gid"; then
      supplementary_gid=$gid
      break
    fi
  done
  if test -z "$supplementary_gid"; then
    supplementary_gid=$primary_gid
  fi

  group_path=$case_dir/group-access
  rm -rf "$group_path"
  mkdir -p "$group_path"
  chgrp "$supplementary_gid" "$group_path"
  chmod 2770 "$group_path"

  # --- Build the base image from pinned Ubuntu 24.04 digest ---
  echo "Building base image from pinned Ubuntu 24.04 digest..."
  IMAGE_VERSION=1.0.0-local \
  IMAGE_REVISION=$revision \
  IMAGE_CREATED=$created \
  IMAGE_LICENSES=LicenseRef-Container-Image-Review-Required \
  IMAGE_TAG=cyclestone-base:mvp-local-$identity_case \
  IID_FILE=$iid_file \
    "$repo_root/scripts/build-base-podman.sh" > "$case_dir/base-build.log" 2>&1 \
    || { status=$?; sed -n '1,240p' "$case_dir/base-build.log" >&2; exit "$status"; }
  sed -n '1,60p' "$case_dir/base-build.log"

  base_id=$(sed -n '1p' "$iid_file")
  base_tag=cyclestone-base:mvp-local-$identity_case

  scrub_log() {
    log_file=$1
    test -f "$log_file" || return 0
    sed -E \
      -e 's/[0-9a-f]{64}/[REDACTED_HEX64]/g' \
      -e 's/[0-9a-f]{32}/[REDACTED_HEX32]/g' \
      -e 's/(key|token|pass|secret|auth|api)[^[:space:]=]*[[:space:]]*[=:][[:space:]]*[^[:space:]]+/& -> [REDACTED]/gi' \
      "$log_file" > "$log_file.tmp" && mv -f "$log_file.tmp" "$log_file"
  }

  # --- Static contracts checks ---
  echo "Running static contracts checks..."
  "$repo_root/tests/contracts.sh" > "$case_dir/contracts.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/contracts.log" >&2; scrub_log "$case_dir/contracts.log"; exit "$status"; }
  scrub_log "$case_dir/contracts.log"

  # --- Documentation validation ---
  echo "Running documentation command validation..."
  "$repo_root/scripts/validate-docs.sh" > "$case_dir/validate-docs.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/validate-docs.log" >&2; exit "$status"; }

  # --- Provider registry checks ---
  echo "Running provider registry checks..."
  "$repo_root/tests/provider-registry.sh" > "$case_dir/provider-registry.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/provider-registry.log" >&2; scrub_log "$case_dir/provider-registry.log"; exit "$status"; }
  scrub_log "$case_dir/provider-registry.log"

  # --- Provider authorization checks (provider request and denial) ---
  echo "Running provider authorization checks..."
  "$repo_root/tests/provider-authorization.sh" > "$case_dir/provider-authorization.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/provider-authorization.log" >&2; scrub_log "$case_dir/provider-authorization.log"; exit "$status"; }
  scrub_log "$case_dir/provider-authorization.log"

  # --- Provider credential checks (Codex read-write access) ---
  echo "Running provider credential checks..."
  CREDENTIAL_TEST_IMAGE=$base_tag \
    "$repo_root/tests/provider-credentials.sh" > "$case_dir/provider-credentials.log" 2>&1 \
    || { status=$?; sed -n '1,200p' "$case_dir/provider-credentials.log" >&2; scrub_log "$case_dir/provider-credentials.log"; exit "$status"; }
  scrub_log "$case_dir/provider-credentials.log"

  # --- Runtime configuration checks (generation and validation) ---
  echo "Running runtime configuration checks..."
  "$repo_root/tests/runtime-config.sh" > "$case_dir/runtime-config.log" 2>&1 \
    || { status=$?; sed -n '1,200p' "$case_dir/runtime-config.log" >&2; scrub_log "$case_dir/runtime-config.log"; exit "$status"; }
  scrub_log "$case_dir/runtime-config.log"

  # --- Child image static checks ---
  echo "Running child image static checks..."
  "$repo_root/tests/child-image-static.sh" > "$case_dir/child-image-static.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/child-image-static.log" >&2; scrub_log "$case_dir/child-image-static.log"; exit "$status"; }
  scrub_log "$case_dir/child-image-static.log"

  # --- Provider example checks (Codex and Ollama) ---
  echo "Running provider example checks (Codex and Ollama)..."
  SKIP_SDK_BUILDS=1 "$repo_root/tests/examples-build.sh" > "$case_dir/examples-build.log" 2>&1 \
    || { status=$?; sed -n '1,120p' "$case_dir/examples-build.log" >&2; scrub_log "$case_dir/examples-build.log"; exit "$status"; }
  scrub_log "$case_dir/examples-build.log"

  # --- Go child-image build and inheritance contract ---
  echo "Running Go child-image build and inheritance contract..."
  BASE_IMAGE=$base_tag CONTAINER_CLI=podman PLATFORM=linux/amd64 \
    "$repo_root/tests/examples-build.sh" > "$case_dir/go-child-build.log" 2>&1 \
    || { status=$?; sed -n '1,200p' "$case_dir/go-child-build.log" >&2; scrub_log "$case_dir/go-child-build.log"; exit "$status"; }
  scrub_log "$case_dir/go-child-build.log"

  # --- Rootless Podman keep-id execution (C5) ---
  echo "Running rootless Podman keep-id execution tests..."
  IMAGE=$base_tag \
  IDENTITY_GROUP_PATH=$group_path \
  IDENTITY_GROUP_GID=$supplementary_gid \
  EVIDENCE_DIR=$case_dir \
    "$repo_root/tests/rootless-podman.sh" > "$case_dir/rootless-podman.log" 2>&1 \
    || { status=$?; sed -n '1,200p' "$case_dir/rootless-podman.log" >&2; scrub_log "$case_dir/rootless-podman.log"; exit "$status"; }
  scrub_log "$case_dir/rootless-podman.log"

  # --- Dev Container CLI with rootless Podman (C6/V8) ---
  echo "Running Dev Container CLI integrations tests..."
  IDENTITY_CASE=$identity_case \
  CYCLESTONE_BASE_IMAGE_ID=$base_id \
  CYCLESTONE_BASE_IMAGE_LOCAL=$base_tag \
  EVIDENCE_DIR=$case_dir \
    "$repo_root/tests/devcontainer-podman.sh" > "$case_dir/devcontainer-podman.log" 2>&1 \
    || { status=$?; sed -n '1,320p' "$case_dir/devcontainer-podman.log" >&2; scrub_log "$case_dir/devcontainer-podman.log"; exit "$status"; }
  scrub_log "$case_dir/devcontainer-podman.log"

  # --- Release-automation metadata verification ---
  echo "Verifying release-automation workflow metadata..."
  release_workflow=$repo_root/.github/workflows/release-image.yml
  test -s "$release_workflow" || fail 'release-image.yml is missing'
  grep -q "github.repository == 'patrick-folster/cyclestone-dev-containers'" "$release_workflow" \
    || fail 'release workflow does not restrict to the canonical repository'
  grep -q 'contents: read' "$release_workflow" \
    || fail 'release workflow must restrict contents permission to read'
  grep -q 'packages: write' "$release_workflow" \
    || fail 'release workflow must grant packages write permission'
  grep -q 'id-token: write' "$release_workflow" \
    || fail 'release workflow must grant id-token write for provenance'
  grep -q 'aquasecurity/trivy-action@' "$release_workflow" \
    || fail 'release workflow must include Trivy vulnerability scanning'
  grep -q 'actions/attest-build-provenance@' "$release_workflow" \
    || fail 'release workflow must include build provenance attestation'
  grep -q 'platforms: linux/amd64,linux/arm64' "$release_workflow" \
    || fail 'release workflow must build multi-architecture images'
  grep -q 'sbom: true' "$release_workflow" \
    || fail 'release workflow must generate SBOM'
  cp "$release_workflow" "$case_dir/release-image.yml"
  echo "PASS: release-automation workflow metadata verified"

  # --- Verify delivery roadmap and validation checklist ---
  echo "Verifying delivery roadmap and validation checklist..."
  test -s "$repo_root/docs/architecture/delivery-roadmap.md" \
    || fail 'delivery-roadmap.md is missing'
  grep -q 'ms-pf-0001' "$repo_root/docs/architecture/delivery-roadmap.md" \
    || fail 'delivery roadmap must reference ms-pf-0001'
  grep -q 'ms-pf-0015' "$repo_root/docs/architecture/delivery-roadmap.md" \
    || fail 'delivery roadmap must reference ms-pf-0015'
  grep -q 'C1.*C10\|C1.*C7.*C10\|C7.*C10' "$repo_root/docs/architecture/delivery-roadmap.md" \
    || fail 'delivery roadmap must reference compatibility rows'
  grep -q 'Out of scope\|out-of-scope\|Out of scope' "$repo_root/docs/architecture/delivery-roadmap.md" \
    || fail 'delivery roadmap must include out-of-scope items'
  grep -q '2026-09-30' "$repo_root/docs/architecture/compatibility.md" \
    || fail 'compatibility.md must include deferred evidence deadline'
  grep -q 'DEFERRED' "$repo_root/docs/architecture/validation-checklist.md" \
    || fail 'validation-checklist.md must mark deferred evidence items'

  printf 'status=pass\ncommit=%s\nsource_digest=%s\nidentity_case=%s\nbase_id=%s\n' \
    "$revision" "$source_digest" "$identity_case" "$base_id" > "$case_dir/result.txt"
  echo "PASS: MVP qualification ($identity_case)"

  for required_case in matching differing; do
    result=$evidence_root/$required_case/result.txt
    test -f "$result" \
      || fail "the $required_case local identity case has not passed; run this command as the corresponding local account"
    grep -Fx "status=pass" "$result" >/dev/null \
      || fail "the $required_case result is not successful"
    grep -Fx "commit=$revision" "$result" >/dev/null \
      || fail "the $required_case result belongs to another commit"
    grep -Fx "source_digest=$source_digest" "$result" >/dev/null \
      || fail "the $required_case result belongs to different source content"
    test -s "$evidence_root/$required_case/conflict-observation.txt" \
      || fail "the $required_case result lacks updateRemoteUserUID evidence"
  done
  echo 'PASS: both local rootless-Podman identity cases qualify the milestone cycle'
  exit 0
fi
if test "${security_boundary_milestone:-false}" = true; then
  test "$(uname -s)" = Linux || fail 'security boundary validation requires Linux'
  test "$(id -u)" -ne 0 || fail 'run security boundary validation as the non-root Podman user'
  for command in git jq realpath stat sha256sum flock sync socat podman devcontainer; do
    command -v "$command" >/dev/null 2>&1 || fail "$command is unavailable"
  done
  test "$(devcontainer --version)" = 0.86.0 || fail 'Dev Container CLI 0.86.0 is required'
  evidence_dir=${EVIDENCE_DIR:-$repo_root/dist/evidence/ms-pf-0011/local}
  mkdir -p "$evidence_dir"
  revision=$(git -C "$repo_root" rev-parse HEAD)
  source_digest=$(git -C "$repo_root" ls-files --cached --others --exclude-standard | LC_ALL=C sort | while IFS= read -r path; do test -f "$repo_root/$path" || continue; printf '%s %s %s\n' "$(stat -c %a "$repo_root/$path")" "$(sha256sum "$repo_root/$path"|awk '{print $1}')" "$path"; done | sha256sum | awk '{print $1}')
  "$repo_root/tests/contracts.sh" >"$evidence_dir/contracts.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/contracts.log" >&2; exit "$status"; }
  "$repo_root/tests/provider-registry.sh" >"$evidence_dir/provider-registry.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/provider-registry.log" >&2; exit "$status"; }
  "$repo_root/tests/provider-authorization.sh" >"$evidence_dir/provider-authorization.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/provider-authorization.log" >&2; exit "$status"; }
  "$repo_root/tests/provider-credentials.sh" >"$evidence_dir/provider-credentials.log" 2>&1 || { status=$?; sed -n '1,200p' "$evidence_dir/provider-credentials.log" >&2; exit "$status"; }
  "$repo_root/tests/runtime-config.sh" >"$evidence_dir/runtime-config.log" 2>&1 || { status=$?; sed -n '1,200p' "$evidence_dir/runtime-config.log" >&2; exit "$status"; }
  "$repo_root/tests/child-image-static.sh" >"$evidence_dir/child-image-static.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/child-image-static.log" >&2; exit "$status"; }
  printf 'status=pass\ncommit=%s\nsource_digest=%s\ndevcontainer_version=0.86.0\n' "$revision" "$source_digest" >"$evidence_dir/result.txt"
  echo 'PASS: local end-to-end security boundary milestone validation'
  exit 0
fi

if test "${host_services_selinux_milestone:-false}" = true; then
  test "$(uname -s)" = Linux || fail 'host services and SELinux validation requires Linux'
  test "$(id -u)" -ne 0 || fail 'run host services and SELinux validation as the non-root Podman user'
  for command in git jq realpath stat sha256sum flock sync socat podman devcontainer; do
    command -v "$command" >/dev/null 2>&1 || fail "$command is unavailable"
  done
  test "$(devcontainer --version)" = 0.86.0 || fail 'Dev Container CLI 0.86.0 is required'
  test "$(podman info --format '{{.Host.Security.Rootless}}')" = true || fail 'Podman is not rootless'
  test "$(podman info --format json | jq -r '.host.ociRuntime.name')" = crun || fail 'Podman must use crun'
  grep -q "^$(id -un):" /etc/subuid || fail 'the invoking user has no /etc/subuid range'
  grep -q "^$(id -un):" /etc/subgid || fail 'the invoking user has no /etc/subgid range'
  evidence_dir=${EVIDENCE_DIR:-$repo_root/dist/evidence/ms-pf-0010/local}
  mkdir -p "$evidence_dir"
  revision=$(git -C "$repo_root" rev-parse HEAD)
  source_digest=$(git -C "$repo_root" ls-files --cached --others --exclude-standard | LC_ALL=C sort | while IFS= read -r path; do test -f "$repo_root/$path" || continue; printf '%s %s %s\n' "$(stat -c %a "$repo_root/$path")" "$(sha256sum "$repo_root/$path"|awk '{print $1}')" "$path"; done | sha256sum | awk '{print $1}')
  "$repo_root/tests/provider-registry.sh" >"$evidence_dir/provider-registry.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/provider-registry.log" >&2; exit "$status"; }
  "$repo_root/tests/provider-authorization.sh" >"$evidence_dir/provider-authorization.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/provider-authorization.log" >&2; exit "$status"; }
  "$repo_root/tests/provider-credentials.sh" >"$evidence_dir/provider-credentials.log" 2>&1 || { status=$?; sed -n '1,200p' "$evidence_dir/provider-credentials.log" >&2; exit "$status"; }
  "$repo_root/tests/runtime-config.sh" >"$evidence_dir/runtime-config.log" 2>&1 || { status=$?; sed -n '1,200p' "$evidence_dir/runtime-config.log" >&2; exit "$status"; }
  printf 'status=pass\ncommit=%s\nsource_digest=%s\ndevcontainer_version=0.86.0\nselinux=%s\n' "$revision" "$source_digest" "$(getenforce 2>/dev/null || echo Disabled)" >"$evidence_dir/result.txt"
  echo 'PASS: local host-services-selinux milestone validation'
  exit 0
fi

if test "${runtime_config_milestone:-false}" = true; then
  test "$(uname -s)" = Linux || fail 'runtime configuration validation requires Linux'
  test "$(id -u)" -ne 0 || fail 'run runtime configuration validation as the non-root Podman user'
  for command in git jq realpath stat sha256sum flock sync socat podman devcontainer; do
    command -v "$command" >/dev/null 2>&1 || fail "$command is unavailable"
  done
  test "$(devcontainer --version)" = 0.86.0 || fail 'Dev Container CLI 0.86.0 is required'
  test "$(podman info --format '{{.Host.Security.Rootless}}')" = true || fail 'Podman is not rootless'
  test "$(podman info --format json | jq -r '.host.ociRuntime.name')" = crun || fail 'Podman must use crun'
  grep -q "^$(id -un):" /etc/subuid || fail 'the invoking user has no /etc/subuid range'
  grep -q "^$(id -un):" /etc/subgid || fail 'the invoking user has no /etc/subgid range'
  evidence_dir=${EVIDENCE_DIR:-$repo_root/dist/evidence/ms-pf-0009/local}
  mkdir -p "$evidence_dir"
  revision=$(git -C "$repo_root" rev-parse HEAD)
  source_digest=$(git -C "$repo_root" ls-files --cached --others --exclude-standard | LC_ALL=C sort | while IFS= read -r path; do test -f "$repo_root/$path" || continue; printf '%s %s %s\n' "$(stat -c %a "$repo_root/$path")" "$(sha256sum "$repo_root/$path"|awk '{print $1}')" "$path"; done | sha256sum | awk '{print $1}')
  "$repo_root/tests/provider-registry.sh" >"$evidence_dir/provider-registry.log" 2>&1 || { status=$?; sed -n '1,120p' "$evidence_dir/provider-registry.log" >&2; exit "$status"; }
  "$repo_root/tests/runtime-config.sh" >"$evidence_dir/runtime-config.log" 2>&1 || { status=$?; sed -n '1,200p' "$evidence_dir/runtime-config.log" >&2; exit "$status"; }
  printf 'status=pass\ncommit=%s\nsource_digest=%s\ndevcontainer_version=0.86.0\n' "$revision" "$source_digest" >"$evidence_dir/result.txt"
  sed -n '1,80p' "$evidence_dir/provider-registry.log"
  sed -n '1,80p' "$evidence_dir/runtime-config.log"
  echo 'PASS: local runtime-configuration milestone validation'
  exit 0
fi

if test "${credential_milestone:-false}" = true; then
  test "$(uname -s)" = Linux || fail 'provider credential validation requires Linux'
  test "$(id -u)" -ne 0 || fail 'run provider credential validation as the non-root Podman user'
  for command in git jq podman socat realpath stat sha256sum base64; do command -v "$command" >/dev/null 2>&1 || fail "$command is unavailable"; done
  test "$(podman info --format '{{.Host.Security.Rootless}}')" = true || fail 'Podman is not rootless'
  test "$(podman info --format json | jq -r '.host.ociRuntime.name')" = crun || fail 'Podman must use crun'
  evidence_dir=${EVIDENCE_DIR:-$repo_root/dist/evidence/ms-pf-0008/local}
  mkdir -p "$evidence_dir"
  revision=$(git rev-parse HEAD)
  source_digest=$(git ls-files --cached --others --exclude-standard | LC_ALL=C sort | while IFS= read -r path; do test -f "$path" || continue; printf '%s %s %s\n' "$(stat -c %a "$path")" "$(sha256sum "$path"|awk '{print $1}')" "$path"; done | sha256sum | awk '{print $1}')
  image=${CREDENTIAL_TEST_IMAGE:-}
  if test -z "$image"; then
    image=cyclestone-base:provider-credentials-local
    iid_file=$evidence_dir/base-image.iid
    if podman image exists "$image" && test -s "$iid_file"; then
      expected_id=$(sed -n '1p' "$iid_file"); case "$expected_id" in sha256:*) :;; *) expected_id=sha256:$expected_id;; esac
      resolved_id=$(podman image inspect --format '{{.Id}}' "$image"); case "$resolved_id" in sha256:*) :;; *) resolved_id=sha256:$resolved_id;; esac
      test "$resolved_id" = "$expected_id" || fail 'existing credential image does not match retained builder identity'
      test "$(podman image inspect --format '{{index .Labels "org.opencontainers.image.revision"}}' "$image")" = "$revision" || fail 'existing credential image belongs to another revision'
      printf 'PASS: reused verified local image %s\n' "$resolved_id" >"$evidence_dir/base-build.log"
    else
      created=$(date -u -d "$(git show -s --format=%cI HEAD)" +%Y-%m-%dT%H:%M:%SZ)
      IMAGE_VERSION=1.0.0-local IMAGE_REVISION=$revision IMAGE_CREATED=$created IMAGE_LICENSES=LicenseRef-Container-Image-Review-Required IMAGE_TAG=$image IID_FILE=$iid_file \
        "$repo_root/scripts/build-base-podman.sh" >"$evidence_dir/base-build.log" 2>&1 || { status=$?; sed -n '1,160p' "$evidence_dir/base-build.log" >&2; exit "$status"; }
    fi
  fi
  image_id=$(podman image inspect --format '{{.Id}}' "$image") || fail 'credential test image is unavailable'
  CREDENTIAL_TEST_IMAGE=$image "$repo_root/tests/provider-credentials.sh" >"$evidence_dir/validation.log" 2>&1 || { status=$?; sed -n '1,200p' "$evidence_dir/validation.log" >&2; exit "$status"; }
  printf 'status=pass\ncommit=%s\nsource_digest=%s\nimage=%s\nimage_id=%s\n' "$revision" "$source_digest" "$image" "$image_id" >"$evidence_dir/result.txt"
  sed -n '1,80p' "$evidence_dir/validation.log"
  echo 'PASS: local secure-provider-credentials milestone validation'
  exit 0
fi

test "$(uname -s)" = Linux || fail 'local milestone validation requires Linux'
test "$(uname -m)" = x86_64 || fail 'local milestone validation requires amd64'
test "$(id -u)" -ne 0 || fail 'run this command as the non-root Podman user'
for command in git jq podman devcontainer; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is unavailable"
done
test "$(podman info --format '{{.Host.Security.Rootless}}')" = true \
  || fail 'Podman is not rootless'
test "$(podman info --format json | jq -r '.host.ociRuntime.name')" = crun \
  || fail 'Podman must use crun'
podman_version=$(podman version --format '{{.Client.Version}}')
podman_major=$(printf '%s\n' "$podman_version" | cut -d. -f1)
podman_minor=$(printf '%s\n' "$podman_version" | cut -d. -f2)
case "$podman_major:$podman_minor" in
  *[!0-9:]*|:*|*:) fail "cannot parse Podman version: $podman_version" ;;
esac
test "$podman_major" -gt 4 || { test "$podman_major" -eq 4 && test "$podman_minor" -ge 9; } \
  || fail 'Podman 4.9 or newer is required'
test "$(devcontainer --version)" = 0.86.0 \
  || fail 'Dev Container CLI 0.86.0 is required'
grep -q "^$(id -un):" /etc/subuid || fail 'the invoking user has no /etc/subuid range'
grep -q "^$(id -un):" /etc/subgid || fail 'the invoking user has no /etc/subgid range'

host_uid=$(id -u)
host_gid=$(id -g)
case "$host_uid:$host_gid" in
  1000:1000) identity_case=matching ;;
  *) identity_case=differing ;;
esac
if test -n "${IDENTITY_CASE:-}" && test "$IDENTITY_CASE" != "$identity_case"; then
  fail "IDENTITY_CASE=$IDENTITY_CASE does not match host identity $host_uid:$host_gid ($identity_case)"
fi

revision=$(git -C "$repo_root" rev-parse HEAD)
source_digest=$(
  git -C "$repo_root" ls-files --cached --others --exclude-standard \
    | LC_ALL=C sort \
    | while IFS= read -r path; do
        test -f "$repo_root/$path" || continue
        printf '%s %s %s\n' \
          "$(stat -c %a "$repo_root/$path")" \
          "$(sha256sum "$repo_root/$path" | awk '{print $1}')" \
          "$path"
      done \
    | sha256sum \
    | awk '{print $1}'
)
created=$(date -u -d "$(git -C "$repo_root" show -s --format=%cI HEAD)" +%Y-%m-%dT%H:%M:%SZ)
evidence_root=${EVIDENCE_DIR:-$repo_root/dist/evidence/ms-pf-0005/local}
case_dir=$evidence_root/$identity_case
iid_file=$case_dir/base-image.iid
if ! test -d "$evidence_root"; then
  mkdir -p "$evidence_root"
  chmod 1777 "$evidence_root"
fi
test -w "$evidence_root" \
  || fail "evidence directory is not writable: $evidence_root"
if test -d "$case_dir"; then
  test "$(stat -c %u "$case_dir")" = "$host_uid" \
    || fail "identity evidence directory is owned by another account: $case_dir"
else
  mkdir "$case_dir"
fi
printf 'milestone=%s\ncommit=%s\nsource_digest=%s\nhost_uid=%s\nhost_gid=%s\nidentity_case=%s\n' \
  ms-pf-0005-integrate-devcontainer-workflows "$revision" "$source_digest" "$host_uid" "$host_gid" "$identity_case" \
  > "$case_dir/local-request.txt"

IMAGE_VERSION=1.0.0-local \
IMAGE_REVISION=$revision \
IMAGE_CREATED=$created \
IMAGE_LICENSES=LicenseRef-Container-Image-Review-Required \
IMAGE_TAG=cyclestone-base:project-devcontainer-local-$identity_case \
IID_FILE=$iid_file \
  "$repo_root/scripts/build-base-podman.sh" > "$case_dir/base-build.log" 2>&1 \
  || { status=$?; sed -n '1,240p' "$case_dir/base-build.log" >&2; exit "$status"; }
sed -n '1,240p' "$case_dir/base-build.log"

base_id=$(sed -n '1p' "$iid_file")
IDENTITY_CASE=$identity_case \
CYCLESTONE_BASE_IMAGE_ID=$base_id \
CYCLESTONE_BASE_IMAGE_LOCAL=cyclestone-base:project-devcontainer-local-$identity_case \
EVIDENCE_DIR=$case_dir \
  "$repo_root/tests/devcontainer-podman.sh" > "$case_dir/validation.log" 2>&1 \
  || { status=$?; sed -n '1,320p' "$case_dir/validation.log" >&2; exit "$status"; }
sed -n '1,320p' "$case_dir/validation.log"

printf 'status=pass\ncommit=%s\nsource_digest=%s\nidentity_case=%s\nbase_id=%s\n' \
  "$revision" "$source_digest" "$identity_case" "$base_id" > "$case_dir/result.txt"
echo "PASS: local Podman milestone validation ($identity_case)"

for required_case in matching differing; do
  result=$evidence_root/$required_case/result.txt
  test -f "$result" \
    || fail "the $required_case local identity case has not passed; run this command as the corresponding local account"
  grep -Fx "status=pass" "$result" >/dev/null \
    || fail "the $required_case result is not successful"
  grep -Fx "commit=$revision" "$result" >/dev/null \
    || fail "the $required_case result belongs to another commit"
  grep -Fx "source_digest=$source_digest" "$result" >/dev/null \
    || fail "the $required_case result belongs to different source content"
  test -s "$evidence_root/$required_case/conflict-observation.txt" \
    || fail "the $required_case result lacks updateRemoteUserUID evidence"
done
echo 'PASS: both local rootless-Podman identity cases qualify the milestone cycle'
