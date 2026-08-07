#!/bin/sh
set -eu

image=${IMAGE:-cyclestone-base:1.0.0}
compare_image=${COMPARE_IMAGE:-}
image_archive=${IMAGE_ARCHIVE:-}
image_platform=${IMAGE_PLATFORM:-}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required host command is unavailable: $1"
}

descriptor_blob() {
  descriptor_root=$1
  descriptor_digest=$2
  descriptor_size=$3
  printf '%s\n' "$descriptor_digest" | grep -Eq '^sha256:[0-9a-f]{64}$' \
    || fail "unsupported or malformed descriptor digest: $descriptor_digest"
  descriptor_hash=${descriptor_digest#sha256:}
  test "${#descriptor_hash}" -eq 64 || fail "malformed SHA-256 descriptor: $descriptor_digest"
  descriptor_path=$descriptor_root/blobs/sha256/$descriptor_hash
  if ! test -f "$descriptor_path" || ! test -r "$descriptor_path"; then
    fail "referenced blob is missing or unreadable: $descriptor_digest"
  fi
  actual_size=$(wc -c < "$descriptor_path" | tr -d ' ')
  test "$actual_size" = "$descriptor_size" \
    || fail "descriptor size mismatch for $descriptor_digest"
  actual_digest=$(sha256sum "$descriptor_path" | awk '{print $1}')
  test "$actual_digest" = "$descriptor_hash" \
    || fail "descriptor digest mismatch for $descriptor_digest"
  printf '%s\n' "$descriptor_path"
}

validate_member_names() {
  member_list=$1
  awk '
    /^\// { exit 1 }
    {
      count = split($0, component, "/")
      for (i = 1; i <= count; i++) if (component[i] == "..") exit 1
    }
  ' "$member_list" || fail 'archive contains an unsafe absolute or parent path'
  duplicates=$(LC_ALL=C sort "$member_list" | uniq -d)
  test -z "$duplicates" || fail "archive contains duplicate members: $duplicates"
}

inspect_layer_tar() {
  layer_tar=$1
  layer_name=$2
  expected_diff_id=$3
  test -s "$layer_tar" || fail "empty layer payload: $layer_name"
  actual_diff_id=sha256:$(sha256sum "$layer_tar" | awk '{print $1}')
  test "$actual_diff_id" = "$expected_diff_id" \
    || fail "uncompressed layer digest mismatch: $layer_name"

  layer_members=$inspect_root/layer-members
  tar -tf "$layer_tar" > "$layer_members" || fail "unreadable layer tar: $layer_name"
  validate_member_names "$layer_members"
  sed 's#^\./##' "$layer_members" > "$layer_members.normalized"

  if grep -Eq '(^|/)(\.ssh|\.aws|\.azure|\.kube|\.docker|\.gnupg|\.netrc|\.npmrc|\.pypirc|\.gitconfig|id_rsa|id_ed25519|credentials|[^/]*\.(key|p12|pfx))(/|$)' \
    "$layer_members.normalized"; then
    fail "credential or personal configuration path found in layer: $layer_name"
  fi
  if grep -Eq '(^|/)(\.git|\.hg|\.svn)(/|$)|^workspace/.+[^/]$' \
    "$layer_members.normalized"; then
    fail "project source path found in layer: $layer_name"
  fi
  temporary_or_cache=$(grep -E '^(tmp|var/tmp)/.+[^/]$|^var/(lib/apt/lists|cache/apt/archives)/.+[^/]$' \
    "$layer_members.normalized" | grep -Ev '^var/(lib/apt/lists|cache/apt/archives)/lock$' || true)
  test -z "$temporary_or_cache" \
    || fail "temporary or package-cache file found in layer $layer_name: $temporary_or_cache"
  if grep -Eq '(^|/)(checksums\.txt|base-packages\.txt|packages\.txt|versions\.env|install-tools\.sh|install-cyclestone\.sh|cyclestone_.*\.tar\.(gz|xz|zst)|codex-.*\.tar\.gz)$' \
    "$layer_members.normalized"; then
    fail "build-only artifact found in layer: $layer_name"
  fi
  if grep -Eq '(^|/)(usr/)?(local/)?(s?bin/)?(go|gofmt|node|npm|npx|dotnet|python[0-9.]*|java|javac|ruby|php|cargo|rustc)$|^var/lib/dpkg/info/(golang|nodejs|npm|dotnet|python|openjdk|default-jre|default-jdk|ruby|php|rustc|cargo)' \
    "$layer_members.normalized"; then
    fail "forbidden runtime or SDK path found in layer: $layer_name"
  fi

  content_candidates=$inspect_root/layer-content-candidates
  grep -E '\.(conf|config|env|ini|json|md|sh|toml|txt|ya?ml)$|(^|/)etc/environment$' \
    "$layer_members" > "$content_candidates" || true
  while IFS= read -r content_member; do
    if LC_ALL=C tar -xOf "$layer_tar" "$content_member" 2>/dev/null | \
      LC_ALL=C grep -aEq 'BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY|AWS_SECRET_ACCESS_KEY=|AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{20,}'; then
      fail "credential-like content found in layer $layer_name: $content_member"
    fi
  done < "$content_candidates"
}

materialize_layer() {
  layer_blob=$1
  layer_media_type=$2
  layer_tar=$3
  case "$layer_media_type" in
    application/vnd.oci.image.layer.v1.tar|application/vnd.docker.image.rootfs.diff.tar)
      cp "$layer_blob" "$layer_tar"
      ;;
    application/vnd.oci.image.layer.v1.tar+gzip|application/vnd.docker.image.rootfs.diff.tar.gzip)
      gzip -dc "$layer_blob" > "$layer_tar" || fail "invalid gzip layer: $layer_blob"
      ;;
    application/vnd.oci.image.layer.v1.tar+zstd)
      require_command zstd
      zstd -q -d -c "$layer_blob" > "$layer_tar" || fail "invalid zstd layer: $layer_blob"
      ;;
    *) fail "unsupported layer media type: $layer_media_type" ;;
  esac
}

