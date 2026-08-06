#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
permissions=$repo_root/scripts/devcontainer-permissions.sh
umask 077
fail() { printf 'ERROR %s: %s\n' "$1" "$2" >&2; exit 1; }
sha256_text() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
podman_cmd() {
  if test -n "${CYCLESTONE_ENGINE_HOME:-}"; then case "$CYCLESTONE_ENGINE_HOME" in /*) :;; *) fail E_ENGINE_HOME 'CYCLESTONE_ENGINE_HOME must be absolute';; esac; env HOME="$CYCLESTONE_ENGINE_HOME" podman "$@"
  else podman "$@"; fi
}
plain_dir() { test ! -L "$1" && test -d "$1" && test "$(stat -c %u "$1")" = "$(id -u)"; }
plain_file() { test ! -L "$1" && test -f "$1" && test "$(stat -c %u "$1")" = "$(id -u)"; }

require_tools() {
  for tool in jq realpath stat id sha256sum awk flock mktemp cp chmod mv sync find date podman grep mkdir dirname wc rm env; do
    command -v "$tool" >/dev/null 2>&1 || fail E_TOOL_MISSING "required host tool is unavailable: $tool"
  done
}
data_setup() {
  if test -n "${CYCLESTONE_DATA_DIR:-}"; then data_root=$CYCLESTONE_DATA_DIR
  elif test -n "${XDG_DATA_HOME:-}"; then data_root=$XDG_DATA_HOME/cyclestone
  else test -n "${HOME:-}" || fail E_STATE_LOCATION 'HOME, XDG_DATA_HOME, or CYCLESTONE_DATA_DIR is required'; data_root=$HOME/.local/share/cyclestone; fi
  case "$data_root" in /*) :;; *) fail E_STATE_LOCATION 'Cyclestone data directory must be absolute';; esac
  if test -e "$data_root" || test -L "$data_root"; then plain_dir "$data_root" || fail E_STATE_UNSAFE 'data directory must be a current-user directory, not a link'; test "$(stat -c %a "$data_root")" = 700 || fail E_STATE_PERMISSIONS 'data directory mode must be 0700'
  else mkdir -p -- "$data_root"; chmod 700 -- "$data_root"; fi
  credential_root=$data_root/provider-credentials-v1
  if test -e "$credential_root" || test -L "$credential_root"; then plain_dir "$credential_root" || fail E_STATE_UNSAFE 'credential state must be a current-user directory, not a link'; test "$(stat -c %a "$credential_root")" = 700 || fail E_STATE_PERMISSIONS 'credential directory mode must be 0700'
  else mkdir -m 700 -- "$credential_root"; fi
  credential_root=$(realpath -e -- "$credential_root")
  lock=$credential_root/state.lock
  if test -e "$lock" || test -L "$lock"; then plain_file "$lock" || fail E_STATE_UNSAFE 'credential lock must be a current-user regular file'; test "$(stat -c %a "$lock")" = 600 || fail E_STATE_PERMISSIONS 'credential lock mode must be 0600'
  else : >"$lock"; chmod 600 -- "$lock"; fi
}
validate_metadata() {
  file=$1
  jq -e '
    def sha: type=="string" and test("^[0-9a-f]{64}$");
    . as $m |
    type=="object" and (keys|sort)==["container_destination","grant_id","identity_fingerprint","mode","project_path","provider_id","request_fingerprint","sessions","source_device","source_inode","source_path","store_file","strategy","version"]
    and .version==1 and (.grant_id|sha) and (.identity_fingerprint|sha) and (.request_fingerprint|sha)
    and (.provider_id|type=="string" and test("^[a-z][a-z0-9-]{1,62}[a-z0-9]$"))
    and (["read-only","read-write","environment","host-service"]|index($m.mode)!=null)
    and (["direct-file-mount","isolated-store","runtime-environment","host-service"]|index($m.strategy)!=null)
    and (.project_path|type=="string" and startswith("/"))
    and (($m.source_path==null and $m.source_device==null and $m.source_inode==null) or (($m.source_path|type=="string" and startswith("/")) and ($m.source_device|type=="number") and ($m.source_inode|type=="number")))
    and (.store_file==null or (.store_file|type=="string" and startswith("/"))) and (.container_destination==null or (.container_destination|type=="string" and startswith("/")))
    and (.sessions|type=="array" and ([.[].id]|length==(unique|length)) and all(.[];(keys|sort)==["container_id","id","started_at"] and (.id|sha) and (.container_id|test("^[0-9a-f]{12,64}$")) and (.started_at|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))))
  ' "$file" >/dev/null 2>&1 || fail E_STATE_SCHEMA 'credential state metadata is invalid'
}
validate_metadata_context() {
  file=$1; expected_source=${source_path:-}; expected_store=${store_file:-}; expected_destination=${destination:-}
  jq -e --arg grant "$grant_id" --arg identity "$identity_fingerprint" --arg request "$request_fingerprint" \
    --arg provider "$provider_id" --arg mode "$mode" --arg strategy "$strategy" --arg project "$project_path" \
    --arg source "$expected_source" --arg store "$expected_store" --arg destination "$expected_destination" '
    .grant_id==$grant and .identity_fingerprint==$identity and .request_fingerprint==$request
    and .provider_id==$provider and .mode==$mode and .strategy==$strategy and .project_path==$project
    and .source_path==(if $source=="" then null else $source end)
    and .store_file==(if $store=="" then null else $store end)
    and .container_destination==(if $destination=="" then null else $destination end)
  ' "$file" >/dev/null 2>&1 || fail E_STATE_INTEGRITY 'credential state does not match the freshly authorized plan'
  if test -n "$expected_source"; then
    test "$(stat -c %d "$expected_source")" = "$(jq -r .source_device "$file")" \
      && test "$(stat -c %i "$expected_source")" = "$(jq -r .source_inode "$file")" \
      || fail E_SOURCE_CHANGED 'host credential source changed since import; revoke and prepare a fresh approval-bound store'
  fi
}
test_fault() {
  test "${CYCLESTONE_CREDENTIAL_TESTING:-0}" = 1 || return 0
  test "${CYCLESTONE_CREDENTIAL_FAULT:-}" != "$1" || fail "$2" "$3"
}
write_metadata() {
  content=$1; directory=$2; output=$directory/metadata.json
  tmp=$(mktemp "$directory/.metadata.XXXXXX") || fail E_STATE_WRITE 'cannot create same-filesystem metadata temporary file'
  trap 'rm -f -- "${tmp:-}"' EXIT HUP INT TERM
  printf '%s\n' "$content" >"$tmp"; chmod 600 -- "$tmp"; validate_metadata "$tmp"
  sync -f "$tmp" >/dev/null 2>&1 || fail E_STATE_WRITE 'cannot fsync credential metadata'
  mv -f -- "$tmp" "$output"; tmp=; sync -f "$directory" >/dev/null 2>&1 || fail E_STATE_WRITE 'cannot fsync credential state directory'; trap - EXIT HUP INT TERM
}
validate_credential() {
  provider=$1; file=$2
  plain_file "$file" || fail E_IMPORT_UNSAFE 'credential source must be a current-user regular file, not a link'
  test "$(stat -c %a "$file")" = 600 || fail E_CREDENTIAL_PERMISSIONS 'credential file mode must be 0600'
  case "$provider" in
    codex) jq -e 'type=="object" and length>0 and (has("tokens") or has("OPENAI_API_KEY") or has("auth_mode"))' "$file" >/dev/null 2>&1 || fail E_CREDENTIAL_FORMAT 'Codex requires a reviewed file-backed auth.json; keyring-only or unknown formats are unsupported';;
    opencode) jq -e 'type=="object" and length>0 and all(to_entries[];.value|type=="object")' "$file" >/dev/null 2>&1 || fail E_CREDENTIAL_FORMAT 'OpenCode auth.json has an unsupported format';;
    *) fail E_CREDENTIAL_FORMAT 'this provider has no file credential format';;
  esac
}
expand_source() {
  template=$1; test -n "${HOME:-}" || fail E_CREDENTIAL_MISSING 'HOME is required to locate the reviewed credential file'
  case "$template" in
    '${HOME}/'*) source_candidate=${HOME}${template#\$\{HOME\}};;
    *) fail E_PLAN_INVALID 'authorized plan contains an undeclared credential source';;
  esac
  test -e "$source_candidate" || fail E_CREDENTIAL_MISSING 'the reviewed provider auth.json is missing; configure file-backed authentication first'
  test ! -L "$source_candidate" || fail E_IMPORT_UNSAFE 'credential source must not be a symbolic link'
  source_path=$(realpath -e -- "$source_candidate") || fail E_IMPORT_UNSAFE 'credential source cannot be canonicalized'
  test "$source_path" = "$source_candidate" || fail E_IMPORT_UNSAFE 'credential source path changed during canonicalization'
}
authorized_context() {
  test "${SAFE_MODE:-false}" != true || fail E_SAFE_MODE_DENIED 'host provider credential grants are blocked in safe mode'
  test "$#" -eq 4 || fail E_USAGE 'expected PROJECT_ROOT REQUEST_FILE PROVIDER_ID PLATFORM'
  project_root=$1; request_file=$2; provider_id=$3; platform=$4
  authorization=$($permissions authorize "$project_root" "$request_file" "$provider_id" "$platform") || exit $?
  printf '%s' "$authorization" | jq -e '.authorized==true and .decision=="always" and .authorization_version==1 and .plan.plan_version==2' >/dev/null 2>&1 || fail E_AUTHORIZATION_INVALID 'fresh authorization result is invalid'
  identity_fingerprint=$(printf '%s' "$authorization" | jq -r .identity_fingerprint)
  request_fingerprint=$(printf '%s' "$authorization" | jq -r .request_fingerprint)
  project_path=$(printf '%s' "$authorization" | jq -r .identity.path)
  plan=$(printf '%s' "$authorization" | jq -S -c .plan)
  strategy=$(printf '%s' "$plan" | jq -r .credential_adapter.strategy)
  mode=$(printf '%s' "$plan" | jq -r .mode)
  grant_id=$(sha256_text "$identity_fingerprint:$request_fingerprint")
  state_dir=$credential_root/$grant_id
  metadata=$state_dir/metadata.json
}
validate_host_service_endpoint() {
  endpoint=$1
  case "$endpoint" in
    http://*) scheme=http; raw_host_port=${endpoint#http://} ;;
    https://*) scheme=https; raw_host_port=${endpoint#https://} ;;
    tcp://*) scheme=http; raw_host_port=${endpoint#tcp://} ;;
    *) scheme=http; raw_host_port=$endpoint ;;
  esac
  raw_host_port=${raw_host_port%%/*}

  case "$raw_host_port" in
    *:*) target_host=${raw_host_port%%:*}; target_port=${raw_host_port##*:} ;;
    *) target_host=$raw_host_port; target_port=11434 ;;
  esac

  case "$target_port" in
    *[!0-9]*) fail E_PORT_DISALLOWED "host-service port '$target_port' is invalid" ;;
  esac
  if test "$target_port" -lt 1024 || test "$target_port" -gt 65535; then
    fail E_PORT_DISALLOWED "host-service port $target_port is outside allowlisted range (1024-65535)"
  fi

  case "$target_host" in
    127.0.0.1|localhost|::1|host.containers.internal|host.docker.internal) ;;
    *)
      if test "$scheme" = http; then
        echo "WARNING: Non-loopback HTTP host-service endpoint '$endpoint' transmits unencrypted plaintext across network boundaries." >&2
      fi
      ;;
  esac

  resolved_host=$target_host
  if test "$target_host" = "host.containers.internal"; then
    if getent hosts host.containers.internal >/dev/null 2>&1; then
      resolved_host=host.containers.internal
    else
      resolved_host="127.0.0.1"
    fi
  fi

  if test "${CYCLESTONE_SKIP_HOST_SERVICE_PROBE:-0}" != "1"; then
    probe_ok=false
    if command -v socat >/dev/null 2>&1; then
      if socat -T 2 TCP:"$resolved_host":"$target_port" STDIN >/dev/null 2>&1; then
        probe_ok=true
      fi
    elif command -v nc >/dev/null 2>&1; then
      if nc -z -w 2 "$resolved_host" "$target_port" >/dev/null 2>&1; then
        probe_ok=true
      fi
    elif (echo > "/dev/tcp/$resolved_host/$target_port") >/dev/null 2>&1; then
      probe_ok=true
    fi

    if test "$probe_ok" = false; then
      fail E_HOST_SERVICE_UNREACHABLE "host-service endpoint '$endpoint' is unreachable at $resolved_host:$target_port"
    fi
  fi
}

validate_mount_safety() {
  source=$1
  dest=${2:-}
  case "$source" in
    *.sock|*docker.sock*|*podman.sock*)
      fail E_PROHIBITED_MOUNT 'direct mounting of host container engine daemon sockets is explicitly prohibited' ;;
  esac
  case "$dest" in
    *.sock|*docker.sock*|*podman.sock*)
      fail E_PROHIBITED_MOUNT 'direct mounting of host container engine daemon sockets is explicitly prohibited' ;;
  esac
  if test -e "$source" && test -S "$source"; then
    fail E_PROHIBITED_MOUNT 'direct mounting of host container engine daemon sockets is explicitly prohibited'
  fi

  case "$source" in
    *.ollama*|*/models/*|*/models|*huggingface*)
      fail E_PROHIBITED_MOUNT 'direct mounting of raw model data directories is explicitly prohibited' ;;
  esac
  case "$dest" in
    *.ollama*|*/models/*|*/models|*huggingface*)
      fail E_PROHIBITED_MOUNT 'direct mounting of raw model data directories is explicitly prohibited' ;;
  esac
}

