#!/bin/sh
set -eu
repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd); cd "$repo_root"
resolver=./scripts/resolve-providers.sh; registry=providers/registry.json
valid=tests/fixtures/providers/valid/all.json; read_only=tests/fixtures/providers/valid/read-only.json
tmp_dir=$(mktemp -d); trap 'rm -rf -- "$tmp_dir"' EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_error() { code=$1; shift; if "$@" >"$tmp_dir/out" 2>"$tmp_dir/err"; then fail "expected $code"; fi; grep -Fq "ERROR $code:" "$tmp_dir/err" || fail "missing stable error $code"; test ! -s "$tmp_dir/out" || fail "$code emitted a plan"; }

jq -e . "$registry" schemas/trusted-provider-registry-v2.schema.json schemas/project-providers-v1.schema.json >/dev/null || fail 'provider JSON is invalid'
schema_tool=$(command -v jsonschema || :)
if test -n "$schema_tool"; then "$schema_tool" -i "$registry" schemas/trusted-provider-registry-v2.schema.json >/dev/null 2>&1 || fail 'trusted registry fails its schema'; fi

jq -e '
  [.definitions[]|.adapters[]|{provider:input_filename,mode,strategy,source_files,environment_names,container_destination,access,import_behavior,synchronization,refresh_behavior,revocation_behavior,directory_mode,file_mode,backup_policy,failure_codes}]|length==7
' "$registry" >/dev/null || fail 'adapter lifecycle metadata is incomplete'

