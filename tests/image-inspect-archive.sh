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

blob_hash() {
  sha256sum "$1" | awk '{print $1}'
}

blob_size() {
  wc -c < "$1" | tr -d ' '
}

make_layer() {
  layer_name=$1
  layer_text=$2
  layer_root=$test_root/$layer_name-root
  mkdir -p "$layer_root/usr/share/cyclestone-fixture"
  printf '%s\n' "$layer_text" > "$layer_root/usr/share/cyclestone-fixture/content"
  tar -cf "$test_root/$layer_name.tar" -C "$layer_root" .
}

install_blob() {
  layout=$1
  source_file=$2
  hash=$(blob_hash "$source_file")
  cp "$source_file" "$layout/blobs/sha256/$hash"
  printf '%s\n' "$hash"
}

write_oci_archive() {
  fixture=$1
  variant=$2
  layout=$test_root/$fixture-layout
  mkdir -p "$layout/blobs/sha256"
  printf '{"imageLayoutVersion":"1.0.0"}\n' > "$layout/oci-layout"

  make_layer "$fixture-one" one
  case "$variant" in
    credential)
      mkdir -p "$test_root/$fixture-one-root/root/.ssh"
      printf 'fixture\n' > "$test_root/$fixture-one-root/root/.ssh/id_rsa"
      ;;
    project)
      mkdir -p "$test_root/$fixture-one-root/workspace"
      printf 'fixture\n' > "$test_root/$fixture-one-root/workspace/source.c"
      ;;
    cache)
      mkdir -p "$test_root/$fixture-one-root/var/lib/apt/lists"
      printf 'fixture\n' > "$test_root/$fixture-one-root/var/lib/apt/lists/package-index"
      ;;
    temporary)
      mkdir -p "$test_root/$fixture-one-root/tmp"
      printf 'fixture\n' > "$test_root/$fixture-one-root/tmp/download"
      ;;
    buildtool)
      mkdir -p "$test_root/$fixture-one-root/usr/local/share/build"
      printf 'fixture\n' > "$test_root/$fixture-one-root/usr/local/share/build/checksums.txt"
      ;;
    runtime)
      mkdir -p "$test_root/$fixture-one-root/usr/bin"
      printf 'fixture\n' > "$test_root/$fixture-one-root/usr/bin/python3"
      ;;
    secret)
      printf '%s\n' '-----BEGIN PRIVATE KEY-----' > \
        "$test_root/$fixture-one-root/usr/share/cyclestone-fixture/secret.env"
      ;;
  esac
  tar -cf "$test_root/$fixture-one.tar" -C "$test_root/$fixture-one-root" .
  layer_one=$test_root/$fixture-one.tar
  layer_one_hash=$(blob_hash "$layer_one")
  layer_one_size=$(blob_size "$layer_one")
  layer_one_diff=sha256:$layer_one_hash
  make_layer "$fixture-two" two
  layer_two=$test_root/$fixture-two.tar
  layer_two_hash=$(blob_hash "$layer_two")
  layer_two_size=$(blob_size "$layer_two")

  layers=$(printf '{"mediaType":"application/vnd.oci.image.layer.v1.tar","digest":"sha256:%s","size":%s}' "$layer_one_hash" "$layer_one_size")
  diff_ids=$(printf '"%s"' "$layer_one_diff")
  case "$variant" in
    good|missing|digest|unreadable|credential|project|cache|temporary|buildtool|runtime|secret) ;;
    zero)
      layers=''
      diff_ids=''
      ;;
    repeated)
      layers="$layers,$layers"
      diff_ids="$diff_ids,$diff_ids"
      ;;
    extra)
      layers="$layers,$(printf '{"mediaType":"application/vnd.oci.image.layer.v1.tar","digest":"sha256:%s","size":%s}' "$layer_two_hash" "$layer_two_size")"
      ;;
    *) fail "unknown OCI fixture variant: $variant" ;;
  esac

  config=$test_root/$fixture-config.json
  printf '{"architecture":"amd64","os":"linux","rootfs":{"type":"layers","diff_ids":[%s]}}\n' \
    "$diff_ids" > "$config"
  config_hash=$(install_blob "$layout" "$config")
  config_size=$(blob_size "$config")
  manifest=$test_root/$fixture-manifest.json
  printf '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json","config":{"mediaType":"application/vnd.oci.image.config.v1+json","digest":"sha256:%s","size":%s},"layers":[%s]}\n' \
    "$config_hash" "$config_size" "$layers" > "$manifest"
  manifest_hash=$(install_blob "$layout" "$manifest")
  manifest_size=$(blob_size "$manifest")
  printf '{"schemaVersion":2,"manifests":[{"mediaType":"application/vnd.oci.image.manifest.v1+json","digest":"sha256:%s","size":%s,"platform":{"os":"linux","architecture":"amd64"}}]}\n' \
    "$manifest_hash" "$manifest_size" > "$layout/index.json"

  case "$variant" in
    zero) ;;
    missing) rm -f "$layout/blobs/sha256/$layer_one_hash" ;;
    digest)
      cp "$layer_one" "$layout/blobs/sha256/$layer_one_hash"
      printf 'corrupt' >> "$layout/blobs/sha256/$layer_one_hash"
      ;;
    unreadable) mkdir "$layout/blobs/sha256/$layer_one_hash" ;;
    *)
      cp "$layer_one" "$layout/blobs/sha256/$layer_one_hash"
      test "$variant" != extra || cp "$layer_two" "$layout/blobs/sha256/$layer_two_hash"
      ;;
  esac
  tar -cf "$test_root/$fixture.tar" -C "$layout" .
}

