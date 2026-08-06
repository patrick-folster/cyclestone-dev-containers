#!/bin/sh
set -eu
repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_error() {
  expected=$1; shift
  if "$@" >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"; then fail "expected $expected"; fi
  grep -Fq "ERROR $expected:" "$tmp_dir/stderr" || { sed -n '1,40p' "$tmp_dir/stderr" >&2; fail "missing $expected diagnostic"; }
  { printf 'EXPECTED %s\n' "$expected"; sed -n '1,40p' "$tmp_dir/stdout"; sed -n '1,40p' "$tmp_dir/stderr"; } >>"$tmp_dir/diagnostics.log"
}
for tool in git jq realpath stat sha256sum flock socat devcontainer mkfifo; do command -v "$tool" >/dev/null 2>&1 || fail "missing required host tool: $tool"; done
test "$(devcontainer --version)" = 0.86.0 || fail 'Dev Container CLI 0.86.0 is required'

export HOME="$tmp_dir/home"
export CYCLESTONE_DATA_DIR="$tmp_dir/state"
export ANTHROPIC_API_KEY='runtime-config-secret-canary'
export HTTPS_PROXY='http://runtime-config-proxy-canary.invalid'
export HTTP_PROXY='http://runtime-config-proxy-canary.invalid'
export NO_PROXY='runtime-config-no-proxy-canary.invalid'
export OLLAMA_HOST='http://runtime-config-ollama-canary.invalid'
export GEMINI_API_KEY='runtime-config-agy-canary'
export CYCLESTONE_SKIP_HOST_SERVICE_PROBE=1
mkdir -p "$HOME/.codex" "$HOME/.local/share/opencode" "$tmp_dir/bin"
printf '%s\n' '{"tokens":{"access_token":"runtime-config-codex-canary"}}' >"$HOME/.codex/auth.json"
printf '%s\n' '{"openai":{"type":"api","key":"runtime-config-opencode-canary"}}' >"$HOME/.local/share/opencode/auth.json"
chmod 600 "$HOME/.codex/auth.json" "$HOME/.local/share/opencode/auth.json"
printf '%s\n' '#!/bin/sh' 'echo "unexpected Podman execution" >&2' 'exit 99' >"$tmp_dir/bin/podman"
chmod +x "$tmp_dir/bin/podman"
export PATH="$tmp_dir/bin:$PATH"

project=$tmp_dir/project
mkdir -p "$project/.devcontainer"
cp templates/project-devcontainer/.devcontainer/Containerfile templates/project-devcontainer/.devcontainer/lifecycle.sh "$project/.devcontainer/"
cp templates/project-devcontainer/.devcontainer/devcontainer.json "$project/.devcontainer/devcontainer.json"
cp tests/fixtures/providers/valid/all.json "$project/providers.json"
cp .gitignore "$project/.gitignore"
git init -q "$project"
git -C "$project" config user.name 'Runtime Configuration Fixture'
git -C "$project" config user.email fixture.invalid
git -C "$project" add .devcontainer providers.json .gitignore
git -C "$project" commit -qm initial
request=$project/providers.json

approve() {
  provider=$1
  { sleep 1; printf 'a\n'; } | socat -,ignoreeof EXEC:"$repo_root/scripts/devcontainer-permissions.sh review $project $request $provider linux",pty,setsid,ctty >"$tmp_dir/review-$provider" 2>&1 || :
  grep -Fq '"authorized":true' "$tmp_dir/review-$provider" || { sed -n '1,60p' "$tmp_dir/review-$provider" >&2; fail "could not approve $provider"; }
}
for provider in agy claude codex generic-environment ollama opencode; do approve "$provider"; done

