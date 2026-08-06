#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"
permissions=./scripts/devcontainer-permissions.sh
request_source=tests/fixtures/providers/valid/all.json
read_only_source=tests/fixtures/providers/valid/read-only.json
tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT HUP INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
for tool in realpath stat git jq sha256sum flock socat sync; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required host tool: $tool"
done

export HOME="$tmp_dir/home"
export CYCLESTONE_DATA_DIR="$tmp_dir/local-cyclestone"
export ANTHROPIC_API_KEY=INERT_SENTINEL_SECRET
mkdir -p "$HOME" "$tmp_dir/projects"
project=$tmp_dir/projects/project
git init -q "$project"
git -C "$project" config user.name 'Authorization Fixture'
git -C "$project" config user.email fixture.invalid
cp "$request_source" "$project/providers.json"
cp "$read_only_source" "$project/providers-read-only.json"
git -C "$project" add providers.json providers-read-only.json
git -C "$project" commit -qm initial
request=$project/providers.json
read_only_request=$project/providers-read-only.json

expect_error() {
  code=$1; shift
  if "$@" >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"; then fail "expected $code"; fi
  grep -Fq "ERROR $code:" "$tmp_dir/stderr" || fail "missing stable error $code"
  test ! -s "$tmp_dir/stdout" || fail "$code emitted authorization output"
}
run_review() {
  decision=$1; provider=$2; output=$3; review_request=${4:-$request}
  # socat supplies a controlling terminal without adding a
  # test-only bypass to the production approval boundary.
  { sleep 1; printf '%s\n' "$decision"; } | socat -,ignoreeof EXEC:"$permissions review $project $review_request $provider linux",pty,setsid,ctty >"$output" 2>&1 || :
}
prompt_snapshot() {
  provider=$1; expected=$2; snapshot_request=${3:-$request}
  run_review deny "$provider" "$tmp_dir/prompt-raw" "$snapshot_request"
  tr -d '\r' <"$tmp_dir/prompt-raw" |
    sed -n '/Cyclestone provider authorization review/,/Grant duration:/p' |
    sed -E \
      -e 's#Project identity: git-worktree .* device=[0-9]+ inode=[0-9]+#Project identity: git-worktree <PROJECT> device=<DEVICE> inode=<INODE>#' \
      -e 's#Git directory: .* device=[0-9]+ inode=[0-9]+#Git directory: <GIT_DIR> device=<DEVICE> inode=<INODE>#' \
      -e 's#Git common directory: .* device=[0-9]+ inode=[0-9]+#Git common directory: <COMMON_DIR> device=<DEVICE> inode=<INODE>#' \
      -e 's#root-set-sha256=[0-9a-f]{64}#root-set-sha256=<SHA256>#' >"$tmp_dir/prompt"
  if ! cmp -s "$expected" "$tmp_dir/prompt"; then diff -u "$expected" "$tmp_dir/prompt" >&2 || :; fail "prompt snapshot changed for $provider"; fi
}

expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$project" "$request" codex linux
expect_error E_INTERACTIVE_REQUIRED "$permissions" review "$project" "$request" codex linux </dev/null
cp "$request" "$project/untracked.json"
expect_error E_REQUEST_UNCOMMITTED "$permissions" authorize "$project" "$project/untracked.json" codex linux
ln -s "$request" "$project/request-link.json"
expect_error E_REQUEST_BOUNDARY "$permissions" authorize "$project" "$project/request-link.json" codex linux
expect_error E_REQUEST_BOUNDARY "$permissions" authorize "$project" "$tmp_dir/outside.json" codex linux

prompt_snapshot codex tests/fixtures/provider-authorization/prompt-filesystem.txt
prompt_snapshot codex tests/fixtures/provider-authorization/prompt-filesystem-read-only.txt "$read_only_request"
prompt_snapshot claude tests/fixtures/provider-authorization/prompt-environment.txt
prompt_snapshot agy tests/fixtures/provider-authorization/prompt-environment-agy.txt
prompt_snapshot ollama tests/fixtures/provider-authorization/prompt-host-service.txt
grep -Fq 'ERROR E_DENIED:' "$tmp_dir/prompt-raw" || fail 'interactive denial did not fail closed'
test "$($permissions list | jq '.grants|length')" -eq 0 || fail 'interactive denial persisted a grant'