# P1: byte-identity golden — plan output (excluding registry_version) must be deterministic
for tuple in 'claude environment runtime-environment' 'codex read-write isolated-store' 'generic-environment environment runtime-environment' 'ollama host-service host-service' 'opencode read-write isolated-store' 'agy environment runtime-environment'; do
  provider=${tuple%% *}; rest=${tuple#* }; mode=${rest%% *}; strategy=${rest#* }
  first=$($resolver "$valid" "$provider" linux); second=$($resolver "$valid" "$provider" linux)
  test "$first" = "$second" || fail "non-deterministic plan for $provider"
  printf '%s' "$first" | jq -e --arg p "$provider" --arg m "$mode" --arg s "$strategy" '.plan_version==2 and .registry_version==2 and .provider_id==$p and .mode==$m and .credential_adapter.strategy==$s and .credential_adapter.mode==$m and (.credential_adapter.refresh_behavior|length>0)' >/dev/null || fail "invalid adapter plan for $provider"
done
ro=$($resolver "$read_only" codex linux)
printf '%s' "$ro" | jq -e '.filesystem=={access:"read-only",container_destination:"/home/developer/.codex/auth.json",host_source:"${HOME}/.codex/auth.json",kind:"file"} and .credential_adapter.strategy=="direct-file-mount" and .credential_adapter.synchronization=="forbidden"' >/dev/null || fail 'Codex read-only is not an exact-file adapter'

for file in tests/fixtures/providers/invalid-project/*.json; do case "$file" in *duplicate-key*) code=E_PROJECT_JSON;; *) code=E_PROJECT_SCHEMA;; esac; expect_error "$code" "$resolver" "$file" codex linux; done
expect_error E_PROVIDER_DISABLED "$resolver" tests/fixtures/providers/disabled.json codex linux
expect_error E_PROVIDER_UNKNOWN "$resolver" tests/fixtures/providers/unknown-provider.json custom-provider linux
expect_error E_MODE_UNSUPPORTED "$resolver" tests/fixtures/providers/incompatible-mode.json opencode linux
expect_error E_PLATFORM_UNSUPPORTED "$resolver" "$valid" codex darwin

jq -S -c '[.definitions[]|{id,supported_modes,recommended_mode,adapters,host_service:(.host_service//{kind:"none"})}]' "$registry" >"$tmp_dir/boundaries"
cmp -s tests/fixtures/providers/snapshots/access-boundaries.json "$tmp_dir/boundaries" || fail 'credential adapter boundary snapshot changed without review'

# P2: 7th provider JSON-only drop-in — add a provider using existing enum values, zero shell edits
# This proves the v2 registry is data-driven: a new provider with an environment adapter reusing
# an existing env name can be added via JSON only. The snapshot comparison catches the change
# (separate test above), but the shell resolver accepts it without code edits.
drop_in_registry=$tmp_dir/repo/providers/registry.json
mkdir -p "$(dirname "$drop_in_registry")"
jq '.definitions += [{"id":"test-env","display_name":"Test Env","description":"Test provider for JSON-only drop-in.","supported_modes":["environment"],"recommended_mode":"environment","platforms":["linux"],"required_cli":{"name":null,"location":"none"},"adapters":[{"mode":"environment","adapter_version":1,"strategy":"runtime-environment","source_files":[],"environment_names":["HTTPS_PROXY"],"container_destination":null,"access":"environment","import_behavior":"none","synchronization":"none","refresh_behavior":"replace host variables and recreate the session","revocation_behavior":"stop the active session and revoke approval","directory_mode":null,"file_mode":null,"backup_policy":"no Cyclestone credential copy; host and process retention remain external","failure_codes":["E_ENV_MISSING"]}],"security_guidance":"Test provider for JSON-only drop-in."}]' "$registry" >"$drop_in_registry"
# The drop-in registry must pass the v2 schema
if test -n "$schema_tool"; then "$schema_tool" -i "$drop_in_registry" schemas/trusted-provider-registry-v2.schema.json >/dev/null 2>&1 || fail 'drop-in 7th provider fails the v2 schema'; fi
# A project request for the 7th provider must resolve successfully
drop_in_request=$tmp_dir/repo/request.json
printf '%s\n' '{"version":1,"providers":{"test-env":{"enabled":true,"mode":"environment"}}}' >"$drop_in_request"
# The resolver uses repo_root relative path, so copy the resolver too
mkdir -p "$tmp_dir/repo/scripts"
cp "$resolver" "$tmp_dir/repo/scripts/resolve-providers.sh"; chmod +x "$tmp_dir/repo/scripts/resolve-providers.sh"
drop_in_plan=$("$tmp_dir/repo/scripts/resolve-providers.sh" "$drop_in_request" test-env linux 2>"$tmp_dir/err") || fail "7th provider JSON drop-in failed to resolve: $(cat "$tmp_dir/err")"
printf '%s' "$drop_in_plan" | jq -e '.plan_version==2 and .registry_version==2 and .provider_id=="test-env" and .mode=="environment" and .credential_adapter.strategy=="runtime-environment" and .credential_adapter.environment_names==["HTTPS_PROXY"]' >/dev/null || fail '7th provider plan is invalid'

# Hostile registry mutations: structural and access-boundary violations must fail closed.
# v2 separates structural/access validation (schema+shell) from semantic validation (snapshot).
# Descriptive metadata changes (import_behavior text, failure_codes list) are allowed by the
# shell validator — the snapshot comparison and maintainer review catch them.
mutate_and_reject() {
  name=$1; filter=$2; rm -rf "$tmp_dir/repo"; mkdir -p "$tmp_dir/repo/scripts" "$tmp_dir/repo/providers"
  jq "$filter" "$registry" >"$tmp_dir/repo/providers/registry.json"; cp "$resolver" "$tmp_dir/repo/scripts/resolve-providers.sh"; chmod +x "$tmp_dir/repo/scripts/resolve-providers.sh"
  schema_rejects=yes
  if test -n "$schema_tool" && "$schema_tool" -i "$tmp_dir/repo/providers/registry.json" schemas/trusted-provider-registry-v2.schema.json >/dev/null 2>&1; then schema_rejects=no; fi
  shell_rejects=yes
  if "$tmp_dir/repo/scripts/resolve-providers.sh" "$valid" codex linux >"$tmp_dir/out" 2>"$tmp_dir/err"; then shell_rejects=no; fi
  if [ "$schema_rejects" = "no" ] && [ "$shell_rejects" = "no" ]; then fail "$name accepted by both schema and shell"; fi
  if [ "$shell_rejects" = "yes" ]; then grep -Fq "ERROR E_REGISTRY_SCHEMA:" "$tmp_dir/err" || fail "$name shell rejected without E_REGISTRY_SCHEMA"; fi
}
mutate_and_reject root '.definitions[1].adapters[0].source_files=["/"]'
mutate_and_reject home '.definitions[1].adapters[0].source_files=["${HOME}"]'
mutate_and_reject config '.definitions[1].adapters[0].source_files=["${HOME}/.config"]'
mutate_and_reject whole-auth-directory '.definitions[1].adapters[0].source_files=["${HOME}/.codex"]'
mutate_and_reject traversal '.definitions[1].adapters[0].source_files=["${HOME}/.codex/../.ssh/id_rsa"]'
mutate_and_reject podman-socket '.definitions[1].adapters[0].source_files=["${XDG_RUNTIME_DIR}/podman/podman.sock"]'
mutate_and_reject undeclared-file '.definitions[1].adapters[0].source_files=["${HOME}/.codex/config.toml"]'
mutate_and_reject destination '.definitions[1].adapters[0].container_destination="/workspace/auth.json"'
mutate_and_reject environment '.definitions[2].adapters[0].environment_names += ["UNREVIEWED_TOKEN"]'
mutate_and_reject wildcard '.definitions[2].adapters[0].environment_names=["HTTP_*"]'
mutate_and_reject endpoint '.definitions[3].host_service.default_endpoint="http://127.0.0.1:9999"'
mutate_and_reject custom-field '.definitions[0].adapters[0].credential_value="not-allowed"'
mutate_and_reject broad-writable '.definitions[1].adapters[1].strategy="direct-file-mount"'
mutate_and_reject duplicate-id '.definitions[4].id="codex"'
mutate_and_reject codex-opencode-source '.definitions[1].adapters[1].source_files=["${HOME}/.local/share/opencode/auth.json"]'
mutate_and_reject codex-opencode-destination '.definitions[1].adapters[1].container_destination="/home/developer/.local/share/opencode/auth.json"'
mutate_and_reject access-mismatch '.definitions[1].adapters[0].access="read-write"'
mutate_and_reject mode-mismatch '.definitions[1].adapters[0].mode="read-write"'
mutate_and_reject directory-mode-mismatch '.definitions[1].adapters[1].directory_mode=null'
mutate_and_reject file-mode-mismatch '.definitions[4].adapters[0].file_mode=null'

printf '%s\n' 'PASS: closed provider credential adapters, deterministic plans, 7th-provider JSON drop-in, and hostile boundaries are enforced'