inspect_oci_archive() {
  archive_root=$1
  index_file=$archive_root/index.json
  jq -e '.schemaVersion == 2 and (.manifests | type == "array")' "$index_file" >/dev/null \
    || fail 'invalid OCI index.json'

  candidates=$inspect_root/oci-candidates
  jq -r --arg platform "$image_platform" '
    .manifests[]
    | select(.annotations["vnd.docker.reference.type"] != "attestation-manifest")
    | select(.mediaType == "application/vnd.oci.image.manifest.v1+json"
          or .mediaType == "application/vnd.docker.distribution.manifest.v2+json")
    | select($platform == "" or .platform == null
          or ((.platform.os + "/" + .platform.architecture) == $platform))
    | [.digest, (.size | tostring)] | @tsv
  ' "$index_file" > "$candidates"
  candidate_count=$(wc -l < "$candidates" | tr -d ' ')
  test "$candidate_count" -eq 1 \
    || fail "expected exactly one OCI image manifest for '${image_platform:-unspecified platform}', found $candidate_count"
  tab=$(printf '\t')
  IFS=$tab read -r manifest_digest manifest_size < "$candidates"
  manifest_file=$(descriptor_blob "$archive_root" "$manifest_digest" "$manifest_size")
  jq -e '.schemaVersion == 2 and (.config | type == "object") and (.layers | type == "array")' \
    "$manifest_file" >/dev/null || fail 'invalid selected OCI image manifest'

  config_digest=$(jq -r '.config.digest' "$manifest_file")
  config_size=$(jq -r '.config.size' "$manifest_file")
  config_file=$(descriptor_blob "$archive_root" "$config_digest" "$config_size")
  jq -e '.rootfs.type == "layers" and (.rootfs.diff_ids | type == "array")' "$config_file" >/dev/null \
    || fail 'selected OCI image has an invalid configuration'

  layers=$inspect_root/oci-layers
  jq -r '.layers[] | [.digest, (.size | tostring), .mediaType] | @tsv' "$manifest_file" > "$layers"
  layer_count=$(wc -l < "$layers" | tr -d ' ')
  diff_count=$(jq '.rootfs.diff_ids | length' "$config_file")
  test "$layer_count" -gt 0 || fail 'selected OCI image references zero layers'
  test "$layer_count" -eq "$diff_count" \
    || fail "OCI layer/config count mismatch: $layer_count descriptors, $diff_count diff IDs"

  # OCI descriptors are content-addressed, so multiple stack positions may
  # legitimately reference the same blob (notably Docker's canonical empty
  # layer). Keep every occurrence and validate it against its positional diff ID.
  layer_number=0
  while IFS=$tab read -r layer_digest layer_size layer_media_type; do
    layer_number=$((layer_number + 1))
    layer_blob=$(descriptor_blob "$archive_root" "$layer_digest" "$layer_size")
    layer_tar=$inspect_root/layer-$layer_number.tar
    materialize_layer "$layer_blob" "$layer_media_type" "$layer_tar"
    expected_diff_id=$(jq -r ".rootfs.diff_ids[$((layer_number - 1))]" "$config_file")
    inspect_layer_tar "$layer_tar" "$layer_digest" "$expected_diff_id"
  done < "$layers"
  test "$layer_number" -eq "$layer_count" || fail 'OCI layer enumeration ended early'
}