check_environment() {
  printf '%s' "$plan" | jq -r '.environment_names[]' | while IFS= read -r name; do
    case "$name" in [A-Z]*[A-Z0-9]) :;; *) fail E_PLAN_INVALID 'authorized plan contains an unapproved environment name';; esac
    eval "present=\${$name+x}"
    test "$present" = x || fail E_ENV_MISSING "required runtime environment name is not set: $name"
    if test "$name" = "OLLAMA_HOST"; then
      eval "val=\${$name}"
      test -n "$val" || val=$(printf '%s' "$plan" | jq -r '.host_service.default_endpoint // "http://host.containers.internal:11434"')
      validate_host_service_endpoint "$val"
    fi
  done
}
ensure_state_dir() {
  if test -e "$state_dir" || test -L "$state_dir"; then plain_dir "$state_dir" || fail E_STATE_UNSAFE 'provider state must be a current-user directory, not a link'; test "$(stat -c %a "$state_dir")" = 700 || fail E_STATE_PERMISSIONS 'provider state mode must be 0700'
  else mkdir -m 700 -- "$state_dir"; fi
}
assert_isolated_contents() {
  isolated=$state_dir/isolated
  plain_dir "$isolated" || fail E_IMPORT_UNSAFE 'isolated store must be a current-user directory, not a link'
  test "$(stat -c %a "$isolated")" = 700 || fail E_STATE_PERMISSIONS 'isolated store mode must be 0700'
  count=$(find "$isolated" -mindepth 1 -maxdepth 1 -printf '%f\n' | wc -l)
  test "$count" -eq 1 && test -f "$isolated/auth.json" && test ! -L "$isolated/auth.json" || fail E_SYNC_INVALID 'isolated store contains an undeclared file or unsafe type'
  validate_credential "$provider_id" "$isolated/auth.json"
}
prepare_locked() {
  source_path=; source_device=null; source_inode=null; store_file=; destination=$(printf '%s' "$plan" | jq -r '.credential_adapter.container_destination // empty')
  case "$strategy" in
    runtime-environment|host-service) check_environment;;
    direct-file-mount)
      template=$(printf '%s' "$plan" | jq -r '.credential_adapter.source_files[0]'); expand_source "$template"; validate_credential "$provider_id" "$source_path"
      validate_mount_safety "$source_path" "$destination"
      source_device=$(stat -c %d "$source_path"); source_inode=$(stat -c %i "$source_path"); store_file=$source_path;;
    isolated-store)
      template=$(printf '%s' "$plan" | jq -r '.credential_adapter.source_files[0]'); expand_source "$template"; validate_credential "$provider_id" "$source_path"
      validate_mount_safety "$source_path" "$destination"
      source_device=$(stat -c %d "$source_path"); source_inode=$(stat -c %i "$source_path")
      if ! test -e "$state_dir" && ! test -L "$state_dir"; then
        stage=$(mktemp -d "$credential_root/.import.XXXXXX") || fail E_STATE_WRITE 'cannot create isolated-store staging directory'; chmod 700 "$stage"
        trap 'rm -rf -- "${stage:-}"' EXIT HUP INT TERM
        mkdir -m 700 "$stage/isolated"; cp --no-dereference -- "$source_path" "$stage/isolated/auth.json"; chmod 600 "$stage/isolated/auth.json"; validate_credential "$provider_id" "$stage/isolated/auth.json"
        test_fault import-after-copy E_STATE_WRITE 'injected import failure after credential copy'
        sync -f "$stage/isolated/auth.json" >/dev/null 2>&1 || fail E_STATE_WRITE 'cannot fsync imported credential'
        test_fault import-after-file-fsync E_STATE_WRITE 'injected import failure after credential file fsync'
        sync -f "$stage/isolated" >/dev/null 2>&1 || fail E_STATE_WRITE 'cannot fsync isolated staging directory'
        test_fault import-after-fsync E_STATE_WRITE 'injected import failure after staging fsync'
        test_fault import-before-rename E_STATE_WRITE 'injected import failure before atomic state publication'
        mv -- "$stage" "$state_dir"; stage=; sync -f "$credential_root" >/dev/null 2>&1 || fail E_STATE_WRITE 'cannot fsync credential root'; trap - EXIT HUP INT TERM
      fi
      assert_isolated_contents; store_file=$state_dir/isolated/auth.json;;
    *) fail E_PLAN_INVALID 'authorized credential strategy is unsupported';;
  esac
  ensure_state_dir
  if test -e "$metadata" || test -L "$metadata"; then plain_file "$metadata" || fail E_STATE_UNSAFE 'credential metadata must be a current-user regular file, not a link'; test "$(stat -c %a "$metadata")" = 600 || fail E_STATE_PERMISSIONS 'credential metadata mode must be 0600'; validate_metadata "$metadata"; validate_metadata_context "$metadata"; sessions=$(jq -c .sessions "$metadata")
  else sessions='[]'; fi
  # Drop only sessions whose tracked container no longer exists or runs.
  kept='[]'
  printf '%s' "$sessions" | jq -c '.[]' | while IFS= read -r session; do :; done
  for cid in $(printf '%s' "$sessions" | jq -r '.[].container_id'); do
    if podman_cmd container exists "$cid" >/dev/null 2>&1 && test "$(podman_cmd inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" = true; then kept=$(printf '%s' "$kept" | jq -S -c --argjson s "$(printf '%s' "$sessions" | jq -c --arg c "$cid" '.[]|select(.container_id==$c)')" '.+[$s]'); fi
  done
  metadata_json=$(jq -S -c -n --arg grant "$grant_id" --arg identity "$identity_fingerprint" --arg request "$request_fingerprint" --arg provider "$provider_id" --arg mode "$mode" --arg strategy "$strategy" --arg project "$project_path" --arg source "${source_path:-}" --arg store "${store_file:-}" --arg dest "$destination" --argjson device "$source_device" --argjson inode "$source_inode" --argjson sessions "$kept" \
    '{version:1,grant_id:$grant,identity_fingerprint:$identity,request_fingerprint:$request,provider_id:$provider,mode:$mode,strategy:$strategy,project_path:$project,source_path:(if $source=="" then null else $source end),source_device:$device,source_inode:$inode,store_file:(if $store=="" then null else $store end),container_destination:(if $dest=="" then null else $dest end),sessions:$sessions}')
  write_metadata "$metadata_json" "$state_dir"
  runtime_source=${store_file:-}; runtime_destination=$destination
  if test "$strategy" = isolated-store; then runtime_source=$(dirname -- "$store_file"); runtime_destination=$(dirname -- "$destination"); fi
  jq -S -c -n --arg provider "$provider_id" --arg strategy "$strategy" --arg mode "$mode" --arg source "$runtime_source" --arg destination "$runtime_destination" --argjson names "$(printf '%s' "$plan" | jq -c .environment_names)" --argjson service "$(printf '%s' "$plan" | jq -c .host_service)" \
    '{credential_runtime_version:1,provider_id:$provider,strategy:$strategy,mode:$mode,environment_names:$names,mount:(if $source=="" then null else {source:$source,destination:$destination,access:$mode} end),host_service:$service}'
}
prepare() {
  data_setup; authorized_context "$@"; exec 8<>"$lock"; flock -x 8; prepare_locked
}
sync_store() {
  data_setup; authorized_context "$@"; test "$strategy" = isolated-store || fail E_SYNC_FORBIDDEN 'synchronization is supported only for an approved isolated store'
  exec 8<>"$lock"; flock -x 8; test -f "$metadata" || fail E_STATE_MISSING 'isolated credential state has not been prepared'; validate_metadata "$metadata"; assert_isolated_contents
  template=$(printf '%s' "$plan" | jq -r '.credential_adapter.source_files[0]'); expand_source "$template"; validate_credential "$provider_id" "$source_path"
  store_file=$state_dir/isolated/auth.json; destination=$(printf '%s' "$plan" | jq -r '.credential_adapter.container_destination // empty'); validate_metadata_context "$metadata"
  target_dir=$(dirname -- "$source_path"); temp=$(mktemp "$target_dir/.auth.json.XXXXXX") || fail E_SYNC_WRITE 'cannot create same-filesystem synchronization file'; trap 'rm -f -- "${temp:-}"' EXIT HUP INT TERM
  cp --no-dereference -- "$state_dir/isolated/auth.json" "$temp"; chmod 600 "$temp"; validate_credential "$provider_id" "$temp"
  test_fault sync-after-copy E_SYNC_WRITE 'injected synchronization failure after credential copy'
  sync -f "$temp" >/dev/null 2>&1 || fail E_SYNC_WRITE 'cannot fsync synchronized credential'
  test_fault sync-after-fsync E_SYNC_WRITE 'injected synchronization failure after credential fsync'
  test_fault sync-before-rename E_SYNC_WRITE 'injected synchronization failure before atomic replacement'
  mv -f -- "$temp" "$source_path"; temp=; sync -f "$target_dir" >/dev/null 2>&1 || fail E_SYNC_WRITE 'cannot fsync credential source directory'; trap - EXIT HUP INT TERM
  updated=$(jq -S -c --argjson dev "$(stat -c %d "$source_path")" --argjson ino "$(stat -c %i "$source_path")" '.source_device=$dev|.source_inode=$ino' "$metadata"); write_metadata "$updated" "$state_dir"
  printf '%s\n' '{"synchronized":true}'
}
start_session() {
  test "$#" -eq 5 || fail E_USAGE 'start PROJECT_ROOT REQUEST_FILE PROVIDER_ID PLATFORM IMAGE'
  image=$5; data_setup; authorized_context "$1" "$2" "$3" "$4"; exec 8<>"$lock"; flock -x 8; runtime=$(prepare_locked)
  session_id=$(sha256_text "$grant_id:$(date -u +%s%N):$$"); name=cyclestone-credential-${session_id%????????????????????????????????????????????????}
  set -- podman_cmd run -d --name "$name" --user 1000:1000 --userns=keep-id:uid=1000,gid=1000 --security-opt=no-new-privileges
  for env_name in $(printf '%s' "$runtime" | jq -r '.environment_names[]'); do set -- "$@" --env "$env_name"; done
  mount_source=$(printf '%s' "$runtime" | jq -r '.mount.source // empty'); mount_destination=$(printf '%s' "$runtime" | jq -r '.mount.destination // empty')
  if test -n "$mount_source"; then case "$mount_source$mount_destination" in *','*|*':'*) fail E_PATH_UNSUPPORTED 'credential mount paths containing comma or colon are unsupported';; esac; mount_access=$(printf '%s' "$runtime" | jq -r '.mount.access'); if test "$mount_access" = read-only; then set -- "$@" --mount "type=bind,src=$mount_source,dst=$mount_destination,ro=true,relabel=private"; else set -- "$@" --mount "type=bind,src=$mount_source,dst=$mount_destination,rw=true,relabel=private"; fi; fi
  set -- "$@" "$image" sleep infinity
  # Never let the long-lived container monitor inherit the credential-state lock.
  container_id=$("$@" 8>&-) || fail E_SESSION_START 'rootless Podman could not start the credential session'
  started=$(date -u +%Y-%m-%dT%H:%M:%SZ); current=$(jq -S -c --arg id "$session_id" --arg cid "$container_id" --arg now "$started" '.sessions += [{id:$id,container_id:$cid,started_at:$now}]' "$metadata")
  if ! write_metadata "$current" "$state_dir"; then podman_cmd rm -f -t 0 "$container_id" >/dev/null 2>&1 || :; exit 1; fi
  jq -S -c -n --arg id "$session_id" --arg cid "$container_id" '{session_id:$id,container_id:$cid}'
}
find_session() {
  wanted=$1; printf '%s' "$wanted" | grep -Eq '^[0-9a-f]{64}$' || fail E_SESSION_ID 'session ID must be a SHA-256 value'
  found=
  for candidate in "$credential_root"/[0-9a-f]*; do test -f "$candidate/metadata.json" || continue; validate_metadata "$candidate/metadata.json"; if jq -e --arg id "$wanted" '.sessions[]|select(.id==$id)' "$candidate/metadata.json" >/dev/null; then test -z "$found" || fail E_STATE_SCHEMA 'duplicate session ID'; found=$candidate; fi; done
  test -n "$found" || fail E_SESSION_MISSING 'tracked credential session does not exist'; state_dir=$found; metadata=$found/metadata.json; container_id=$(jq -r --arg id "$wanted" '.sessions[]|select(.id==$id)|.container_id' "$metadata")
}
stop_session() {
  data_setup; exec 8<>"$lock"; flock -x 8; find_session "$1"; podman_cmd rm -f -t 0 "$container_id" >/dev/null 2>&1 || :
  updated=$(jq -S -c --arg id "$1" '.sessions|=map(select(.id!=$id))' "$metadata"); write_metadata "$updated" "$state_dir"; printf '%s\n' '{"stopped":true}'
}
exec_session() {
  sid=$1; shift; test "$#" -gt 0 || fail E_USAGE 'exec SESSION_ID COMMAND [ARG...]'; data_setup; exec 8<>"$lock"; flock -x 8; find_session "$sid"; flock -u 8
  podman_cmd exec "$container_id" "$@"
}
revoke_state() {
  selector=$1; wanted=$2; data_setup; exec 8<>"$lock"; flock -x 8
  targets=
  for candidate in "$credential_root"/[0-9a-f]*; do test -f "$candidate/metadata.json" || continue; validate_metadata "$candidate/metadata.json"; if jq -e --arg key "$selector" --arg value "$wanted" 'getpath([$key])==$value' "$candidate/metadata.json" >/dev/null; then
      for cid in $(jq -r '.sessions[].container_id' "$candidate/metadata.json"); do if podman_cmd container exists "$cid" >/dev/null 2>&1 && test "$(podman_cmd inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" = true; then fail E_ACTIVE_SESSION 'stop every tracked provider session before revocation'; fi; done
      targets="$targets $candidate"
    fi; done
  for target in $targets; do case "$target" in "$credential_root"/[0-9a-f]*) rm -rf -- "$target";; *) fail E_STATE_UNSAFE 'refusing credential deletion outside the state root';; esac; done
  sync -f "$credential_root" >/dev/null 2>&1 || fail E_STATE_WRITE 'cannot fsync credential state after revocation'
}
list_state() {
  data_setup; exec 8<>"$lock"; flock -x 8; first=true; printf '{"version":1,"states":['
  for candidate in "$credential_root"/[0-9a-f]*; do test -f "$candidate/metadata.json" || continue; validate_metadata "$candidate/metadata.json"; $first || printf ','; first=false; jq -S -c '{grant_id,identity_fingerprint,provider_id,mode,strategy,project_path,active_sessions:(.sessions|length)}' "$candidate/metadata.json"; done
  printf ']}\n'
}