# Read-only is a natural trusted-registry plan, not a mutated grant fixture.
# Once remains invocation-local; persistent read-only approval cannot authorize
# the read-write request and revocation affects the next exact evaluation.
run_review once codex "$tmp_dir/read-only-once" "$read_only_request"
grep -Fq '"decision":"once"' "$tmp_dir/read-only-once" || fail 'read-only allow-once did not authorize its invocation'
test "$($permissions list | jq '.grants|length')" -eq 0 || fail 'read-only allow-once was persisted'
expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$project" "$read_only_request" codex linux

run_review always codex "$tmp_dir/read-only-always" "$read_only_request"
grep -Fq '"authorized":true' "$tmp_dir/read-only-always" || fail 'persistent read-only review did not authorize'
read_only_authorized=$($permissions authorize "$project" "$read_only_request" codex linux)
printf '%s' "$read_only_authorized" | jq -e '.authorized and .decision=="always" and .plan.provider_id=="codex" and .plan.mode=="read-only" and .plan.filesystem.access=="read-only"' >/dev/null || fail 'persistent exact read-only grant did not authorize'
read_only_listing=$($permissions list)
printf '%s' "$read_only_listing" | jq -e '.grants|length==1 and .[0].request.provider_id=="codex" and .[0].request.mode=="read-only"' >/dev/null || fail 'read-only grant listing is incomplete'
cp "$CYCLESTONE_DATA_DIR/provider-permissions-v1/grants.json" "$tmp_dir/read-only-before-escalation.json"
expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$project" "$request" codex linux
cmp -s "$tmp_dir/read-only-before-escalation.json" "$CYCLESTONE_DATA_DIR/provider-permissions-v1/grants.json" || fail 'read-only-to-read-write escalation mutated the store'
read_only_grant_id=$(printf '%s' "$read_only_listing" | jq -r '.grants[0].id')
$permissions revoke "$read_only_grant_id"
expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$project" "$read_only_request" codex linux

run_review always codex "$tmp_dir/always"
grep -Fq '"authorized":true' "$tmp_dir/always" || fail 'persistent review did not authorize'
authorized=$($permissions authorize "$project" "$request" codex linux)
printf '%s' "$authorized" | jq -e '.authorized and .decision=="always" and .plan.provider_id=="codex"' >/dev/null || fail 'persistent exact grant did not authorize'
printf '\n' >>"$request"
expect_error E_REQUEST_UNCOMMITTED "$permissions" authorize "$project" "$request" codex linux
git -C "$project" checkout -q -- providers.json
git -C "$project" rm --cached -q providers.json
expect_error E_REQUEST_UNCOMMITTED "$permissions" authorize "$project" "$request" codex linux
git -C "$project" reset -q HEAD -- providers.json