expect_error E_UNMANAGED_OUTPUT scripts/devcontainer-generate.sh "$project" "$request"
scripts/devcontainer-generate.sh "$project" "$request" --dry-run --replace >"$tmp_dir/dry-run"
grep -Fq 'CHANGE .devcontainer/devcontainer.json (unmanaged content redacted; replacement authorized)' "$tmp_dir/dry-run" || fail 'dry-run did not safely preview the unmanaged replacement'
grep -Fq 'CREATE .cyclestone/runtime/devcontainer.json (machine-local content redacted)' "$tmp_dir/dry-run" || fail 'dry-run omitted the redacted local creation preview'
if grep -Fq "$tmp_dir" "$tmp_dir/dry-run"; then fail 'dry-run disclosed an absolute local path'; fi
scripts/devcontainer-generate.sh "$project" "$request" --replace >"$tmp_dir/generated"
if grep -Fq "$tmp_dir" "$tmp_dir/generated"; then fail 'generation diagnostics disclosed an absolute local path'; fi
portable=$project/.devcontainer/devcontainer.json
local_config=$project/.cyclestone/runtime/devcontainer.json
test -f "$portable" && test -f "$local_config" || fail 'generator omitted an output'
cp "$portable" "$tmp_dir/portable-first"
cp "$local_config" "$tmp_dir/local-first"
portable_digest=$(sha256sum "$portable" | awk '{print $1}')
local_digest=$(sha256sum "$local_config" | awk '{print $1}')
scripts/devcontainer-generate.sh "$project" "$request" >"$tmp_dir/rerun"
cmp -s "$tmp_dir/portable-first" "$portable" && cmp -s "$tmp_dir/local-first" "$local_config" || fail 'identical generation changed bytes'
test "$portable_digest" = "$(sha256sum "$portable"|awk '{print $1}')" && test "$local_digest" = "$(sha256sum "$local_config"|awk '{print $1}')" || fail 'identical generation changed a digest'
scripts/devcontainer-generate.sh "$project" "$request" --dry-run >"$tmp_dir/no-diff"
test ! -s "$tmp_dir/no-diff" || fail 'no-op dry-run emitted a diff'
scripts/devcontainer-validate.sh "$project" "$request" >"$tmp_dir/validated"

mv "$local_config" "$tmp_dir/local-held"
expect_error E_OUTPUT_MISSING scripts/devcontainer-validate.sh "$project" "$request"
mv "$tmp_dir/local-held" "$local_config"
mv "$portable" "$tmp_dir/portable-held"
expect_error E_OUTPUT_MISSING scripts/devcontainer-validate.sh "$project" "$request"
mv "$tmp_dir/portable-held" "$portable"

mv "$local_config" "$tmp_dir/local-held"
mkdir "$local_config"
expect_error E_OUTPUT_PATH scripts/devcontainer-validate.sh "$project" "$request"
rmdir "$local_config"
mv "$tmp_dir/local-held" "$local_config"
mv "$portable" "$tmp_dir/portable-held"
ln -s "$tmp_dir/portable-held" "$portable"
expect_error E_OUTPUT_PATH scripts/devcontainer-validate.sh "$project" "$request"
rm "$portable"
mv "$tmp_dir/portable-held" "$portable"
printf '%s\n' '{malformed' >"$portable"
expect_error E_GENERATED_JSON scripts/devcontainer-validate.sh "$project" "$request"
cp "$tmp_dir/portable-first" "$portable"

cp "$portable" "$tmp_dir/portable-valid"
jq '.customizations.cyclestone.generatedRuntimeConfiguration.outputKind="local-runtime"' "$portable" >"$tmp_dir/tampered"
cp "$tmp_dir/tampered" "$portable"
expect_error E_GENERATED_SCHEMA scripts/devcontainer-validate.sh "$project" "$request"
expect_error E_UNMANAGED_OUTPUT scripts/devcontainer-generate.sh "$project" "$request"
cp "$tmp_dir/portable-valid" "$portable"

jq '.build.args.EVIL="injected"' "$portable" >"$tmp_dir/tampered"
cp "$tmp_dir/tampered" "$portable"
expect_error E_GENERATED_SCHEMA scripts/devcontainer-validate.sh "$project" "$request"
expect_error E_UNMANAGED_OUTPUT scripts/devcontainer-generate.sh "$project" "$request"
cp "$tmp_dir/portable-valid" "$portable"