inspect_docker_archive() {
  archive_root=$1
  manifest_file=$archive_root/manifest.json
  jq -e 'type == "array" and length == 1 and .[0].Config and (.[0].Layers | type == "array")' \
    "$manifest_file" >/dev/null || fail 'Docker archive must contain exactly one image manifest'
  config_rel=$(jq -r '.[0].Config' "$manifest_file")
  config_file=$archive_root/$config_rel
  if ! test -f "$config_file" || ! test -r "$config_file"; then
    fail 'Docker archive configuration is missing or unreadable'
  fi
  jq -e '.rootfs.type == "layers" and (.rootfs.diff_ids | type == "array")' "$config_file" >/dev/null \
    || fail 'Docker archive image has an invalid configuration'
  layers=$inspect_root/docker-layers
  jq -r '.[0].Layers[]' "$manifest_file" > "$layers"
  layer_count=$(wc -l < "$layers" | tr -d ' ')
  diff_count=$(jq '.rootfs.diff_ids | length' "$config_file")
  test "$layer_count" -gt 0 || fail 'Docker archive image references zero layers'
  test "$layer_count" -eq "$diff_count" \
    || fail "Docker layer/config count mismatch: $layer_count paths, $diff_count diff IDs"
  duplicate_layers=$(LC_ALL=C sort "$layers" | uniq -d)
  test -z "$duplicate_layers" || fail "duplicate Docker layer path: $duplicate_layers"
  referenced_layers=$inspect_root/docker-layers.sorted
  discovered_layers=$inspect_root/docker-discovered.sorted
  LC_ALL=C sort "$layers" > "$referenced_layers"
  (cd "$archive_root" && find . -type f -name layer.tar -print | sed 's#^\./##' | LC_ALL=C sort) > "$discovered_layers"
  cmp -s "$referenced_layers" "$discovered_layers" \
    || fail 'Docker archive contains missing or unaccounted layer.tar files'

  layer_number=0
  while IFS= read -r layer_rel; do
    layer_number=$((layer_number + 1))
    layer_tar=$archive_root/$layer_rel
    if ! test -f "$layer_tar" || ! test -r "$layer_tar"; then
      fail "referenced Docker layer is missing or unreadable: $layer_rel"
    fi
    expected_diff_id=$(jq -r ".rootfs.diff_ids[$((layer_number - 1))]" "$config_file")
    inspect_layer_tar "$layer_tar" "$layer_rel" "$expected_diff_id"
  done < "$layers"
  test "$layer_number" -eq "$layer_count" || fail 'Docker layer enumeration ended early'
}

