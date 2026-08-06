#!/bin/sh
set -eu
repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd); cd "$repo_root"
permissions=./scripts/devcontainer-permissions.sh; credentials=./scripts/provider-credentials.sh
engine_home=$HOME
tmp_dir=$(mktemp -d); trap 'for cid in $(env HOME="$engine_home" podman ps -aq --filter name=cyclestone-credential- 2>/dev/null); do env HOME="$engine_home" podman rm -f -t 0 "$cid" >/dev/null 2>&1 || :; done; rm -rf -- "$tmp_dir"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for tool in jq git socat podman realpath stat sha256sum base64; do command -v "$tool" >/dev/null 2>&1 || fail "missing required host tool: $tool"; done
if test "${PROVIDER_CREDENTIALS_STATIC_ONLY:-0}" != 1; then
  test "$(id -u)" -ne 0 || fail 'credential integration must run as a non-root account'
  test "$(env HOME="$engine_home" podman info --format '{{.Host.Security.Rootless}}')" = true || fail 'credential integration requires rootless Podman'
fi

export HOME=$tmp_dir/home CYCLESTONE_DATA_DIR=$tmp_dir/data CYCLESTONE_ENGINE_HOME=$engine_home
mkdir -p "$HOME/.codex" "$HOME/.local/share/opencode" "$tmp_dir/projects"
chmod 700 "$HOME" "$HOME/.codex" "$HOME/.local" "$HOME/.local/share" "$HOME/.local/share/opencode"
seed=$(printf '%s' "$tmp_dir:$$" | sha256sum | awk '{print $1}')
codex_canary=codex_${seed}_line1
claude_canary=$(printf 'claude_%s_line1\nline2_%s_%%3D_shell!value' "$seed" "$seed")
proxy_canary=http://user:${seed}@proxy.invalid:8080
no_proxy_canary=.invalid-$seed,127.0.0.1
ollama_canary=http://host.containers.internal:11434/$seed
agy_canary=$(printf 'agy_%s_line1\nline2_%s_%%3D_shell!value' "$seed" "$seed")
opencode_canary=$(printf 'opencode_%s' "$seed" | base64 | tr -d '\n')
jq -n --arg value "$codex_canary" '{tokens:{access_token:$value}}' >"$HOME/.codex/auth.json"
jq -n --arg value "$opencode_canary" '{openai:{type:"api",key:$value}}' >"$HOME/.local/share/opencode/auth.json"
chmod 600 "$HOME/.codex/auth.json" "$HOME/.local/share/opencode/auth.json"
printf '%s\n' adjacent >"$HOME/.codex/config.toml"; printf '%s\n' adjacent >"$HOME/.local/share/opencode/session.db"
adjacent_codex_hash=$(sha256sum "$HOME/.codex/config.toml" | awk '{print $1}'); adjacent_opencode_hash=$(sha256sum "$HOME/.local/share/opencode/session.db" | awk '{print $1}')
export ANTHROPIC_API_KEY=$claude_canary HTTPS_PROXY=$proxy_canary HTTP_PROXY=$proxy_canary NO_PROXY=$no_proxy_canary OLLAMA_HOST=$ollama_canary GEMINI_API_KEY=$agy_canary

project=$tmp_dir/projects/project; git init -q "$project"; git -C "$project" config user.name 'Credential Fixture'; git -C "$project" config user.email fixture.invalid
cp tests/fixtures/providers/valid/all.json "$project/providers.json"; cp tests/fixtures/providers/valid/read-only.json "$project/providers-read-only.json"
git -C "$project" add .; git -C "$project" commit -qm initial; request=$project/providers.json; ro_request=$project/providers-read-only.json
review() { provider=$1; file=${2:-$request}; output=$tmp_dir/review-$provider-$(basename "$file"); { sleep 1; printf '%s\n' always; } | socat -,ignoreeof EXEC:"$permissions review $project $file $provider linux",pty,setsid,ctty >"$output" 2>&1 || :; grep -Fq '"authorized":true' "$output" || fail "approval failed for $provider"; }
for provider in agy claude codex generic-environment ollama opencode; do review "$provider"; done; review codex "$ro_request"