jq '.customizations.cyclestone.generatedRuntimeConfiguration.inputIdentities.registrySha256=("0"*64)' "$portable" >"$tmp_dir/tampered"
cp "$tmp_dir/tampered" "$portable"
expect_error E_GENERATED_PAIR scripts/devcontainer-validate.sh "$project" "$request"
expect_error E_UNMANAGED_OUTPUT scripts/devcontainer-generate.sh "$project" "$request"
cp "$tmp_dir/portable-valid" "$portable"
jq '.customizations.cyclestone.generatedRuntimeConfiguration.inputIdentities.registrySha256=("1"*64)' "$portable" >"$tmp_dir/tampered-portable"
jq '.customizations.cyclestone.generatedRuntimeConfiguration.inputIdentities.registrySha256=("1"*64)' "$local_config" >"$tmp_dir/tampered-local"
cp "$tmp_dir/tampered-portable" "$portable"
cp "$tmp_dir/tampered-local" "$local_config"
expect_error E_METADATA_STALE scripts/devcontainer-validate.sh "$project" "$request"
cp "$tmp_dir/portable-valid" "$portable"
cp "$tmp_dir/local-first" "$local_config"
jq '(.customizations.cyclestone.runtimeAccess[]|select(.providerId=="claude").environmentNames)=["ANTHROPIC_API_KEY","OLLAMA_HOST"]' "$local_config" >"$tmp_dir/tampered-local"
cp "$tmp_dir/tampered-local" "$local_config"
expect_error E_GENERATED_PAIR scripts/devcontainer-validate.sh "$project" "$request"
cp "$tmp_dir/local-first" "$local_config"
jq -S '.customizations.cyclestone.generatedRuntimeConfiguration' "$portable" >"$tmp_dir/portable-metadata"
jq -S '.customizations.cyclestone.runtimeAccess' "$local_config" >"$tmp_dir/runtime-access"

# Compute the expected provenance metadata from the same committed inputs the
# generator uses (request, registry, template) so the check stays correct
# automatically whenever an input changes — no manual SHA resync. The structural
# validator (runtime_validate_generated_file) already enforces the schema; this
# independently verifies the generator wired the correct hashes and constants.
expected_request_hash=$(jq -S -c . "$request" | sha256sum | awk '{print $1}')
expected_registry_hash=$(jq -S -c . "$repo_root/providers/registry.json" | sha256sum | awk '{print $1}')
expected_template_hash=$(jq -S -c . "$repo_root/templates/project-devcontainer/.devcontainer/devcontainer.json" | sha256sum | awk '{print $1}')
jq -S -c -n \
  --arg generator 1.0.0 \
  --arg kind portable \
  --argjson safeMode false \
  --arg request "$expected_request_hash" \
  --arg registry "$expected_registry_hash" \
  --arg template "$expected_template_hash" \
  '{schemaVersion:1,generatorVersion:$generator,outputKind:$kind,safeMode:$safeMode,inputIdentities:{projectRequestSha256:$request,registrySha256:$registry,templateSha256:$template}}' \
  | jq -S . >"$tmp_dir/expected-portable-metadata"
cmp -s "$tmp_dir/expected-portable-metadata" "$tmp_dir/portable-metadata" || fail 'portable provenance metadata does not match the computed input hashes'
cmp -s tests/fixtures/runtime-config/golden/runtime-access.json "$tmp_dir/runtime-access" || fail 'runtime access ordering/merge golden changed'

jq -e '
  (.containerEnv|keys)==["ANTHROPIC_API_KEY","GEMINI_API_KEY","HTTPS_PROXY","HTTP_PROXY","NO_PROXY","OLLAMA_HOST"]
  and all(.containerEnv|to_entries[];.value==("${localEnv:"+.key+"}"))
  and ([.mounts[]|select(contains("/home/developer/.codex"))]|length)==1
  and ([.mounts[]|select(contains("/home/developer/.local/share/opencode"))]|length)==1
  and .runArgs==["--userns=keep-id:uid=1000,gid=1000","--security-opt=no-new-privileges"]
' "$local_config" >/dev/null || fail 'authorized runtime access or structural contracts are incomplete'
jq -e 'has("containerEnv")|not' "$portable" >/dev/null || fail 'portable output contains machine-local environment inheritance'
if grep -F -e 'runtime-config-secret-canary' -e 'runtime-config-proxy-canary' -e 'runtime-config-codex-canary' -e 'runtime-config-opencode-canary' -e 'runtime-config-agy-canary' "$portable" "$local_config" "$tmp_dir/generated" "$tmp_dir/validated" >/dev/null; then fail 'secret or secret-derived value reached generated output or logs'; fi
if grep -Fq "$tmp_dir" "$portable"; then fail 'portable output contains a local absolute path'; fi
git -C "$project" check-ignore -q .cyclestone/runtime/devcontainer.json || fail 'machine-local output is not ignored by Git policy'
test -n "$(git -C "$project" status --short .devcontainer/devcontainer.json)" || fail 'portable output is not visible to Git'