inspect_saved_archive() {
  archive=$1
  if ! test -f "$archive" || ! test -r "$archive"; then
    fail "image archive is missing or unreadable: $archive"
  fi
  archive_members=$inspect_root/archive-members
  tar -tf "$archive" > "$archive_members" || fail "unreadable image archive: $archive"
  validate_member_names "$archive_members"
  archive_root=$inspect_root/unpacked
  mkdir "$archive_root"
  tar -xf "$archive" -C "$archive_root" || fail "could not extract image archive: $archive"
  if test -f "$archive_root/oci-layout" && test -f "$archive_root/index.json"; then
    inspect_oci_archive "$archive_root"
  elif test -f "$archive_root/manifest.json"; then
    inspect_docker_archive "$archive_root"
  else
    fail 'archive is neither an OCI image layout nor a Docker image archive'
  fi
}

require_command jq
require_command sha256sum
require_command tar

inspect_root=$(mktemp -d)
cleanup() {
  test -n "${inspect_root:-}" && test "$inspect_root" != / && rm -rf -- "$inspect_root"
}
trap cleanup EXIT HUP INT TERM

if test -n "$image_archive"; then
  inspect_saved_archive "$image_archive"
  echo "PASS: exact final-image layer coverage and prohibited-content checks ($image_archive)"
  exit 0
fi

docker image inspect "$image" >/dev/null 2>&1 || fail "image is not loaded: $image"

for label in org.opencontainers.image.title org.opencontainers.image.description \
  org.opencontainers.image.source org.opencontainers.image.url \
  org.opencontainers.image.documentation org.opencontainers.image.licenses \
  org.opencontainers.image.version org.opencontainers.image.revision \
  org.opencontainers.image.created org.opencontainers.image.base.digest \
  io.cyclestone.image.version io.cyclestone.tools; do
  value=$(docker image inspect --format "{{ index .Config.Labels \"$label\" }}" "$image")
  if test "$value" = '<no value>'; then
    fail "missing label: $label"
  fi
  # An empty io.cyclestone.tools value is valid: it denotes an empty-toolset
  # image (see docs/architecture/image-contract.md). All other labels must be
  # non-empty.
  if test -z "$value" && test "$label" != 'io.cyclestone.tools'; then
    fail "empty label: $label"
  fi
done

docker image inspect --format '{{json .Config}}' "$image" | \
  grep -Eqi '(AWS_SECRET_ACCESS_KEY|BEGIN [A-Z ]*PRIVATE KEY|password=|token=)' && \
  fail 'credential-like content found in image configuration'
docker history --no-trunc --format '{{.CreatedBy}}' "$image" | \
  grep -Eqi '(AWS_SECRET_ACCESS_KEY|BEGIN [A-Z ]*PRIVATE KEY|password=|token=)' && \
  fail 'credential-like content found in image history'