store=$CYCLESTONE_DATA_DIR/provider-permissions-v1/grants.json
test "$(stat -c %a "$CYCLESTONE_DATA_DIR")" = 700 || fail 'data directory is not 0700'
test "$(stat -c %a "$(dirname "$store")")" = 700 || fail 'permission directory is not 0700'
test "$(stat -c %a "$store")" = 600 || fail 'grant store is not 0600'
jq -e . "$store" >/dev/null || fail 'grant store is corrupt'
schema_tool=$(command -v jsonschema || :)
if test -n "$schema_tool"; then "$schema_tool" -i "$store" schemas/local-provider-grants-v1.schema.json >/dev/null 2>&1 || fail 'grant store failed Draft 2020-12 schema validation'; fi
grant_schema_reject() {
  name=$1; filter=$2
  test -n "$schema_tool" || return 0
  jq "$filter" "$store" >"$tmp_dir/schema-hostile.json"
  if "$schema_tool" -i "$tmp_dir/schema-hostile.json" schemas/local-provider-grants-v1.schema.json >/dev/null 2>&1; then fail "$name passed the public grant schema"; fi
}
grant_schema_reject strategy '.grants[0].plan.credential_adapter.strategy="direct-file-mount"'
grant_schema_reject mode '.grants[0].plan.mode="read-only"'
grant_schema_reject access '.grants[0].plan.credential_adapter.access="read-only"'
grant_schema_reject environment '.grants[0].plan.environment_names=["ANTHROPIC_API_KEY"]'
grant_schema_reject adapter-environment '.grants[0].plan.credential_adapter.environment_names=["ANTHROPIC_API_KEY"]'
grant_schema_reject host-service '.grants[0].plan.host_service={"kind":"http","endpoint_environment":"OLLAMA_HOST","default_endpoint":"http://host.containers.internal:11434","transport":"tcp","authentication":"none"}'
grant_schema_reject filesystem-root '.grants[0].plan.filesystem.host_source="/"'
grant_schema_reject filesystem-home '.grants[0].plan.filesystem.host_source="${HOME}"'
grant_schema_reject filesystem-config '.grants[0].plan.filesystem.host_source="${HOME}/.config"'
grant_schema_reject provider-directory '.grants[0].plan.filesystem.host_source="${HOME}/.codex"'
grant_schema_reject podman-socket '.grants[0].plan.filesystem.host_source="${XDG_RUNTIME_DIR}/podman/podman.sock"'
grant_schema_reject directory-mode '.grants[0].plan.credential_adapter.directory_mode=null'
if grep -R -F 'INERT_SENTINEL_SECRET' "$tmp_dir" >/dev/null 2>&1; then fail 'secret sentinel reached authorization state, prompt, listing, or diagnostics'; fi

listing=$($permissions list)
printf '%s' "$listing" | jq -e '.grants as $g | ($g|length)==1 and $g[0].request.provider_id=="codex" and ($g[0].project.path|endswith("/project"))' >/dev/null || fail 'safe grant listing is incomplete'
grant_id=$(printf '%s' "$listing" | jq -r '.grants[0].id')
approved_store=$tmp_dir/approved-store.json
cp "$store" "$approved_store"

assert_store_rejected() {
  name=$1; code=$2; filter=$3
  jq -S -c "$filter" "$approved_store" >"$store"
  chmod 600 "$store"
  expect_error "$code" "$permissions" list
  cp "$approved_store" "$store"
  chmod 600 "$store"
}

# Schema-shaped records remain untrusted: canonical bodies, both fingerprints,
# and the deterministic grant ID must agree before any command uses the store.
assert_store_rejected identity-fingerprint E_STORE_INTEGRITY '.grants[0].identity_fingerprint=("0"*64)'
assert_store_rejected identity-body E_STORE_INTEGRITY '.grants[0].identity.filesystem.inode+=1'
assert_store_rejected request-fingerprint E_STORE_INTEGRITY '.grants[0].request_fingerprint=("0"*64)'
assert_store_rejected request-body E_STORE_SCHEMA '.grants[0].plan.security_guidance="altered but shape-valid"'
assert_store_rejected deterministic-id E_STORE_INTEGRITY '.grants[0].id=("0"*64)'

# Runtime loading enforces every committed shape restriction that JSON Schema
# can express, plus canonical UTC and deterministic cross-field invariants.
assert_store_rejected timestamp-shape E_STORE_SCHEMA '.grants[0].created_at="not-a-date"'
assert_store_rejected timestamp-value E_STORE_SCHEMA '.grants[0].created_at="2026-99-99T00:00:00Z"'
assert_store_rejected empty-description E_STORE_SCHEMA '.grants[0].plan.description=""'
assert_store_rejected empty-write-audit E_STORE_SCHEMA '.grants[0].plan.write_requirements=""'
assert_store_rejected empty-security-audit E_STORE_SCHEMA '.grants[0].plan.security_guidance=""'
assert_store_rejected negative-device E_STORE_SCHEMA '.grants[0].identity.filesystem.device=-1'
assert_store_rejected zero-inode E_STORE_SCHEMA '.grants[0].identity.filesystem.inode=0'
assert_store_rejected fractional-inode E_STORE_SCHEMA '.grants[0].identity.filesystem.inode=1.5'
assert_store_rejected duplicate-id E_STORE_SCHEMA '.grants += [.grants[0] | .created_at="2026-08-01T00:00:01Z"]'