printf '%s\n' '{"version":1,"providers":{"codex":{"enabled":false,"mode":"disabled"}}}' >"$project/disabled.json"
printf '%s\n' '{"version":1,"providers":{"claude":{"enabled":true,"mode":"environment"}}}' >"$project/single.json"
printf '%s\n' '{"version":1,"providers":{"claude":{"enabled":true,"mode":"environment"},"codex":{"enabled":false,"mode":"disabled"},"ollama":{"enabled":true,"mode":"host-service"}}}' >"$project/mixed-disabled.json"
printf '%s\n' '{"version":1,"providers":{"codex":{"enabled":true,"mode":"read-only"}}}' >"$project/mode-changed.json"
git -C "$project" add disabled.json single.json mixed-disabled.json mode-changed.json
git -C "$project" commit -qm 'add provider combination fixtures'
scripts/devcontainer-generate.sh "$project" "$project/disabled.json" --replace >"$tmp_dir/disabled-generated"
scripts/devcontainer-validate.sh "$project" "$project/disabled.json" >"$tmp_dir/disabled-validated"
jq -e '.containerEnv=={} and .customizations.cyclestone.runtimeAccess==[] and (.mounts|length)==1' "$local_config" >/dev/null || fail 'disabled-only generation emitted runtime access'

scripts/devcontainer-generate.sh "$project" "$project/single.json" >"$tmp_dir/single-generated"
scripts/devcontainer-validate.sh "$project" "$project/single.json" >"$tmp_dir/single-validated"
jq -e '(.customizations.cyclestone.runtimeAccess|map(.providerId))==["claude"] and (.containerEnv|keys)==["ANTHROPIC_API_KEY"] and (.mounts|length)==1' "$local_config" >/dev/null || fail 'single-provider generation emitted an incorrect intersection'

scripts/devcontainer-generate.sh "$project" "$project/mixed-disabled.json" >"$tmp_dir/mixed-generated"
scripts/devcontainer-validate.sh "$project" "$project/mixed-disabled.json" >"$tmp_dir/mixed-validated"
jq -e '(.customizations.cyclestone.runtimeAccess|map(.providerId))==["claude","ollama"] and (.containerEnv|keys)==["ANTHROPIC_API_KEY","OLLAMA_HOST"] and (.mounts|length)==1' "$local_config" >/dev/null || fail 'mixed disabled/approved generation emitted an incorrect intersection'
expect_error E_PERMISSION scripts/devcontainer-generate.sh "$project" "$project/mode-changed.json"

scripts/devcontainer-generate.sh "$project" "$request" >"$tmp_dir/multi-restored"
cmp -s "$tmp_dir/portable-first" "$portable" && cmp -s "$tmp_dir/local-first" "$local_config" || fail 'multi-provider regeneration was not byte stable after positive variants'

jq '.mounts[1]="source=/redacted/local/source,target=/home/developer/.codex,type=bind,rw"' "$local_config" >"$tmp_dir/local-changed"
cp "$tmp_dir/local-changed" "$local_config"
scripts/devcontainer-generate.sh "$project" "$request" --dry-run --replace >"$tmp_dir/redacted-dry-run"
grep -Fxq 'CHANGE .cyclestone/runtime/devcontainer.json (machine-local content redacted)' "$tmp_dir/redacted-dry-run" || fail 'changed local output did not use the redacted preview'
if grep -Fq -e '/redacted/local/source' -e "$tmp_dir" "$tmp_dir/redacted-dry-run"; then fail 'local dry-run preview disclosed a source path'; fi
cp "$tmp_dir/local-first" "$local_config"

cp "$portable" "$tmp_dir/sentinel-portable"
cp "$local_config" "$tmp_dir/sentinel-local"
portable_mode=$(stat -c %a "$portable")
local_mode=$(stat -c %a "$local_config")
assert_outputs_unchanged() {
  context=$1
  cmp -s "$tmp_dir/sentinel-portable" "$portable" && cmp -s "$tmp_dir/sentinel-local" "$local_config" \
    || fail "$context changed prior generated output bytes"
  test "$(stat -c %a "$portable")" = "$portable_mode" && test "$(stat -c %a "$local_config")" = "$local_mode" \
    || fail "$context changed prior generated output modes"
}