docker run --rm --user 0 --entrypoint /bin/sh "$image" -eu -c '
  packages=$(dpkg-query -W -f="\${Package}\n")
  printf "%s\n" "$packages" | grep -Eq "^(sudo|golang|nodejs|npm|dotnet|python[0-9.]*|openjdk|default-jre|default-jdk|ruby|php|rustc|cargo)(:|$)" && exit 1
  for command in sudo go node npm dotnet python python3 java javac ruby php cargo rustc; do
    ! command -v "$command" >/dev/null 2>&1
  done
  git_dependencies=$(dpkg-query -W -f="\${Depends}" git)
  case "$git_dependencies" in *perl*) ;; *) echo "Git no longer records its reviewed Perl dependency" >&2; exit 1 ;; esac
  unexpected_perl=$(printf "%s\n" "$packages" | grep -E "perl" | \
    grep -Ev "^(liberror-perl|libperl[0-9.]*t64|perl|perl-base|perl-modules-[0-9.]+)$" || true)
  test -z "$unexpected_perl" || { echo "unexpected Perl package: $unexpected_perl" >&2; exit 1; }
  test -z "$(find /var/lib/apt/lists /var/cache/apt -mindepth 1 \
    \( -type f -o -type l \) -print -quit)"
  test -z "$(find /tmp /var/tmp -mindepth 1 -print -quit)"
  test -z "$(find /workspace -mindepth 1 -print -quit)"
  for path in /root/.ssh /root/.aws /root/.azure /root/.kube /root/.docker /root/.gnupg \
    /home/developer/.ssh /home/developer/.aws /home/developer/.azure \
    /home/developer/.kube /home/developer/.docker /home/developer/.gnupg \
    /home/developer/.gitconfig /home/developer/.netrc /home/developer/.npmrc \
    /home/developer/.pypirc; do
    test ! -e "$path"
  done
  test -z "$(find / -xdev -type d \( -name .git -o -name .hg -o -name .svn \) -print -quit)"
  test -z "$(find / -xdev -type f \( -name "*.key" -o -name "*.p12" -o -name "*.pfx" \
    -o -name checksums.txt -o -name base-packages.txt -o -name versions.env \
    -o -name install-tools.sh -o -name install-cyclestone.sh \
    -o -name "cyclestone_*.tar.*" -o -name "codex-*.tar.gz" \) -print -quit)"
  test -z "$(find /home/developer -mindepth 1 -maxdepth 1 -name ".*" \
    ! -name .config ! -name .cache ! -name .local ! -name .opencode -print -quit)"
  tools="${INSTALL_TOOLS:-}"
  if printf "%s" ",$tools," | grep -q ",cyclestone,"; then
    test -f /home/developer/.local/share/licenses/cyclestone/LICENSE.md
    file /home/developer/.local/bin/cyclestone
    ldd /home/developer/.local/bin/cyclestone 2>&1 || true
  fi
  if printf "%s" ",$tools," | grep -q ",codex,"; then
    test -f /home/developer/.local/bin/codex
    test -x /home/developer/.local/bin/codex
    test -f /home/developer/.local/bin/codex-code-mode-host
    test -x /home/developer/.local/bin/codex-code-mode-host
    test "$(stat -c %U:%G /home/developer/.local/bin/codex /home/developer/.local/bin/codex-code-mode-host | uniq)" = developer:developer
    file /home/developer/.local/bin/codex /home/developer/.local/bin/codex-code-mode-host
  fi
  dpkg-query -W -f="\${Package}\t\${Version}\n" | LC_ALL=C sort
' || fail 'filesystem, package, runtime, or linkage inspection failed'

docker save --output "$inspect_root/image.tar" "$image"
inspect_saved_archive "$inspect_root/image.tar"

normalized_evidence() {
  evidence_image=$1
  output=$2
  {
    docker image inspect --format '{{.Config.User}}|{{.Config.WorkingDir}}|{{json .Config.Env}}|{{json .Config.Entrypoint}}|{{json .Config.Cmd}}|{{json .Config.Labels}}' "$evidence_image"
    docker run --rm --user 0 --entrypoint /bin/sh "$evidence_image" -c \
      'tools="${INSTALL_TOOLS:-}"
       if printf "%s" ",$tools," | grep -q ",cyclestone,"; then
         sha256sum /home/developer/.local/bin/cyclestone; cyclestone --version
       fi
       if printf "%s" ",$tools," | grep -q ",codex,"; then
         sha256sum /home/developer/.local/bin/codex /home/developer/.local/bin/codex-code-mode-host /home/developer/.local/bin/.codex-install-metadata
         codex --version
       fi
       dpkg-query -W -f="\${Package}\t\${Version}\n" | sort; stat -c "%n %U:%G %a" /home/developer /workspace /home/developer/.config /home/developer/.cache /home/developer/.local/share /home/developer/.config/cyclestone /home/developer/.local/share/cyclestone'
  } > "$output"
}

if test -n "$compare_image"; then
  docker image inspect "$compare_image" >/dev/null 2>&1 || fail "comparison image is not loaded: $compare_image"
  normalized_evidence "$image" "$inspect_root/first.evidence"
  normalized_evidence "$compare_image" "$inspect_root/second.evidence"
  diff -u "$inspect_root/first.evidence" "$inspect_root/second.evidence" \
    || fail 'normalized rebuild evidence differs'
fi

docker image inspect --format 'size_bytes={{.Size}}' "$image"
echo "PASS: final image configuration, packages, filesystem, layers, and normalized evidence ($image)"