# Exact equality rejects provider, capability-family, variable, service, mode,
# platform, and registry changes; none can reuse the existing filesystem grant.
for provider in agy claude generic-environment ollama opencode; do
  expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$project" "$request" "$provider" linux
done
expect_error E_MODE_UNSUPPORTED ./scripts/resolve-providers.sh tests/fixtures/providers/incompatible-mode.json opencode linux
expect_error E_PLATFORM_UNSUPPORTED "$permissions" authorize "$project" "$request" codex darwin

# Cross-wired plans are exercised through the real resolver and authorize
# command. The now-correlated grant loader rejects them before approval matching,
# and rejection must not mutate persistent state.
assert_escalation_rejected() {
  name=$1; provider=$2; filter=$3
  test_identity=$($permissions identity "$project")
  test_plan=$(./scripts/resolve-providers.sh "$request" "$provider" linux | jq -S -c "$filter")
  test_identity_hash=$(printf '%s' "$test_identity" | sha256sum | awk '{print $1}')
  test_request_hash=$(printf '%s' "$test_plan" | sha256sum | awk '{print $1}')
  test_id=$(printf '%s' "$test_identity_hash:$test_request_hash" | sha256sum | awk '{print $1}')
  jq -S -c -n --arg id "$test_id" --arg ih "$test_identity_hash" --arg rh "$test_request_hash" \
    --argjson identity "$test_identity" --argjson plan "$test_plan" \
    '{version:1,grants:[{id:$id,identity_fingerprint:$ih,request_fingerprint:$rh,identity:$identity,plan:$plan,decision:"always",created_at:"2026-08-01T00:00:00Z"}]}' >"$store"
  chmod 600 "$store"
  cp "$store" "$tmp_dir/escalation-before-$name.json"
  expect_error E_STORE_SCHEMA "$permissions" authorize "$project" "$request" "$provider" linux
  cmp -s "$tmp_dir/escalation-before-$name.json" "$store" || fail "rejected escalation mutated the store: $name"
}
assert_escalation_rejected mode codex '.mode="read-only"|.filesystem.access="read-only"|.credential_adapter.mode="read-only"|.credential_adapter.access="read-only"'
assert_escalation_rejected source codex ".filesystem.host_source=\"\${HOME}/.codex-expanded\"|.credential_adapter.source_files=[\"\${HOME}/.codex-expanded\"]"
assert_escalation_rejected destination codex '.filesystem.container_destination="/home/developer/.codex-expanded"|.credential_adapter.container_destination="/home/developer/.codex-expanded"'
assert_escalation_rejected variables claude '.environment_names=["ANTHROPIC_API_KEY","EXTRA_NAME"]|.credential_adapter.environment_names=["ANTHROPIC_API_KEY","EXTRA_NAME"]'
assert_escalation_rejected host-service ollama '.host_service.default_endpoint="http://host.invalid:11434"'
assert_escalation_rejected provider codex '.provider_id="altered-provider"'
cp "$approved_store" "$store"
chmod 600 "$store"

# Registry and platform are closed resolver/schema boundaries rather than
# grant-expandable fields: unsupported values fail before approval matching.
assert_store_rejected registry-version E_STORE_SCHEMA '.grants[0].plan.registry_version=1'
assert_store_rejected stored-platform E_STORE_SCHEMA '.grants[0].plan.platform="other"'

$permissions revoke "$grant_id"
expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$project" "$request" codex linux