mkdir "$project/hostile"
jq '.providers.codex.mount="/etc"' "$request" >"$project/hostile/raw-mount.json"
jq '.providers.claude.environment={EVIL:"value"}' "$request" >"$project/hostile/environment-value.json"
jq '.providers.codex.source="/etc"' "$request" >"$project/hostile/source.json"
jq '.providers.codex.destination="/workspace"' "$request" >"$project/hostile/destination.json"
jq '.providers.claude.environmentName="EVIL"' "$request" >"$project/hostile/environment-name.json"
jq '.providers.ollama.service="engine-socket"' "$request" >"$project/hostile/service.json"
jq '.providers.ollama.endpoint="http://host.invalid"' "$request" >"$project/hostile/endpoint.json"
jq '.runArgs=["--privileged"]' "$request" >"$project/hostile/run-args.json"
jq '.features={"evil":{}}' "$request" >"$project/hostile/feature.json"
jq '.customizations={evil:{}}' "$request" >"$project/hostile/customizations.json"
jq '.postCreateCommand="hostile"' "$request" >"$project/hostile/lifecycle.json"
jq '.raw={mounts:["source=/etc,target=/workspace,type=bind"]}' "$request" >"$project/hostile/raw-json.json"
printf '%s\n' '{"version":1,"providers":{"codex":{"enabled":true,"mode":"read-write","unknown":true}}}' >"$project/hostile/unknown-field.json"
printf '%s\n' '{"version":1,"providers":{"codex":{"enabled":true,"mode":"read-write"},"codex":{"enabled":true,"mode":"read-only"}}}' >"$project/hostile/duplicate.json"
for hostile in "$project"/hostile/*.json; do
  case "$hostile" in */duplicate.json) code=E_REQUEST_JSON;; *) code=E_REQUEST_SCHEMA;; esac
  expect_error "$code" scripts/devcontainer-generate.sh "$project" "$hostile" --replace
  assert_outputs_unchanged "hostile request $(basename "$hostile")"
done

expect_error E_CONFLICT sh -c '
  repo_root=$1
  . "$repo_root/scripts/runtime-config-lib.sh"
  plans='"'"'[{"environment_names":["DUPLICATE"],"mount":null},{"environment_names":["DUPLICATE"],"mount":null}]'"'"'
  runtime_check_conflicts
' sh "$repo_root"
expect_error E_CONFLICT sh -c '
  repo_root=$1
  . "$repo_root/scripts/runtime-config-lib.sh"
  plans='"'"'[{"environment_names":[],"mount":{"destination":"/same"}},{"environment_names":[],"mount":{"destination":"/same"}}]'"'"'
  runtime_check_conflicts
' sh "$repo_root"
expect_error E_RUNTIME_PLAN sh -c '
  repo_root=$1
  project_root=$2
  request_file=$3
  provider_id=codex
  . "$repo_root/scripts/runtime-config-lib.sh"
  runtime_config_init
  authorization=$($permissions authorize "$project_root" "$request_file" "$provider_id" linux)
  authorized_plan=$(printf "%s" "$authorization" | jq -S -c .plan)
  runtime=$($credentials prepare "$project_root" "$request_file" "$provider_id" linux | jq -S -c ".mount.source=\"/etc\"")
  runtime_validate_runtime_plan
' sh "$repo_root" "$project" "$request"

saved_anthropic=$ANTHROPIC_API_KEY
unset ANTHROPIC_API_KEY
expect_error E_PREREQUISITE scripts/devcontainer-generate.sh "$project" "$request"
export ANTHROPIC_API_KEY=$saved_anthropic
assert_outputs_unchanged 'missing environment prerequisite'
saved_gemini=$GEMINI_API_KEY
unset GEMINI_API_KEY
expect_error E_PREREQUISITE scripts/devcontainer-generate.sh "$project" "$request"
export GEMINI_API_KEY=$saved_gemini
assert_outputs_unchanged 'missing agy environment prerequisite'
saved_ollama=$OLLAMA_HOST
unset OLLAMA_HOST
expect_error E_PREREQUISITE scripts/devcontainer-validate.sh "$project" "$request"
export OLLAMA_HOST=$saved_ollama
assert_outputs_unchanged 'missing host-service prerequisite'

mv "$HOME/.codex/auth.json" "$HOME/.codex/auth.json.held"
expect_error E_PREREQUISITE scripts/devcontainer-generate.sh "$project" "$request"
mv "$HOME/.codex/auth.json.held" "$HOME/.codex/auth.json"
assert_outputs_unchanged 'missing credential source'
mv "$HOME/.codex/auth.json" "$HOME/.codex/auth.json.held"
ln -s "$HOME/.codex/auth.json.held" "$HOME/.codex/auth.json"
expect_error E_PREREQUISITE scripts/devcontainer-generate.sh "$project" "$request"
rm "$HOME/.codex/auth.json"
mv "$HOME/.codex/auth.json.held" "$HOME/.codex/auth.json"
assert_outputs_unchanged 'credential source symlink'