write_docker_archive() {
  fixture=$1
  layout=$test_root/$fixture-layout
  mkdir -p "$layout/layer-one"
  make_layer "$fixture" docker
  cp "$test_root/$fixture.tar" "$layout/layer-one/layer.tar"
  diff_id=sha256:$(blob_hash "$layout/layer-one/layer.tar")
  printf '{"architecture":"amd64","os":"linux","rootfs":{"type":"layers","diff_ids":["%s"]}}\n' \
    "$diff_id" > "$layout/config.json"
  printf '[{"Config":"config.json","RepoTags":["fixture:latest"],"Layers":["layer-one/layer.tar"]}]\n' \
    > "$layout/manifest.json"
  tar -cf "$test_root/$fixture-docker.tar" -C "$layout" .
}

expect_pass() {
  archive=$1
  if ! IMAGE_ARCHIVE="$archive" IMAGE_PLATFORM=linux/amd64 \
    "$repo_root/tests/image-inspect.sh" > "$test_root/pass.log" 2>&1; then
    sed -n '1,20p' "$test_root/pass.log" >&2
    fail "valid archive fixture failed: $archive"
  fi
}

expect_fail() {
  archive=$1
  if IMAGE_ARCHIVE="$archive" IMAGE_PLATFORM=linux/amd64 \
    "$repo_root/tests/image-inspect.sh" > "$test_root/failure.log" 2>&1; then
    fail "invalid archive fixture unexpectedly passed: $archive"
  fi
  grep -Fq 'FAIL:' "$test_root/failure.log" || fail "fixture did not fail closed: $archive"
}

write_oci_archive oci-good good
expect_pass "$test_root/oci-good.tar"
write_oci_archive oci-repeated repeated
expect_pass "$test_root/oci-repeated.tar"
write_docker_archive classic-good
expect_pass "$test_root/classic-good-docker.tar"

for variant in zero missing extra digest unreadable credential project cache temporary buildtool runtime secret; do
  write_oci_archive "oci-$variant" "$variant"
  expect_fail "$test_root/oci-$variant.tar"
done

echo 'PASS: archive inspection accepts repeated OCI blob references and rejects invalid coverage and prohibited content'