run_review once codex "$tmp_dir/once"
grep -Fq '"decision":"once"' "$tmp_dir/once" || fail 'allow-once did not authorize its invocation'
test "$($permissions list | jq '.grants|length')" -eq 0 || fail 'allow-once was persisted'
expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$project" "$request" codex linux

run_review malformed codex "$tmp_dir/malformed"
grep -Fq 'ERROR E_DECISION_INVALID:' "$tmp_dir/malformed" || fail 'malformed terminal decision did not fail closed'
{ sleep 1; printf '\004'; } | socat -,ignoreeof EXEC:"$permissions review '$project' '$request' codex linux",pty,setsid,ctty >"$tmp_dir/eof" 2>&1 || :
grep -Fq 'ERROR E_DECISION_EOF:' "$tmp_dir/eof" || fail 'terminal EOF did not fail closed'
{ sleep 1; printf '\003'; } | socat -,ignoreeof EXEC:"$permissions review '$project' '$request' codex linux",pty,setsid,ctty >"$tmp_dir/signal" 2>&1 || :
test "$($permissions list | jq '.grants|length')" -eq 0 || fail 'failed decisions changed the store'

# Real topology operations prove conservative identity behavior.
run_review always codex "$tmp_dir/pre-move-approval"
grep -Fq '"authorized":true' "$tmp_dir/pre-move-approval" || fail 'pre-move approval was not stored'
original_identity=$($permissions identity "$project")
symlink=$tmp_dir/projects/project-link
ln -s "$project" "$symlink"
test "$($permissions identity "$symlink")" = "$original_identity" || fail 'project symlink did not resolve to canonical identity'
git clone -q "$project" "$tmp_dir/projects/clone"
clone_identity=$($permissions identity "$tmp_dir/projects/clone")
test "$clone_identity" != "$original_identity" || fail 'clone shared project identity'
git -C "$project" worktree add -q "$tmp_dir/projects/linked"
linked_identity=$($permissions identity "$tmp_dir/projects/linked")
test "$linked_identity" != "$original_identity" || fail 'linked worktree shared project identity'
git clone -q "$project" "$tmp_dir/projects/symlink-metadata"
mv "$tmp_dir/projects/symlink-metadata/.git" "$tmp_dir/projects/symlink-metadata-git"
ln -s "$tmp_dir/projects/symlink-metadata-git" "$tmp_dir/projects/symlink-metadata/.git"
expect_error E_PROJECT_IDENTITY "$permissions" identity "$tmp_dir/projects/symlink-metadata"
mkdir "$tmp_dir/projects/plain"
printf '%s' "$($permissions identity "$tmp_dir/projects/plain")" | jq -e '.kind=="directory"' >/dev/null || fail 'non-Git identity is not separately scoped'
mv "$project" "$tmp_dir/projects/moved"
moved_identity=$($permissions identity "$tmp_dir/projects/moved")
test "$moved_identity" != "$original_identity" || fail 'move retained project identity'
expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$tmp_dir/projects/moved" "$tmp_dir/projects/moved/providers.json" codex linux
test "$($permissions list | jq '.grants|length')" -eq 0 || fail 'observed move did not retire the prior path-scoped grant'
mv "$tmp_dir/projects/moved" "$project"
expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$project" "$request" codex linux
test "$($permissions list | jq '.grants|length')" -eq 0 || fail 'move-back revived a retired grant'
mv "$project" "$tmp_dir/projects/moved"
mkdir "$project"
replacement_identity=$($permissions identity "$project")
test "$replacement_identity" != "$original_identity" || fail 'same-path replacement retained project identity'

# Concurrent persistent approvals serialize and preserve every exact grant.
project=$tmp_dir/projects/moved; request=$project/providers.json
pids=
for provider in codex agy claude ollama opencode; do run_review always "$provider" "$tmp_dir/concurrent-$provider" & pids="$pids $!"; done
remaining=$pids
attempt=0
while test -n "$remaining" && test "$attempt" -lt 100; do
  next=
  for pid in $remaining; do kill -0 "$pid" 2>/dev/null && next="$next $pid"; done
  remaining=$next
  test -z "$remaining" || sleep 0.2
  attempt=$((attempt + 1))
