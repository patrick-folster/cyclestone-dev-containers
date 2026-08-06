#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
registry=$repo_root/providers/registry.json
fail() { printf 'ERROR %s: %s\n' "$1" "$2" >&2; exit 1; }

test "$#" -eq 3 || fail E_USAGE 'usage: resolve-providers.sh PROJECT PROVIDER_ID PLATFORM'
project=$1; provider_id=$2; platform=$3
test -f "$project" || fail E_PROJECT_READ 'project request is not a readable file'

reject_duplicate_leaves() {
  jq empty "$1" >/dev/null 2>&1 || return 1
  jq --stream -n -e 'reduce (inputs|select(length==2)|.[0]|@json) as $p ({};if has($p) then error("duplicate key") else .[$p]=true end)' "$1" >/dev/null 2>&1
}
reject_duplicate_leaves "$project" || fail E_PROJECT_JSON 'project JSON is invalid or contains a duplicate key'
reject_duplicate_leaves "$registry" || fail E_REGISTRY_JSON 'trusted registry JSON is invalid or contains a duplicate key'

jq -e '
  type=="object" and (keys|sort)==["providers","version"] and .version==1
  and (.providers|type=="object" and length>0)
  and all(.providers|to_entries[]; . as $e | ($e.key|test("^[a-z][a-z0-9-]{1,62}[a-z0-9]$"))
    and ($e.value|type=="object" and (keys|sort)==["enabled","mode"])
    and ($e.value.enabled|type=="boolean")
    and (($e.value.enabled==false and $e.value.mode=="disabled") or
      ($e.value.enabled==true and (["read-only","read-write","environment","host-service"]|index($e.value.mode)!=null))))
' "$project" >/dev/null 2>&1 || fail E_PROJECT_SCHEMA 'project request does not satisfy schema version 1'

# Generic registry validator: structure + adapter coherence without per-ID branches.
# Adapter cross-field rules mirror schemas/trusted-provider-registry-v2.schema.json
# strategy-family oneOf branches. This is defense-in-depth alongside the JSON Schema.
jq -e '
  def exact($k): type=="object" and (keys|sort)==($k|sort);
  def text: type=="string" and length>0;
  def cli: exact(["location","name"]) and ((.location=="none" and .name==null) or (.location=="container" and (.name|text)));
  def service: exact(["authentication","default_endpoint","endpoint_environment","kind","transport"])
    and .kind=="http" and .endpoint_environment=="OLLAMA_HOST" and .default_endpoint=="http://host.containers.internal:11434" and .transport=="tcp" and .authentication=="none";
  def adapter: . as $a |
    exact(["access","adapter_version","backup_policy","container_destination","directory_mode","environment_names","failure_codes","file_mode","import_behavior","mode","refresh_behavior","revocation_behavior","source_files","strategy","synchronization"])
    and $a.adapter_version==1
    and $a.access==$a.mode
    and (["direct-file-mount","isolated-store","runtime-environment","host-service"]|index($a.strategy)!=null)
    and (["read-only","read-write","environment","host-service"]|index($a.mode)!=null)
    and ($a.source_files|type=="array" and length==(unique|length)
      and all(.[];. as $s|["${HOME}/.codex/auth.json","${HOME}/.local/share/opencode/auth.json"]|index($s)!=null))
    and ($a.environment_names|type=="array" and length==(unique|length) and .==sort
      and all(.[];. as $n|["ANTHROPIC_API_KEY","HTTPS_PROXY","HTTP_PROXY","NO_PROXY","OLLAMA_HOST","GEMINI_API_KEY"]|index($n)!=null))
    and ([null,"/home/developer/.codex/auth.json","/home/developer/.local/share/opencode/auth.json"]|index($a.container_destination)!=null)
    and ([null,700]|index($a.directory_mode)!=null) and ([null,600]|index($a.file_mode)!=null)
    and (.import_behavior|text) and (.synchronization|text) and (.refresh_behavior|text) and (.revocation_behavior|text) and (.backup_policy|text)
    and (.failure_codes|type=="array" and length>0 and length==(unique|length) and all(.[];test("^E_[A-Z_]+$")))
    and (if .strategy=="runtime-environment" then .mode=="environment" and (.source_files|length)==0 and (.environment_names|length)>0 and .container_destination==null and .directory_mode==null and .file_mode==null
      elif .strategy=="host-service" then .mode=="host-service" and .source_files==[] and (.environment_names|length)>0 and .container_destination==null and .directory_mode==null and .file_mode==null
      elif .strategy=="direct-file-mount" then .mode=="read-only" and (.source_files|length)==1 and .environment_names==[] and (.container_destination|text) and .directory_mode==null and .file_mode==600
        and ((.source_files[0]=="${HOME}/.codex/auth.json" and .container_destination=="/home/developer/.codex/auth.json")
          or (.source_files[0]=="${HOME}/.local/share/opencode/auth.json" and .container_destination=="/home/developer/.local/share/opencode/auth.json"))
      else .strategy=="isolated-store" and .mode=="read-write" and (.source_files|length)==1 and .environment_names==[] and (.container_destination|text) and .directory_mode==700 and .file_mode==600
        and ((.source_files[0]=="${HOME}/.codex/auth.json" and .container_destination=="/home/developer/.codex/auth.json")
          or (.source_files[0]=="${HOME}/.local/share/opencode/auth.json" and .container_destination=="/home/developer/.local/share/opencode/auth.json")) end);
  type=="object" and exact(["definitions","registry_version"]) and .registry_version==2
  and (.definitions|type=="array" and length>0 and length==([.[].id]|unique|length)
    and all(.[]; (.id|test("^[a-z][a-z0-9-]{1,62}[a-z0-9]$"))))
  and all(.definitions[]; . as $d |
    (if ($d.adapters|any(.strategy=="host-service")) then ($d|has("host_service")) and ($d.host_service|service) else ($d|has("host_service")|not) end)
    and ($d|exact(["adapters","description","display_name","id","platforms","recommended_mode","required_cli","security_guidance","supported_modes"]
      + (if $d|has("host_service") then ["host_service"] else [] end)))
    and ($d.display_name|text) and ($d.description|text) and ($d.security_guidance|text)
    and $d.platforms==["linux"] and ($d.required_cli|cli)
    and ($d.adapters|type=="array" and length>0 and length==([.[].mode]|unique|length) and all(.[];adapter))
    and ($d.supported_modes|type=="array" and length>0 and length==(unique|length)
      and all(.[];. as $m|["read-only","read-write","environment","host-service"]|index($m)!=null))
    and ($d.supported_modes|sort)==([$d.adapters[].mode]|sort)
    and ($d.supported_modes|index($d.recommended_mode)!=null))