require_tools
command=${1:-}; test -n "$command" || fail E_USAGE 'usage: provider-credentials.sh COMMAND ...'; shift || :
case "$command" in
  prepare) test "$#" -eq 4 || fail E_USAGE 'prepare PROJECT_ROOT REQUEST_FILE PROVIDER_ID PLATFORM'; prepare "$@";;
  synchronize) test "$#" -eq 4 || fail E_USAGE 'synchronize PROJECT_ROOT REQUEST_FILE PROVIDER_ID PLATFORM'; sync_store "$@";;
  start) start_session "$@";;
  exec) test "$#" -ge 2 || fail E_USAGE 'exec SESSION_ID COMMAND [ARG...]'; exec_session "$@";;
  stop) test "$#" -eq 1 || fail E_USAGE 'stop SESSION_ID'; stop_session "$1";;
  list) test "$#" -eq 0 || fail E_USAGE 'list takes no arguments'; list_state;;
  revoke-grant) test "$#" -eq 1 || fail E_USAGE 'revoke-grant GRANT_ID'; revoke_state grant_id "$1";;
  revoke-project) test "$#" -eq 1 || fail E_USAGE 'revoke-project IDENTITY_FINGERPRINT'; revoke_state identity_fingerprint "$1";;
  *) fail E_USAGE 'command must be prepare, synchronize, start, exec, stop, list, revoke-grant, or revoke-project';;
esac