done
test -z "$remaining" || fail 'parallel approvals exceeded bounded wait'
for pid in $pids; do wait "$pid" || fail 'parallel approval failed'; done
for provider in codex agy claude ollama opencode; do
  grep -Fq '"authorized":true' "$tmp_dir/concurrent-$provider" || fail "parallel approval did not authorize $provider: $(tr -d '\r' <"$tmp_dir/concurrent-$provider" | tail -1)"
done
test "$($permissions list | jq '.grants|length')" -eq 5 || fail 'parallel writers lost a grant'
jq -e . "$store" >/dev/null || fail 'parallel writers corrupted the store'

# A failed write before rename leaves the prior valid store byte-for-byte
# usable; the injected failing mktemp affects only this disposable test PATH.
cp "$store" "$tmp_dir/store-before-interruption.json"
interrupted_id=$($permissions list | jq -r '.grants[0].id')
mkdir "$tmp_dir/failing-tools"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$tmp_dir/failing-tools/mktemp"
chmod 700 "$tmp_dir/failing-tools/mktemp"
expect_error E_STORE_WRITE env PATH="$tmp_dir/failing-tools:$PATH" "$permissions" revoke "$interrupted_id"
cmp -s "$tmp_dir/store-before-interruption.json" "$store" || fail 'interrupted replacement changed the prior store'
jq -e . "$store" >/dev/null || fail 'interrupted replacement made the prior store unusable'

$permissions revoke-project "$project"
test "$($permissions list | jq '.grants|length')" -eq 0 || fail 'project revocation was not immediate'
expect_error E_APPROVAL_REQUIRED "$permissions" authorize "$project" "$request" codex linux

# Hostile precreated state fails closed instead of being followed or repaired.
hostile=$tmp_dir/hostile
mkdir -m 700 "$hostile"
ln -s "$tmp_dir/escape" "$hostile/provider-permissions-v1"
if CYCLESTONE_DATA_DIR=$hostile "$permissions" list >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"; then fail 'symlinked store directory was accepted'; fi
grep -Fq 'ERROR E_STORE_UNSAFE:' "$tmp_dir/stderr" || fail 'unsafe store lacks stable diagnostic'
chmod 644 "$store"
expect_error E_STORE_PERMISSIONS "$permissions" list
chmod 600 "$store"

unsafe_data=$tmp_dir/unsafe-data-mode
mkdir -m 755 "$unsafe_data"
expect_error E_STORE_PERMISSIONS env CYCLESTONE_DATA_DIR="$unsafe_data" "$permissions" list
test "$(stat -c %a "$unsafe_data")" = 755 || fail 'unsafe data-directory mode was silently repaired'

unsafe_permission_dir=$tmp_dir/unsafe-permission-directory
mkdir -m 700 "$unsafe_permission_dir"
mkdir -m 755 "$unsafe_permission_dir/provider-permissions-v1"
expect_error E_STORE_PERMISSIONS env CYCLESTONE_DATA_DIR="$unsafe_permission_dir" "$permissions" list
test "$(stat -c %a "$unsafe_permission_dir/provider-permissions-v1")" = 755 || fail 'unsafe permission-directory mode was silently repaired'

unsafe_lock=$tmp_dir/unsafe-lock-mode
mkdir -m 700 "$unsafe_lock" "$unsafe_lock/provider-permissions-v1"
: >"$unsafe_lock/provider-permissions-v1/grants.lock"
chmod 644 "$unsafe_lock/provider-permissions-v1/grants.lock"
expect_error E_STORE_PERMISSIONS env CYCLESTONE_DATA_DIR="$unsafe_lock" "$permissions" list
test "$(stat -c %a "$unsafe_lock/provider-permissions-v1/grants.lock")" = 644 || fail 'unsafe lock mode was silently repaired'

printf '%s\n' 'PASS: local provider authorization, identity, prompts, storage, concurrency, and revocation are enforced'
