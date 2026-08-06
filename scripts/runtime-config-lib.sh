#!/bin/sh
# Shared implementation for the repository-local generate and validate commands.

runtime_config_init() {
  generator_version=1.0.0
  registry=$repo_root/providers/registry.json
  template=$repo_root/templates/project-devcontainer/.devcontainer/devcontainer.json
  permissions=$repo_root/scripts/devcontainer-permissions.sh
  credentials=$repo_root/scripts/provider-credentials.sh
  safe_mode=${SAFE_MODE:-false}
}

runtime_fail() { printf 'ERROR %s: %s\n' "$1" "$2" >&2; exit 1; }
runtime_test_fault() {
  test "${CYCLESTONE_RUNTIME_CONFIG_TEST_FAULT:-}" != "$1" || runtime_fail E_WRITE "injected failure at $1"
}
runtime_test_pause_for_source_swap() {
  test "${CYCLESTONE_RUNTIME_CONFIG_TEST_FAULT:-}" = source-swap || return 0
  ready_fifo=${CYCLESTONE_RUNTIME_CONFIG_TEST_READY_FIFO:-}
  continue_fifo=${CYCLESTONE_RUNTIME_CONFIG_TEST_CONTINUE_FIFO:-}
  test -p "$ready_fifo" && test -p "$continue_fifo" || runtime_fail E_WRITE 'source-swap test FIFOs are unavailable'
  printf '%s\n' ready >"$ready_fifo"
  IFS= read -r resume <"$continue_fifo" || runtime_fail E_WRITE 'source-swap test did not resume'
  test "$resume" = continue || runtime_fail E_WRITE 'source-swap test supplied an invalid resume token'
}
runtime_hash_file() { jq -S -c . "$1" | sha256sum | awk '{print $1}'; }
runtime_hash_text() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
runtime_reject_duplicates() {
  jq empty "$1" >/dev/null 2>&1 &&
    jq --stream -n -e 'reduce (inputs|select(length==2)|.[0]|@json) as $p ({};if has($p) then error("duplicate key") else .[$p]=true end)' "$1" >/dev/null 2>&1
}
runtime_require_tools() {
  for runtime_tool in jq git realpath stat sha256sum awk mktemp diff sync mv chmod mkdir dirname devcontainer cp cmp rm; do
    command -v "$runtime_tool" >/dev/null 2>&1 || runtime_fail E_TOOL_MISSING "required host tool is unavailable: $runtime_tool"
  done
  test "$(devcontainer --version 2>/dev/null)" = 0.86.0 || runtime_fail E_CLI_VERSION 'Dev Container CLI 0.86.0 is required'
}
runtime_validate_template() {
  runtime_reject_duplicates "$template" || runtime_fail E_TEMPLATE_JSON 'structural template JSON is invalid or contains a duplicate key'
  jq -e '
    type=="object" and (keys|sort)==["build","containerUser","customizations","mounts","name","overrideCommand","postCreateCommand","privileged","remoteUser","runArgs","updateRemoteUserUID","workspaceFolder","workspaceMount"]
    and .remoteUser=="developer" and .containerUser=="developer" and .updateRemoteUserUID==false
    and .workspaceFolder=="/workspace" and .workspaceMount=="source=${localWorkspaceFolder},target=/workspace,type=bind"
    and .privileged==false and .overrideCommand==true
    and .postCreateCommand=="/workspace/.devcontainer/lifecycle.sh postCreate"
    and .runArgs==["--userns=keep-id:uid=1000,gid=1000","--security-opt=no-new-privileges"]
    and .mounts==["source=cyclestone-project-go-cache,target=/home/developer/.cache/go-build,type=volume"]
    and .customizations=={}
    and (.build|type=="object" and (keys|sort)==["args","context","dockerfile"] and .dockerfile=="Containerfile" and .context=="..")
  ' "$template" >/dev/null 2>&1 || runtime_fail E_TEMPLATE_SCHEMA 'template violates the reviewed project Dev Container contract'
}
runtime_validate_request() {
  runtime_reject_duplicates "$request_file" || runtime_fail E_REQUEST_JSON 'project request JSON is invalid or contains a duplicate key'
  jq -e '
    type=="object" and (keys|sort)==["providers","version"] and .version==1
    and (.providers|type=="object" and length>0)
    and all(.providers|to_entries[]; .key|test("^[a-z][a-z0-9-]{1,62}[a-z0-9]$"))
    and all(.providers[]; . as $request | type=="object" and (keys|sort)==["enabled","mode"]
      and (($request.enabled==false and $request.mode=="disabled") or ($request.enabled==true and (["read-only","read-write","environment","host-service"]|index($request.mode)!=null))))
  ' "$request_file" >/dev/null 2>&1 || runtime_fail E_REQUEST_SCHEMA 'project request does not satisfy the closed version-1 schema'
}
runtime_validate_generated_file() {
  generated_file=$1
  generated_kind=$2
  runtime_reject_duplicates "$generated_file" || runtime_fail E_GENERATED_JSON 'generated configuration is invalid JSON or contains a duplicate key'
  jq -e --arg kind "$generated_kind" --arg generator "$generator_version" --arg safeMode "$safe_mode" --slurpfile base "$template" --slurpfile registry "$registry" '
    ([$registry[0].definitions[].adapters[].environment_names[]] | unique) as $envNames
    | def metadata:
      type=="object" and (keys|sort)==["generatorVersion","inputIdentities","outputKind","safeMode","schemaVersion"]
      and .schemaVersion==1 and .generatorVersion==$generator and .outputKind==$kind and .safeMode==($safeMode=="true")
      and (.inputIdentities|type=="object" and (keys|sort)==["projectRequestSha256","registrySha256","templateSha256"]
        and all(.[];type=="string" and test("^[0-9a-f]{64}$")));
    def structural:
      .name==$base[0].name and .build==$base[0].build
      and .remoteUser=="developer" and .containerUser=="developer" and .updateRemoteUserUID==false
      and .workspaceFolder=="/workspace" and .workspaceMount=="source=${localWorkspaceFolder},target=/workspace,type=bind"
      and .privileged==false and .overrideCommand==true
      and (if $safeMode=="true" then
             (has("postCreateCommand")|not) and (has("updateContentCommand")|not) and (has("postStartCommand")|not) and (has("postAttachCommand")|not) and (has("initializeCommand")|not) and (has("onCreateCommand")|not) and (has("waitFor")|not)
           else
             .postCreateCommand=="/workspace/.devcontainer/lifecycle.sh postCreate"
           end)
      and .runArgs==["--userns=keep-id:uid=1000,gid=1000","--security-opt=no-new-privileges"]
      and (.build|type=="object" and (keys|sort)==["args","context","dockerfile"] and .dockerfile=="Containerfile" and .context=="..")
      and (.mounts|type=="array" and length>0 and all(.[];type=="string"))
      and .mounts[0]==$base[0].mounts[0];
    type=="object" and structural
    and (.customizations.cyclestone.generatedRuntimeConfiguration|metadata)
    and if $kind=="portable" then
      (keys|sort)==(if $safeMode=="true" then ["build","containerUser","customizations","mounts","name","overrideCommand","privileged","remoteUser","runArgs","updateRemoteUserUID","workspaceFolder","workspaceMount"] else ["build","containerUser","customizations","mounts","name","overrideCommand","postCreateCommand","privileged","remoteUser","runArgs","updateRemoteUserUID","workspaceFolder","workspaceMount"] end)
      and .mounts==$base[0].mounts
      and (.customizations|keys)==["cyclestone"]
      and (.customizations.cyclestone|keys)==["generatedRuntimeConfiguration"]
    else
      (keys|sort)==(if $safeMode=="true" then ["build","containerEnv","containerUser","customizations","mounts","name","overrideCommand","privileged","remoteUser","runArgs","updateRemoteUserUID","workspaceFolder","workspaceMount"] else ["build","containerEnv","containerUser","customizations","mounts","name","overrideCommand","postCreateCommand","privileged","remoteUser","runArgs","updateRemoteUserUID","workspaceFolder","workspaceMount"] end)
      and (.customizations|keys)==["cyclestone"]
      and (.customizations.cyclestone|keys|sort)==["generatedRuntimeConfiguration","runtimeAccess"]
       and (.containerEnv|type=="object" and all(to_entries[];
          (.key as $k | ($envNames|index($k))!=null) and .value==("${localEnv:"+.key+"}")))
       and (.customizations.cyclestone.runtimeAccess|type=="array"
         and .==sort_by(.providerId) and ([.[].providerId]|length==(unique|length))
         and all(.[];type=="object" and (keys|sort)==["environmentNames","hostService","mode","mountDestination","providerId","strategy"]
           and (.providerId|test("^[a-z][a-z0-9-]{1,62}[a-z0-9]$"))
           and (.environmentNames|type=="array" and .==sort and length==(unique|length)
              and all(.[]; . as $n | ($envNames|index($n))!=null))
          and (.mountDestination==null or (.mountDestination|type=="string" and startswith("/") and (contains("..")|not)))
          and if .mode=="environment" then
            .strategy=="runtime-environment" and (.environmentNames|length)>0 and .mountDestination==null and .hostService=={"kind":"none"}
          elif .mode=="host-service" then
            .strategy=="host-service" and .mountDestination==null
            and (.hostService|type=="object" and (keys|sort)==["authentication","default_endpoint","endpoint_environment","kind","transport"]
              and .kind=="http" and .authentication=="none" and .transport=="tcp"
               and (.default_endpoint|type=="string" and test("^https?://[^[:space:]]+$"))
              and (.endpoint_environment|type=="string" and test("^[A-Z][A-Z0-9_]*$")))
          elif .mode=="read-only" then
            .strategy=="direct-file-mount" and (.environmentNames|length)==0 and .mountDestination!=null and .hostService=={"kind":"none"}
          elif .mode=="read-write" then
            .strategy=="isolated-store" and (.environmentNames|length)==0 and .mountDestination!=null and .hostService=={"kind":"none"}
          else false end))
    end
  ' "$generated_file" >/dev/null 2>&1 || runtime_fail E_GENERATED_SCHEMA "generated $generated_kind configuration violates the closed schema"
}
runtime_validate_generated_pair() {
  portable_file=$1
  local_file=$2
  runtime_validate_generated_file "$portable_file" portable
  runtime_validate_generated_file "$local_file" local-runtime
  jq -e -s '
    .[0] as $portable | .[1] as $local |
    $portable.customizations.cyclestone.generatedRuntimeConfiguration.inputIdentities
      == $local.customizations.cyclestone.generatedRuntimeConfiguration.inputIdentities
    and (($local
      | del(.containerEnv, .customizations.cyclestone.runtimeAccess)
      | .mounts=$portable.mounts
      | .customizations.cyclestone.generatedRuntimeConfiguration.outputKind="portable") == $portable)
    and (($local.containerEnv|keys) == ([$local.customizations.cyclestone.runtimeAccess[].environmentNames[]]|unique))
    and (([$local.customizations.cyclestone.runtimeAccess[].environmentNames[]] | length)
      == ([$local.customizations.cyclestone.runtimeAccess[].environmentNames[]] | unique | length))
    and ($local.mounts[1:] as $providerMounts
      | [$local.customizations.cyclestone.runtimeAccess[]|select(.mountDestination!=null)] as $mountAccess
      | ($providerMounts|length)==($mountAccess|length)
      and ([$mountAccess[].mountDestination]|length)==([$mountAccess[].mountDestination]|unique|length)
      and all($mountAccess[]; . as $access
        | any($providerMounts[];
            startswith("source=/")
            and contains(",target="+$access.mountDestination+",type=bind,")
            and endswith(if $access.mode=="read-only" then "readonly" else "rw" end))))
  ' "$portable_file" "$local_file" >/dev/null 2>&1 \
    || runtime_fail E_GENERATED_PAIR 'generated portable and local-runtime configurations are inconsistent'
}
runtime_validate_paths() {
  test -d "$project_arg" || runtime_fail E_PROJECT_PATH 'project root is not a directory'
  test ! -L "$project_arg" || runtime_fail E_PROJECT_PATH 'project root must not be a symbolic link'
  project_root=$(realpath -e -- "$project_arg") || runtime_fail E_PROJECT_PATH 'project root cannot be canonicalized'
  test ! -L "$request_arg" || runtime_fail E_REQUEST_PATH 'project request must not be a symbolic link'
  request_file=$(realpath -e -- "$request_arg") || runtime_fail E_REQUEST_PATH 'project request cannot be canonicalized'
  case "$request_file/" in "$project_root/"*) :;; *) runtime_fail E_REQUEST_PATH 'project request must be inside the project root';; esac
  portable_output=$project_root/.devcontainer/devcontainer.json
  local_output=$project_root/.cyclestone/runtime/devcontainer.json
  for output_parent in "$project_root/.devcontainer" "$project_root/.cyclestone" "$project_root/.cyclestone/runtime"; do
    if test -e "$output_parent" || test -L "$output_parent"; then
      test ! -L "$output_parent" && test -d "$output_parent" || runtime_fail E_OUTPUT_PATH 'generated output parent must be a real directory'
    fi
  done
}
runtime_check_conflicts() {
  duplicate_env=$(printf '%s' "$plans" | jq -r '[.[].environment_names[]]|group_by(.)|map(select(length>1)|.[0])|first//empty')
  test -z "$duplicate_env" || runtime_fail E_CONFLICT "multiple providers contribute environment name $duplicate_env"
  duplicate_target=$(printf '%s' "$plans" | jq -r '[.[].mount|select(.!=null)|.destination]|group_by(.)|map(select(length>1)|.[0])|first//empty')
  test -z "$duplicate_target" || runtime_fail E_CONFLICT "multiple providers contribute mount destination $duplicate_target"
}
runtime_metadata() {
  output_kind=$1
  is_safe_json=$(test "$safe_mode" = true && echo true || echo false)
  jq -S -c -n --arg generator "$generator_version" --arg kind "$output_kind" --argjson safeMode "$is_safe_json" --arg request "$request_hash" --arg registry "$registry_hash" --arg template "$template_hash" \
    '{schemaVersion:1,generatorVersion:$generator,outputKind:$kind,safeMode:$safeMode,inputIdentities:{projectRequestSha256:$request,registrySha256:$registry,templateSha256:$template}}'
}
runtime_expected_mount_source() {
  expected_strategy=$1
  if test "$expected_strategy" = direct-file-mount; then
    source_template=$(printf '%s' "$authorized_plan" | jq -r '.filesystem.host_source')
    case "$source_template" in
      '${HOME}/'*) expected_source=${HOME}${source_template#\$\{HOME\}};;
      *) runtime_fail E_RUNTIME_PLAN "provider $provider_id authorized an unsupported credential source";;
    esac
  elif test "$expected_strategy" = isolated-store; then
    if test -n "${CYCLESTONE_DATA_DIR:-}"; then data_root=$CYCLESTONE_DATA_DIR
    elif test -n "${XDG_DATA_HOME:-}"; then data_root=$XDG_DATA_HOME/cyclestone
    else test -n "${HOME:-}" || runtime_fail E_RUNTIME_PLAN 'HOME, XDG_DATA_HOME, or CYCLESTONE_DATA_DIR is required'; data_root=$HOME/.local/share/cyclestone; fi
    grant_id=$(runtime_hash_text "$(printf '%s' "$authorization" | jq -r .identity_fingerprint):$(printf '%s' "$authorization" | jq -r .request_fingerprint)")
    expected_source=$data_root/provider-credentials-v1/$grant_id/isolated
  else
    expected_source=
    return 0
  fi
  expected_source=$(realpath -e -- "$expected_source") || runtime_fail E_RUNTIME_PLAN "provider $provider_id prepared an unavailable grant-bound source"
}
runtime_validate_runtime_plan() {
  printf '%s' "$runtime" | jq -e --arg id "$provider_id" --argjson plan "$authorized_plan" '
    . as $runtime | type=="object" and (keys|sort)==["credential_runtime_version","environment_names","host_service","mode","mount","provider_id","strategy"]
    and $runtime.credential_runtime_version==1 and $runtime.provider_id==$id
    and $runtime.mode==$plan.mode and $runtime.strategy==$plan.credential_adapter.strategy
    and $runtime.environment_names==$plan.environment_names and $runtime.host_service==$plan.host_service
    and ($runtime.environment_names|type=="array" and .==sort and length==(unique|length)
      and all(.[];test("^[A-Z][A-Z0-9_]*$")))
    and if $runtime.mode=="environment" then
      $runtime.strategy=="runtime-environment" and ($runtime.environment_names|length)>0
      and $runtime.mount==null and $runtime.host_service=={"kind":"none"}
    elif $runtime.mode=="host-service" then
      $runtime.strategy=="host-service" and ($runtime.environment_names|length)>0 and $runtime.mount==null
      and ($runtime.host_service|type=="object" and (keys|sort)==["authentication","default_endpoint","endpoint_environment","kind","transport"]
        and .kind=="http" and .transport=="tcp" and .authentication=="none"
        and (.default_endpoint|test("^https?://[^[:space:]]+$"))
        and (.endpoint_environment|test("^[A-Z][A-Z0-9_]*$")))
    elif $runtime.mode=="read-only" or $runtime.mode=="read-write" then
      $runtime.strategy==(if $runtime.mode=="read-only" then "direct-file-mount" else "isolated-store" end)
      and $runtime.environment_names==[] and $runtime.host_service=={"kind":"none"}
      and ($runtime.mount as $mount | $mount|type=="object" and (keys|sort)==["access","destination","source"]
        and $mount.access==$runtime.mode and ($mount.source|type=="string" and startswith("/"))
        and ($mount.destination|type=="string" and startswith("/")))
      and (($plan.credential_adapter.container_destination |
        if $runtime.strategy=="isolated-store" then sub("/[^/]+$";"") else . end) == $runtime.mount.destination)
    else false end
  ' >/dev/null 2>&1 || runtime_fail E_RUNTIME_PLAN "provider $provider_id returned a malformed or authorization-mismatched credential runtime plan"
  runtime_expected_mount_source "$(printf '%s' "$runtime" | jq -r .strategy)"
  actual_source=$(printf '%s' "$runtime" | jq -r '.mount.source // empty')
  test "$actual_source" = "$expected_source" || runtime_fail E_RUNTIME_PLAN "provider $provider_id runtime mount source is outside its fresh grant-bound source"
}
runtime_collect() {
  plans='[]'
  sources='[]'
  allowed_destinations=$(jq -r '[.definitions[].adapters[].container_destination]|map(select(.!=null))|unique|map(. + "\n" + (sub("/[^/]+$";"")))|join("\n")' "$registry")
  enabled_count=$(jq -r '.providers|to_entries|map(select(.value.enabled))|length' "$request_file")
  if test "$safe_mode" = true; then
    if test "$enabled_count" -gt 0; then
      runtime_fail E_SAFE_MODE_DENIED 'host provider credential grants are blocked in safe mode'
    fi
  fi
  for provider_id in $(jq -r '.providers|to_entries|map(select(.value.enabled))|sort_by(.key)|.[].key' "$request_file"); do
    authorization=$($permissions authorize "$project_root" "$request_file" "$provider_id" linux) || runtime_fail E_PERMISSION "provider $provider_id lacks a fresh exact persistent grant"
    printf '%s' "$authorization" | jq -e --arg id "$provider_id" '
      type=="object" and (keys|sort)==["authorization_version","authorized","decision","identity","identity_fingerprint","plan","request_fingerprint"]
      and .authorization_version==1 and .authorized==true and .decision=="always"
      and (.identity_fingerprint|test("^[0-9a-f]{64}$")) and (.request_fingerprint|test("^[0-9a-f]{64}$"))
      and .plan.plan_version==2 and .plan.platform=="linux" and .plan.provider_id==$id
    ' >/dev/null 2>&1 || runtime_fail E_GRANT_SCHEMA "provider $provider_id returned an invalid authorization"
    authorized_plan=$(printf '%s' "$authorization" | jq -S -c .plan)
    runtime=$($credentials prepare "$project_root" "$request_file" "$provider_id" linux) || runtime_fail E_PREREQUISITE "provider $provider_id credential prerequisites are not satisfied"
    runtime_validate_runtime_plan
    plans=$(printf '%s' "$plans" | jq -S -c --argjson plan "$runtime" '.+[$plan]|sort_by(.provider_id)')
  done
  runtime_check_conflicts
  printf '%s' "$plans" | jq -c '.[]|.mount|select(.!=null)' >"$render_dir/mounts.jsonl"
  while IFS= read -r mount; do
    source=$(printf '%s' "$mount" | jq -r .source); destination=$(printf '%s' "$mount" | jq -r .destination)
    case "$source" in *"/.."|*"/../"*|"../"*|*"..") runtime_fail E_PATH_TRAVERSAL "mount source contains path traversal: $source";; esac
    case "$destination" in *"/.."|*"/../"*|"../"*|*"..") runtime_fail E_PATH_TRAVERSAL "mount destination contains path traversal: $destination";; esac
    case "$source" in *.sock|*docker.sock*|*podman.sock*) runtime_fail E_PROHIBITED_MOUNT 'direct mounting of host container engine daemon sockets is explicitly prohibited';; esac
    case "$destination" in *.sock|*docker.sock*|*podman.sock*) runtime_fail E_PROHIBITED_MOUNT 'direct mounting of host container engine daemon sockets is explicitly prohibited';; esac
    if test -e "$source" && test -S "$source"; then runtime_fail E_PROHIBITED_MOUNT 'direct mounting of host container engine daemon sockets is explicitly prohibited'; fi
    case "$source" in *.ollama*|*/models/*|*/models|*huggingface*) runtime_fail E_PROHIBITED_MOUNT 'direct mounting of raw model data directories is explicitly prohibited';; esac
    case "$destination" in *.ollama*|*/models/*|*/models|*huggingface*) runtime_fail E_PROHIBITED_MOUNT 'direct mounting of raw model data directories is explicitly prohibited';; esac
    case "$destination" in /workspace|/home/developer|/home/developer/.cache/go-build|/usr/*|/etc/*|/proc/*|/sys/*|/run/*) runtime_fail E_DESTINATION "reserved mount destination: $destination";; esac
    printf '%s\n' "$allowed_destinations" | grep -qxF "$destination" || runtime_fail E_DESTINATION "non-fixed or arbitrary container destination path is disallowed: $destination"
    case "$source$destination" in *','*|*':'*) runtime_fail E_PATH_UNSUPPORTED 'runtime mount paths containing comma or colon are unsupported';; esac
    test ! -L "$source" || runtime_fail E_SOURCE_LINK 'credential mount source must not be a symbolic link'
    canonical=$(realpath -e -- "$source") || runtime_fail E_SOURCE_MISSING 'credential mount source cannot be canonicalized'
    test "$canonical" = "$source" || runtime_fail E_SOURCE_CHANGED 'credential mount source changed during canonicalization'
    source_type=$(printf '%s' "$mount" | jq -r '.access as $access | if $access=="read-only" then "file" else "directory" end')
    if test "$source_type" = file; then test -f "$source" || runtime_fail E_SOURCE_TYPE 'direct credential mount source must be a regular file'
    else test -d "$source" || runtime_fail E_SOURCE_TYPE 'isolated credential mount source must be a directory'; fi
    sources=$(printf '%s' "$sources" | jq -S -c --arg path "$source" --argjson device "$(stat -c %d "$source")" --argjson inode "$(stat -c %i "$source")" --arg type "$source_type" '.+[{path:$path,device:$device,inode:$inode,type:$type}]')
  done <"$render_dir/mounts.jsonl"
}
runtime_render() {
  request_hash=$(runtime_hash_file "$request_file")
  registry_hash=$(runtime_hash_file "$registry")
  template_hash=$(runtime_hash_file "$template")
  portable_metadata=$(runtime_metadata portable)
  local_metadata=$(runtime_metadata local-runtime)
  if test "$safe_mode" = true; then
    portable=$(jq -S --argjson metadata "$portable_metadata" '
      .customizations={cyclestone:{generatedRuntimeConfiguration:$metadata}}
      | del(.postCreateCommand, .updateContentCommand, .postStartCommand, .postAttachCommand, .initializeCommand, .onCreateCommand, .waitFor)
    ' "$template")
  else
    portable=$(jq -S --argjson metadata "$portable_metadata" '.customizations={cyclestone:{generatedRuntimeConfiguration:$metadata}}' "$template")
  fi
  container_env=$(printf '%s' "$plans" | jq -S -c '[.[].environment_names[]]|unique|map({key:.,value:("${localEnv:"+.+"}")})|from_entries')
  provider_mounts=$(printf '%s' "$plans" | jq -S -c '[.[]|.mount|select(.!=null)|"source="+.source+",target="+.destination+",type=bind,"+(if .access=="read-only" then "readonly" else "rw" end)]|sort')
  access=$(printf '%s' "$plans" | jq -S -c '[.[]|{providerId:.provider_id,mode,strategy,environmentNames:.environment_names,mountDestination:(.mount.destination//null),hostService:.host_service}]')
  if test "$safe_mode" = true; then
    local_config=$(printf '%s' "$portable" | jq -S --argjson metadata "$local_metadata" --argjson env "$container_env" --argjson mounts "$provider_mounts" --argjson access "$access" '
      .containerEnv=$env | .mounts=(.mounts+$mounts) | .customizations.cyclestone.generatedRuntimeConfiguration=$metadata | .customizations.cyclestone.runtimeAccess=$access
      | del(.postCreateCommand, .updateContentCommand, .postStartCommand, .postAttachCommand, .initializeCommand, .onCreateCommand, .waitFor)')
  else
    local_config=$(printf '%s' "$portable" | jq -S --argjson metadata "$local_metadata" --argjson env "$container_env" --argjson mounts "$provider_mounts" --argjson access "$access" '
      .containerEnv=$env | .mounts=(.mounts+$mounts) | .customizations.cyclestone.generatedRuntimeConfiguration=$metadata | .customizations.cyclestone.runtimeAccess=$access')
  fi
  printf '%s\n' "$portable" >"$render_dir/portable.json"
  printf '%s\n' "$local_config" >"$render_dir/local.json"
  printf '%s\n' "$sources" | jq -S . >"$render_dir/sources.json"
}
runtime_validate_rendered() {
  runtime_validate_generated_file "$render_dir/portable.json" portable
  runtime_validate_generated_file "$render_dir/local.json" local-runtime
  cli_workspace=$render_dir/workspace
  mkdir -p "$cli_workspace/.devcontainer"
  cp "$repo_root/templates/project-devcontainer/.devcontainer/Containerfile" "$cli_workspace/.devcontainer/Containerfile"
  cp "$repo_root/templates/project-devcontainer/.devcontainer/lifecycle.sh" "$cli_workspace/.devcontainer/lifecycle.sh"
  cp "$render_dir/local.json" "$cli_workspace/.devcontainer/devcontainer.json"
  devcontainer read-configuration --workspace-folder "$cli_workspace" --config "$cli_workspace/.devcontainer/devcontainer.json" >/dev/null 2>"$render_dir/devcontainer.err" || runtime_fail E_CLI_VALIDATE 'Dev Container CLI rejected generated configuration'
}
runtime_prepare_render() {
  runtime_require_tools
  runtime_validate_paths
  runtime_validate_template
  runtime_validate_request
  runtime_collect
  runtime_test_fault after-validation
  runtime_render
  runtime_test_fault after-render
  runtime_validate_rendered
}