expect_error() { code=$1; shift; if "$@" >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"; then fail "expected $code"; fi; grep -Fq "ERROR $code:" "$tmp_dir/stderr" || fail "missing stable error $code"; test ! -s "$tmp_dir/stdout" || fail "$code emitted runtime material"; }
safe_capture() { name=$1; shift; "$@" >"$tmp_dir/$name.out" 2>"$tmp_dir/$name.err" || { sed -n '1,20p' "$tmp_dir/$name.err" >&2; fail "$name failed"; }; }
scan_retained_value() {
  value=$1; : >"$tmp_dir/secret-files"
  find "$tmp_dir" "$repo_root" -type f ! -path "$tmp_dir/image.tar" ! -path "$tmp_dir/secret-files" -print >"$tmp_dir/scan-candidates"
  while IFS= read -r candidate; do
    grep -Fxq -- "$candidate" "$tmp_dir/credential-scan-exemptions" && continue
    if grep -a -F -q -- "$value" "$candidate" 2>/dev/null; then printf '%s\n' "$candidate" >>"$tmp_dir/secret-files"; fi
  done <"$tmp_dir/scan-candidates"
  test -s "$tmp_dir/secret-files"
}

# Environment and service plans carry exact names and metadata, never values.
safe_capture agy-plan "$credentials" prepare "$project" "$request" agy linux
jq -e '.environment_names==["GEMINI_API_KEY"] and .mount==null' "$tmp_dir/agy-plan.out" >/dev/null || fail 'Agy runtime plan drifted'
safe_capture claude-plan "$credentials" prepare "$project" "$request" claude linux
jq -e '.environment_names==["ANTHROPIC_API_KEY"] and .mount==null' "$tmp_dir/claude-plan.out" >/dev/null || fail 'Claude runtime plan drifted'
safe_capture generic-plan "$credentials" prepare "$project" "$request" generic-environment linux
jq -e '.environment_names==["HTTPS_PROXY","HTTP_PROXY","NO_PROXY"] and .mount==null' "$tmp_dir/generic-plan.out" >/dev/null || fail 'generic environment plan drifted'

# Start a mock host service listener on the default Ollama port before any
# positive ollama plan call: the production prepare path probes reachability,
# so the listener must exist before the plan assertions below and before the
# runtime section. The negative reachability test uses a separate port (59999)
# and the non-loopback warning test skips the probe, so neither is affected.
socat TCP-LISTEN:11434,fork,reuseaddr EXEC:cat >/dev/null 2>&1 &
mock_ollama_pid=$!

safe_capture ollama-plan "$credentials" prepare "$project" "$request" ollama linux
unset ANTHROPIC_API_KEY; expect_error E_ENV_MISSING "$credentials" prepare "$project" "$request" claude linux; export ANTHROPIC_API_KEY=$claude_canary
unset GEMINI_API_KEY; expect_error E_ENV_MISSING "$credentials" prepare "$project" "$request" agy linux; export GEMINI_API_KEY=$agy_canary

# Host-service port allowlisting, reachability, non-loopback warnings, and socket/model mount guards
export OLLAMA_HOST=http://host.containers.internal:80
expect_error E_PORT_DISALLOWED "$credentials" prepare "$project" "$request" ollama linux
export OLLAMA_HOST=http://host.containers.internal:70000
expect_error E_PORT_DISALLOWED "$credentials" prepare "$project" "$request" ollama linux

export OLLAMA_HOST=http://127.0.0.1:59999
expect_error E_HOST_SERVICE_UNREACHABLE "$credentials" prepare "$project" "$request" ollama linux

export OLLAMA_HOST=http://192.168.1.200:11434
CYCLESTONE_SKIP_HOST_SERVICE_PROBE=1 "$credentials" prepare "$project" "$request" ollama linux >"$tmp_dir/warn.out" 2>"$tmp_dir/warn.err" || fail 'non-loopback warning prepare failed'
grep -Fq 'WARNING: Non-loopback HTTP host-service endpoint' "$tmp_dir/warn.err" || fail 'missing non-loopback HTTP security warning'

export OLLAMA_HOST=$ollama_canary

# First import is atomic and exact. Both writable providers reject missing files,
# unsafe modes, links, non-regular files, changed formats, and failures at every
# real pre-publication boundary without leaving a usable store.
codex_source=$HOME/.codex/auth.json; opencode_source=$HOME/.local/share/opencode/auth.json
exercise_import_rejections() {
  provider=$1; source=$2; invalid=$3
  mv "$source" "$source.saved"; expect_error E_CREDENTIAL_MISSING "$credentials" prepare "$project" "$request" "$provider" linux; mv "$source.saved" "$source"
  chmod 640 "$source"; expect_error E_CREDENTIAL_PERMISSIONS "$credentials" prepare "$project" "$request" "$provider" linux; chmod 600 "$source"
  cp "$source" "$source.saved"; printf '%s\n' "$invalid" >"$source"; chmod 600 "$source"
  expect_error E_CREDENTIAL_FORMAT "$credentials" prepare "$project" "$request" "$provider" linux; mv "$source.saved" "$source"; chmod 600 "$source"
  mv "$source" "$source.real"; mkfifo "$source"; expect_error E_IMPORT_UNSAFE "$credentials" prepare "$project" "$request" "$provider" linux
  rm "$source"; ln -s "$source.real" "$source"; expect_error E_IMPORT_UNSAFE "$credentials" prepare "$project" "$request" "$provider" linux
  rm "$source"; mv "$source.real" "$source"; chmod 600 "$source"
  for point in import-after-copy import-after-file-fsync import-after-fsync import-before-rename; do
    expect_error E_STATE_WRITE env CYCLESTONE_CREDENTIAL_TESTING=1 CYCLESTONE_CREDENTIAL_FAULT=$point "$credentials" prepare "$project" "$request" "$provider" linux
    test "$($credentials list | jq --arg provider "$provider" '[.states[]|select(.provider_id==$provider and .mode=="read-write")]|length')" -eq 0 || fail "failed $provider import published usable state at $point"
    test -z "$(find "$CYCLESTONE_DATA_DIR/provider-credentials-v1" -maxdepth 1 -name '.import.*' -print -quit)" || fail "failed $provider import retained staging state at $point"
  done
}
exercise_import_rejections codex "$codex_source" '{}'
exercise_import_rejections opencode "$opencode_source" '[]'
test "$($credentials list | jq '[.states[]|select(.provider_id=="codex" or .provider_id=="opencode")]|length')" -eq 0 || fail 'failed first imports left usable credential state'
safe_capture codex-rw-plan "$credentials" prepare "$project" "$request" codex linux
safe_capture opencode-plan "$credentials" prepare "$project" "$request" opencode linux
codex_mount=$(jq -r .mount.source "$tmp_dir/codex-rw-plan.out")/auth.json; opencode_mount=$(jq -r .mount.source "$tmp_dir/opencode-plan.out")/auth.json
test "$(stat -c %a "$(dirname "$codex_mount")")" = 700 && test "$(stat -c %a "$codex_mount")" = 600 || fail 'Codex isolated permissions are not restrictive'
test "$(stat -c %a "$(dirname "$opencode_mount")")" = 700 && test "$(stat -c %a "$opencode_mount")" = 600 || fail 'OpenCode isolated permissions are not restrictive'
test "$(stat -c %u "$codex_mount")" = "$(id -u)" && test "$(stat -c %u "$opencode_mount")" = "$(id -u)" || fail 'isolated credentials are not owned by the invoking user'
cmp -s "$HOME/.codex/auth.json" "$codex_mount" || fail 'Codex import changed credential bytes'; cmp -s "$opencode_source" "$opencode_mount" || fail 'OpenCode import changed credential bytes'
safe_capture codex-ro-plan "$credentials" prepare "$project" "$ro_request" codex linux
jq -e --arg source "$HOME/.codex/auth.json" '.strategy=="direct-file-mount" and .mount.source==$source and .mount.access=="read-only"' "$tmp_dir/codex-ro-plan.out" >/dev/null || fail 'Codex read-only mount is not the exact host auth file'
expect_error E_SYNC_FORBIDDEN "$credentials" synchronize "$project" "$ro_request" codex linux

# Retained output, grant records, and metadata remain value-free. Exemptions are
# exact current source/store files, never every file named auth.json.
printf '%s\n' "$codex_source" "$opencode_source" "$codex_mount" "$opencode_mount" >"$tmp_dir/credential-scan-exemptions"
for value in "$codex_canary" "$claude_canary" "$agy_canary" "$proxy_canary" "$opencode_canary"; do
  if scan_retained_value "$value"; then fail "a credential value reached retained non-credential output: $(basename "$(sed -n '1p' "$tmp_dir/secret-files")")"; fi
done
scan_negative=non_exempt_auth_${seed}; mkdir -p "$tmp_dir/negative-control"; printf '%s\n' "$scan_negative" >"$tmp_dir/negative-control/auth.json"
scan_retained_value "$scan_negative" || fail 'secret scanner missed a non-exempt auth.json negative control'
rm -f "$tmp_dir/negative-control/auth.json"

if test "${PROVIDER_CREDENTIALS_STATIC_ONLY:-0}" = 1; then printf '%s\n' 'PASS: provider credential adapters, imports, plans, redaction, and failures are enforced (runtime skipped)'; exit 0; fi
image=${CREDENTIAL_TEST_IMAGE:-}
if test -z "$image"; then image=$(env HOME="$engine_home" podman images --format '{{.Repository}}:{{.Tag}}' | grep -m1 '^localhost/cyclestone-base:' || :); fi
test -n "$image" || fail 'set CREDENTIAL_TEST_IMAGE to a locally verified Cyclestone base image'

start() { provider=$1; file=${2:-$request}; safe_capture start-$provider "$credentials" start "$project" "$file" "$provider" linux "$image"; jq -r .session_id "$tmp_dir/start-$provider.out"; }
stop() { "$credentials" stop "$1" >/dev/null; }
grant_for() { provider=$1; mode=$2; $permissions list | jq -r --arg provider "$provider" --arg mode "$mode" '.grants[]|select(.request.provider_id==$provider and .request.mode==$mode)|.id'; }
active_revoke_fails() { provider=$1; mode=$2; expect_error E_ACTIVE_SESSION "$permissions" revoke "$(grant_for "$provider" "$mode")"; }
hash_value() { printf %s "$1" | sha256sum | awk '{print $1}'; }
assert_sync_failures_preserve_source() {
  provider=$1; source=$2; source_dir=$(dirname "$source"); before=$(sha256sum "$source" | awk '{print $1}')
  for point in sync-after-copy sync-after-fsync sync-before-rename; do
    expect_error E_SYNC_WRITE env CYCLESTONE_CREDENTIAL_TESTING=1 CYCLESTONE_CREDENTIAL_FAULT=$point "$credentials" synchronize "$project" "$request" "$provider" linux
    test "$(sha256sum "$source" | awk '{print $1}')" = "$before" || fail "failed $provider synchronization replaced the prior host file at $point"
    test -z "$(find "$source_dir" -maxdepth 1 -name '.auth.json.*' -print -quit)" || fail "failed $provider synchronization retained a temporary file at $point"
  done
  chmod 500 "$source_dir"
  expect_error E_SYNC_WRITE "$credentials" synchronize "$project" "$request" "$provider" linux
  chmod 700 "$source_dir"
  test "$(sha256sum "$source" | awk '{print $1}')" = "$before" || fail "permission-denied $provider synchronization replaced the prior host file"
}

# Runtime environment values are inherited by exact name. Recreating each
# session observes refreshed multiline, shell-significant, URL-like, and
# encoded-looking values without serializing them into runtime plans.
agy_first=$(start agy); observed=$($credentials exec "$agy_first" sh -c 'printf %s "$GEMINI_API_KEY" | sha256sum' | awk '{print $1}'); test "$observed" = "$(hash_value "$agy_canary")" || fail 'Agy runtime environment was not forwarded'; stop "$agy_first"
agy_refresh=$(printf 'refresh_%s\n$()!%%0A_%s' "$seed" "$seed"); export GEMINI_API_KEY=$agy_refresh
agy_second=$(start agy); test "$agy_second" != "$agy_first" || fail 'Agy recreation reused a session'; observed=$($credentials exec "$agy_second" sh -c 'printf %s "$GEMINI_API_KEY" | sha256sum' | awk '{print $1}'); test "$observed" = "$(hash_value "$agy_refresh")" || fail 'Agy recreation did not refresh the runtime value'; active_revoke_fails agy environment; stop "$agy_second"
export GEMINI_API_KEY=$agy_canary

claude_first=$(start claude); observed=$($credentials exec "$claude_first" sh -c 'printf %s "$ANTHROPIC_API_KEY" | sha256sum' | awk '{print $1}'); test "$observed" = "$(hash_value "$claude_canary")" || fail 'Claude runtime environment was not forwarded'; stop "$claude_first"
claude_refresh=$(printf 'refresh_%s\n$()!%%0A_%s' "$seed" "$seed"); export ANTHROPIC_API_KEY=$claude_refresh
claude_second=$(start claude); test "$claude_second" != "$claude_first" || fail 'Claude recreation reused a session'; observed=$($credentials exec "$claude_second" sh -c 'printf %s "$ANTHROPIC_API_KEY" | sha256sum' | awk '{print $1}'); test "$observed" = "$(hash_value "$claude_refresh")" || fail 'Claude recreation did not refresh the runtime value'; active_revoke_fails claude environment; stop "$claude_second"

generic_first=$(start generic-environment)
for tuple in "HTTPS_PROXY:$proxy_canary" "HTTP_PROXY:$proxy_canary" "NO_PROXY:$no_proxy_canary"; do name=${tuple%%:*}; value=${tuple#*:}; observed=$($credentials exec "$generic_first" sh -c "printf %s \"\$$name\" | sha256sum" | awk '{print $1}'); test "$observed" = "$(hash_value "$value")" || fail "generic environment omitted $name"; done
stop "$generic_first"
https_refresh=https://user:${seed}@refresh.invalid/a?encoded=%2F; http_refresh=$(printf 'http://u:%s@proxy.invalid/\npath-%s' "$seed" "$seed"); no_proxy_refresh=*.$seed.invalid,'$(literal)',127.0.0.1
export HTTPS_PROXY=$https_refresh HTTP_PROXY=$http_refresh NO_PROXY=$no_proxy_refresh
generic_second=$(start generic-environment); test "$generic_second" != "$generic_first" || fail 'generic recreation reused a session'
for tuple in "HTTPS_PROXY:$https_refresh" "HTTP_PROXY:$http_refresh" "NO_PROXY:$no_proxy_refresh"; do name=${tuple%%:*}; value=${tuple#*:}; observed=$($credentials exec "$generic_second" sh -c "printf %s \"\$$name\" | sha256sum" | awk '{print $1}'); test "$observed" = "$(hash_value "$value")" || fail "generic refresh omitted $name"; done
active_revoke_fails generic-environment environment; stop "$generic_second"

ollama_first=$(start ollama); observed=$($credentials exec "$ollama_first" sh -c 'printf %s "$OLLAMA_HOST" | sha256sum' | awk '{print $1}'); test "$observed" = "$(hash_value "$ollama_canary")" || fail 'Ollama endpoint was not forwarded'; stop "$ollama_first"
ollama_refresh=http://host.containers.internal:11434/api/$seed/%32; export OLLAMA_HOST=$ollama_refresh
ollama_second=$(start ollama); test "$ollama_second" != "$ollama_first" || fail 'Ollama recreation reused a session'; observed=$($credentials exec "$ollama_second" sh -c 'printf %s "$OLLAMA_HOST" | sha256sum' | awk '{print $1}'); test "$observed" = "$(hash_value "$ollama_refresh")" || fail 'Ollama recreation did not refresh the endpoint'; active_revoke_fails ollama host-service; stop "$ollama_second"

# The direct mount exposes only auth.json, rejects mutation, observes a host
# refresh only after recreation, and never grants the sibling auth directory.
ro_first=$(start codex "$ro_request"); $credentials exec "$ro_first" sh -c 'test -r /home/developer/.codex/auth.json && test ! -e /home/developer/.codex/config.toml'
if $credentials exec "$ro_first" sh -c 'printf x >>/home/developer/.codex/auth.json' >"$tmp_dir/ro-write.out" 2>"$tmp_dir/ro-write.err"; then fail 'read-only Codex credential accepted a write'; fi
stop "$ro_first"
codex_ro_refresh=codex_ro_${seed}_refresh; jq -n --arg value "$codex_ro_refresh" '{tokens:{access_token:$value}}' >"$codex_source"; chmod 600 "$codex_source"
ro_second=$(start codex "$ro_request"); test "$ro_second" != "$ro_first" || fail 'Codex read-only recreation reused a session'; observed=$($credentials exec "$ro_second" sh -c 'jq -r .tokens.access_token /home/developer/.codex/auth.json | sha256sum' | awk '{print $1}'); test "$observed" = "$(printf '%s\n' "$codex_ro_refresh" | sha256sum | awk '{print $1}')" || fail 'Codex read-only recreation missed host refresh'; active_revoke_fails codex read-only; stop "$ro_second"

# Writable sessions modify only isolated files. Extra siblings fail sync and adjacent host files remain unchanged.
rw_first=$(start codex); $credentials exec "$rw_first" sh -c 'sed "s/access_token/refreshed_token/" /home/developer/.codex/auth.json >/tmp/auth && mv /tmp/auth /home/developer/.codex/auth.json && chmod 600 /home/developer/.codex/auth.json'
$credentials exec "$rw_first" sh -c 'printf container-only >/home/developer/.codex/../codex-sibling-probe'
$credentials exec "$rw_first" sh -c 'printf hostile >/home/developer/.codex/extra.json'; stop "$rw_first"
expect_error E_SYNC_INVALID "$credentials" synchronize "$project" "$request" codex linux
test "$(sha256sum "$HOME/.codex/config.toml" | awk '{print $1}')" = "$adjacent_codex_hash" || fail 'Codex adjacent host state was corrupted'
test ! -e "$HOME/codex-sibling-probe" || fail 'Codex traversal reached host state outside the isolated mount'
rm "$(dirname "$codex_mount")/extra.json"
ln -s "$codex_source" "$(dirname "$codex_mount")/extra-link"; expect_error E_SYNC_INVALID "$credentials" synchronize "$project" "$request" codex linux; rm "$(dirname "$codex_mount")/extra-link"
assert_sync_failures_preserve_source codex "$codex_source"
safe_capture codex-sync "$credentials" synchronize "$project" "$request" codex linux
jq -e '.tokens.refreshed_token' "$HOME/.codex/auth.json" >/dev/null || fail 'Codex atomic synchronization did not update the approved host file'
rw_second=$(start codex); test "$rw_second" != "$rw_first" || fail 'Codex writable recreation reused a session'; $credentials exec "$rw_second" jq -e .tokens.refreshed_token /home/developer/.codex/auth.json >/dev/null; active_revoke_fails codex read-write; stop "$rw_second"

opencode_first=$(start opencode); $credentials exec "$opencode_first" sh -c 'sed "s/\"api\"/\"api-refreshed\"/" /home/developer/.local/share/opencode/auth.json >/tmp/auth && mv /tmp/auth /home/developer/.local/share/opencode/auth.json && chmod 600 /home/developer/.local/share/opencode/auth.json'; $credentials exec "$opencode_first" sh -c 'printf container-only >/home/developer/.local/share/opencode/../opencode-sibling-probe'; $credentials exec "$opencode_first" sh -c 'printf hostile >/home/developer/.local/share/opencode/extra.json'; stop "$opencode_first"
expect_error E_SYNC_INVALID "$credentials" synchronize "$project" "$request" opencode linux
test "$(sha256sum "$HOME/.local/share/opencode/session.db" | awk '{print $1}')" = "$adjacent_opencode_hash" || fail 'hostile OpenCode output corrupted adjacent host state'
test ! -e "$HOME/.local/share/opencode-sibling-probe" || fail 'OpenCode traversal reached host state outside the isolated mount'
rm "$(dirname "$opencode_mount")/extra.json"
mkfifo "$(dirname "$opencode_mount")/extra-fifo"; expect_error E_SYNC_INVALID "$credentials" synchronize "$project" "$request" opencode linux; rm "$(dirname "$opencode_mount")/extra-fifo"
assert_sync_failures_preserve_source opencode "$opencode_source"
safe_capture opencode-sync "$credentials" synchronize "$project" "$request" opencode linux
test "$(sha256sum "$HOME/.local/share/opencode/session.db" | awk '{print $1}')" = "$adjacent_opencode_hash" || fail 'OpenCode adjacent host state was corrupted'
opencode_second=$(start opencode); test "$opencode_second" != "$opencode_first" || fail 'OpenCode recreation reused a session'; $credentials exec "$opencode_second" jq -e '.openai.type=="api-refreshed"' /home/developer/.local/share/opencode/auth.json >/dev/null; active_revoke_fails opencode read-write; stop "$opencode_second"

# Project-wide revocation removes all adapters after every provider has proved
# active-session refusal. Every later prepare is denied before runtime access.
$permissions revoke-project "$project"
test "$($credentials list | jq '.states|length')" -eq 0 || fail 'project revocation retained credential state'
for provider in agy claude codex generic-environment ollama opencode; do expect_error E_APPROVAL_REQUIRED "$credentials" prepare "$project" "$request" "$provider" linux; done
expect_error E_APPROVAL_REQUIRED "$credentials" prepare "$project" "$ro_request" codex linux

# Recreated stores reject metadata redirection and source replacement for both
# writable providers without touching approved isolated bytes or adjacent files.
review codex; review opencode
safe_capture codex-reimport "$credentials" prepare "$project" "$request" codex linux
safe_capture opencode-reimport "$credentials" prepare "$project" "$request" opencode linux
codex_reimport_mount=$(jq -r .mount.source "$tmp_dir/codex-reimport.out")/auth.json
opencode_reimport_mount=$(jq -r .mount.source "$tmp_dir/opencode-reimport.out")/auth.json
printf '%s\n' "$codex_reimport_mount" "$opencode_reimport_mount" >>"$tmp_dir/credential-scan-exemptions"
for tuple in "codex:$codex_reimport_mount" "opencode:$opencode_reimport_mount"; do
  provider=${tuple%%:*}; mount=${tuple#*:}; metadata=$(dirname "$(dirname "$mount")")/metadata.json
  cp "$metadata" "$metadata.valid"; isolated_before=$(sha256sum "$mount" | awk '{print $1}')
  jq '.store_file="/tmp/unreviewed-auth.json"' "$metadata.valid" >"$metadata"; chmod 600 "$metadata"
  expect_error E_STATE_INTEGRITY "$credentials" prepare "$project" "$request" "$provider" linux
  test "$(sha256sum "$mount" | awk '{print $1}')" = "$isolated_before" || fail "$provider metadata substitution changed isolated bytes"
  mv "$metadata.valid" "$metadata"; chmod 600 "$metadata"
done
for tuple in "codex:$codex_source" "opencode:$opencode_source"; do
  provider=${tuple%%:*}; source=${tuple#*:}; cp "$source" "$source.replacement"; chmod 600 "$source.replacement"; mv "$source.replacement" "$source"
  expect_error E_SOURCE_CHANGED "$credentials" synchronize "$project" "$request" "$provider" linux
done
test "$(sha256sum "$HOME/.codex/config.toml" | awk '{print $1}')" = "$adjacent_codex_hash" || fail 'source substitution affected adjacent Codex state'
test "$(sha256sum "$HOME/.local/share/opencode/session.db" | awk '{print $1}')" = "$adjacent_opencode_hash" || fail 'source substitution affected adjacent OpenCode state'

# Scan retained repository/test/evidence surfaces and the image archive. Only
# the intentional ephemeral source/store auth.json files may contain canaries.
env HOME="$engine_home" podman history --no-trunc "$image" >"$tmp_dir/image-history" 2>&1
env HOME="$engine_home" podman save -o "$tmp_dir/image.tar" "$image"
git diff --binary >"$tmp_dir/repository.diff"
for value in "$codex_canary" "$codex_ro_refresh" "$claude_canary" "$claude_refresh" "$agy_canary" "$agy_refresh" "$proxy_canary" "$https_refresh" "$http_refresh" "$no_proxy_canary" "$no_proxy_refresh" "$ollama_canary" "$ollama_refresh" "$opencode_canary"; do
  if scan_retained_value "$value"; then fail "a credential value reached a retained surface: $(basename "$(sed -n '1p' "$tmp_dir/secret-files")")"; fi
  if grep -a -F -l -- "$value" "$tmp_dir/image.tar" >"$tmp_dir/secret-files" 2>/dev/null; then fail 'a credential value reached the built image archive'; fi
done

printf '%s\n' 'PASS: all provider credentials pass explicit rootless-Podman authorization, access, recreation, refresh/sync, malicious-write, revocation, post-revocation denial, and redaction checks'