' "$registry" >/dev/null 2>&1 || fail E_REGISTRY_SCHEMA 'trusted registry does not satisfy version 2 credential policy'

request_count=$(jq --arg id "$provider_id" '[.providers|to_entries[]|select(.key==$id)]|length' "$project")
test "$request_count" -eq 1 || fail E_PROVIDER_MISSING 'requested provider is not present in project configuration'
enabled=$(jq -r --arg id "$provider_id" '.providers[$id].enabled' "$project")
mode=$(jq -r --arg id "$provider_id" '.providers[$id].mode' "$project")
test "$enabled" = true || fail E_PROVIDER_DISABLED 'requested provider is disabled'
definition_count=$(jq --arg id "$provider_id" '[.definitions[]|select(.id==$id)]|length' "$registry")
test "$definition_count" -eq 1 || fail E_PROVIDER_UNKNOWN 'requested provider has no unique trusted definition'
jq -e --arg id "$provider_id" --arg mode "$mode" '.definitions[]|select(.id==$id)|.supported_modes|index($mode)!=null' "$registry" >/dev/null || fail E_MODE_UNSUPPORTED 'requested access mode is unsupported'
jq -e --arg id "$provider_id" --arg platform "$platform" '.definitions[]|select(.id==$id)|.platforms|index($platform)!=null' "$registry" >/dev/null || fail E_PLATFORM_UNSUPPORTED 'requested platform is unsupported'

jq -S -c --arg id "$provider_id" --arg mode "$mode" --arg platform "$platform" '
  .registry_version as $rv | .definitions[]|select(.id==$id) as $d | $d.adapters[]|select(.mode==$mode) as $a |
  {plan_version:2,registry_version:$rv,provider_id:$d.id,display_name:$d.display_name,description:$d.description,mode:$mode,platform:$platform,
   filesystem:(if ($a.source_files|length)==0 then {kind:"none"} else {kind:"file",host_source:$a.source_files[0],container_destination:$a.container_destination,access:$a.access} end),
   environment_names:$a.environment_names,host_service:($d.host_service//{kind:"none"}),required_cli:$d.required_cli,credential_adapter:$a,security_guidance:$d.security_guidance}
' "$registry"