mkdir "$tmp_dir/wrong-cli"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" 0.85.0' >"$tmp_dir/wrong-cli/devcontainer"
chmod +x "$tmp_dir/wrong-cli/devcontainer"
expect_error E_CLI_VERSION env PATH="$tmp_dir/wrong-cli:$PATH" scripts/devcontainer-validate.sh "$project" "$request"
expect_error E_TOOL_MISSING env PATH=/usr/sbin:/usr/bin:/bin scripts/devcontainer-validate.sh "$project" "$request"
assert_outputs_unchanged 'CLI prerequisite failures'

ready_fifo=$tmp_dir/source-ready.fifo
continue_fifo=$tmp_dir/source-continue.fifo
mkfifo "$ready_fifo" "$continue_fifo"
CYCLESTONE_RUNTIME_CONFIG_TEST_FAULT=source-swap \
CYCLESTONE_RUNTIME_CONFIG_TEST_READY_FIFO=$ready_fifo \
CYCLESTONE_RUNTIME_CONFIG_TEST_CONTINUE_FIFO=$continue_fifo \
  scripts/devcontainer-generate.sh "$project" "$request" >"$tmp_dir/source-swap.stdout" 2>"$tmp_dir/source-swap.stderr" &
source_swap_pid=$!
IFS= read -r ready <"$ready_fifo"
test "$ready" = ready || fail 'source-swap hook did not become ready'
swap_source=$(jq -r '.mounts[]|select(contains("target=/home/developer/.codex,"))|sub("^source=";"")|split(",target=")[0]' "$local_config")
mv "$swap_source" "$swap_source.held"
mkdir "$swap_source"
chmod 700 "$swap_source"
printf '%s\n' continue >"$continue_fifo"
if wait "$source_swap_pid"; then fail 'source substitution unexpectedly passed generation'; fi
grep -Fq 'ERROR E_SOURCE_CHANGED:' "$tmp_dir/source-swap.stderr" || fail 'source substitution lacked E_SOURCE_CHANGED diagnostic'
rmdir "$swap_source"
mv "$swap_source.held" "$swap_source"
assert_outputs_unchanged 'source substitution'

for stage in after-validation after-render before-source-recheck before-stage before-write after-portable-stage after-local-stage after-file-fsync before-first-rename after-first-rename after-second-rename after-directory-fsync; do
  expect_error E_WRITE env CYCLESTONE_RUNTIME_CONFIG_TEST_FAULT="$stage" scripts/devcontainer-generate.sh "$project" "$request"
  assert_outputs_unchanged "injected $stage failure"
done

grant_id=$(scripts/devcontainer-permissions.sh list | jq -r '.grants[]|select(.request.provider_id=="claude")|.id')
scripts/devcontainer-permissions.sh revoke "$grant_id"
expect_error E_PERMISSION scripts/devcontainer-generate.sh "$project" "$request"
assert_outputs_unchanged 'missing grant'

disabled_request=$project/disabled.json
scripts/devcontainer-generate.sh "$project" "$disabled_request" --safe-mode --replace >"$tmp_dir/safe-gen"
jq -e '.customizations.cyclestone.generatedRuntimeConfiguration.safeMode==true and (has("postCreateCommand")|not)' "$portable" >/dev/null || fail 'safe mode did not omit postCreateCommand or set safeMode flag'
scripts/devcontainer-validate.sh "$project" "$disabled_request" --safe-mode >"$tmp_dir/safe-val"

expect_error E_SAFE_MODE_DENIED scripts/devcontainer-generate.sh "$project" "$request" --safe-mode --replace
expect_error E_SAFE_MODE_DENIED env SAFE_MODE=true scripts/devcontainer-permissions.sh authorize "$project" "$request" claude linux

if grep -F -e 'runtime-config-secret-canary' -e 'runtime-config-proxy-canary' -e 'runtime-config-codex-canary' -e 'runtime-config-opencode-canary' -e 'runtime-config-agy-canary' -e "$tmp_dir" "$tmp_dir/dry-run" "$tmp_dir/redacted-dry-run" "$tmp_dir/diagnostics.log" "$tmp_dir/generated" "$tmp_dir/validated" "$tmp_dir/safe-gen" "$tmp_dir/safe-val" >/dev/null; then
  fail 'dry-run or diagnostic output disclosed a secret, secret-derived value, or absolute local path'
fi

printf '%s\n' 'PASS: runtime configuration generation, validation, ordering, idempotence, provenance, dry-run, atomic failure, access intersection, safe-mode, and hostile input rejection'

