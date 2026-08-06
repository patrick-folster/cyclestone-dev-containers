#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
resolver=$repo_root/scripts/resolve-providers.sh
credentials=$repo_root/scripts/provider-credentials.sh
registry=$repo_root/providers/registry.json
umask 077

fail() { printf 'ERROR %s: %s\n' "$1" "$2" >&2; exit 1; }
require_tools() {
  for tool in realpath stat git jq sha256sum flock mktemp mv chmod date id sync awk sort grep mkdir; do
    command -v "$tool" >/dev/null 2>&1 || fail E_TOOL_MISSING "required host tool is unavailable: $tool"
  done
}
sha256_text() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
is_within() { case "$1/" in "$2/"*) return 0;; *) return 1;; esac; }
assert_plain_path() {
  path=$1; kind=$2
  test ! -L "$path" || fail E_STORE_UNSAFE "$kind must not be a symbolic link"
  if test "$kind" = directory; then test -d "$path" || fail E_STORE_UNSAFE "$kind is not a directory"
  else test -f "$path" || fail E_STORE_UNSAFE "$kind is not a regular file"; fi
  test "$(stat -c %u "$path")" = "$(id -u)" || fail E_STORE_UNSAFE "$kind is not owned by the current user"
}
assert_mode() {
  path=$1; expected=$2; kind=$3
  test "$(stat -c %a "$path")" = "$expected" || fail E_STORE_PERMISSIONS "$kind mode must be 0$expected"
}

identity_json() {
  supplied=$1
  test -d "$supplied" || fail E_PROJECT_IDENTITY 'project root is not a directory'
  root=$(realpath -e -- "$supplied") || fail E_PROJECT_IDENTITY 'project root cannot be canonicalized'
  test -d "$root" || fail E_PROJECT_IDENTITY 'canonical project root is not a directory'
  root_dev=$(stat -c %d "$root") || fail E_PROJECT_IDENTITY 'project filesystem identity is unavailable'
  root_ino=$(stat -c %i "$root") || fail E_PROJECT_IDENTITY 'project filesystem identity is unavailable'
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    top=$(realpath -e -- "$(git -C "$root" rev-parse --show-toplevel)") || fail E_PROJECT_IDENTITY 'Git worktree root is ambiguous'
    test "$top" = "$root" || fail E_PROJECT_IDENTITY 'project root must be the Git worktree root'
    test ! -L "$root/.git" || fail E_PROJECT_IDENTITY 'symbolic-link Git metadata is unsupported'
    git_dir=$(realpath -e -- "$(git -C "$root" rev-parse --absolute-git-dir)") || fail E_PROJECT_IDENTITY 'Git directory cannot be canonicalized'
    common_dir_raw=$(git -C "$root" rev-parse --git-common-dir) || fail E_PROJECT_IDENTITY 'Git common directory is unavailable'
    case "$common_dir_raw" in /*) common_dir=$common_dir_raw;; *) common_dir=$root/$common_dir_raw;; esac
    common_dir=$(realpath -e -- "$common_dir") || fail E_PROJECT_IDENTITY 'Git common directory cannot be canonicalized'
    assert_plain_path "$git_dir" directory
    assert_plain_path "$common_dir" directory
    object_format=$(git -C "$root" rev-parse --show-object-format 2>/dev/null) || fail E_PROJECT_IDENTITY 'Git object format is unavailable'
    roots=$(git -C "$root" rev-list --max-parents=0 --all 2>/dev/null | LC_ALL=C sort | sha256sum | awk '{print $1}') || fail E_PROJECT_IDENTITY 'Git root evidence is unavailable'
    jq -S -c -n --arg path "$root" --argjson device "$root_dev" --argjson inode "$root_ino" \
      --arg git_dir "$git_dir" --argjson git_device "$(stat -c %d "$git_dir")" --argjson git_inode "$(stat -c %i "$git_dir")" \
      --arg common_dir "$common_dir" --argjson common_device "$(stat -c %d "$common_dir")" --argjson common_inode "$(stat -c %i "$common_dir")" \
      --arg object_format "$object_format" --arg roots "$roots" \
      '{identity_version:1,kind:"git-worktree",path:$path,filesystem:{device:$device,inode:$inode},git:{git_dir:$git_dir,git_dir_filesystem:{device:$git_device,inode:$git_inode},common_dir:$common_dir,common_dir_filesystem:{device:$common_device,inode:$common_inode},object_format:$object_format,root_set_sha256:$roots}}'
  else
    jq -S -c -n --arg path "$root" --argjson device "$root_dev" --argjson inode "$root_ino" \
      '{identity_version:1,kind:"directory",path:$path,filesystem:{device:$device,inode:$inode}}'
  fi
}

validate_store_file() {
  candidate_store=$1
  jq -e --slurpfile registry "$registry" '
    def exact($keys): type=="object" and (keys_unsorted|sort)==($keys|sort);
    def text: type=="string" and length>0;
    def fsid: exact(["device","inode"])
      and (.device|type=="number" and .>=0 and floor==.)
      and (.inode|type=="number" and .>=1 and floor==.);
    def identity:
      if .kind=="directory" then exact(["identity_version","kind","path","filesystem"])
        and .identity_version==1 and (.path|type=="string" and startswith("/")) and (.filesystem|fsid)
      elif .kind=="git-worktree" then exact(["identity_version","kind","path","filesystem","git"])
        and .identity_version==1 and (.path|type=="string" and startswith("/")) and (.filesystem|fsid)
        and (.git as $g | ($g|exact(["git_dir","git_dir_filesystem","common_dir","common_dir_filesystem","object_format","root_set_sha256"]))
          and ($g.git_dir|type=="string" and startswith("/")) and ($g.common_dir|type=="string" and startswith("/"))
          and ($g.git_dir_filesystem|fsid) and ($g.common_dir_filesystem|fsid)
          and (["sha1","sha256"]|index($g.object_format)!=null) and ($g.root_set_sha256|type=="string" and test("^[0-9a-f]{64}$")))
      else false end;
    def none: exact(["kind"]) and .kind=="none";
    def adapter: . as $a | exact(["access","adapter_version","backup_policy","container_destination","directory_mode","environment_names","failure_codes","file_mode","import_behavior","mode","refresh_behavior","revocation_behavior","source_files","strategy","synchronization"])
      and $a.adapter_version==1 and (["direct-file-mount","isolated-store","runtime-environment","host-service"]|index($a.strategy)!=null)
      and (["read-only","read-write","environment","host-service"]|index($a.mode)!=null) and $a.access==$a.mode
      and (.source_files|type=="array" and length==(unique|length)) and (.environment_names|type=="array" and length==(unique|length))
      and (.import_behavior|text) and (.synchronization|text) and (.refresh_behavior|text) and (.revocation_behavior|text) and (.backup_policy|text)
      and (.failure_codes|type=="array" and length>0 and all(.[];type=="string" and test("^E_[A-Z_]+$")));
    def plan: exact(["credential_adapter","description","display_name","environment_names","filesystem","host_service","mode","plan_version","platform","provider_id","registry_version","required_cli","security_guidance"])
      and .plan_version==2 and .registry_version==($registry[0].registry_version) and .platform=="linux"
      and (.provider_id|type=="string" and test("^[a-z][a-z0-9-]+$"))
      and (.display_name|text) and (.description|text)
      and (.mode as $mode | ["read-only","read-write","environment","host-service"]|index($mode)!=null)
      and (.environment_names|type=="array" and length==(unique|length)
        and all(.[];type=="string" and test("^[A-Z][A-Z0-9_]*$")))
      and (.required_cli as $cli | ($cli|exact(["location","name"]))
        and (($cli.location=="none" and $cli.name==null)
          or ((["container","host"]|index($cli.location)!=null) and ($cli.name|text))))
      and (.credential_adapter|adapter) and .credential_adapter.mode==.mode and .credential_adapter.environment_names==.environment_names
      and (.security_guidance|text)
      and (.filesystem as $fs | .host_service as $service |
        if (.mode=="read-only" or .mode=="read-write") then
          ($fs|exact(["access","container_destination","host_source","kind"]))
          and $fs.kind=="file" and $fs.access==.mode
          and ($fs.host_source|text) and ($fs.container_destination|text and startswith("/"))
          and .credential_adapter.source_files==[$fs.host_source] and .credential_adapter.container_destination==$fs.container_destination
          and (.environment_names|length)==0 and ($service|none)
        elif .mode=="environment" then
          ($fs|none) and (.environment_names|length)>0 and ($service|none)
        else ($fs|none) and (.environment_names|length)>0
          and ($service|exact(["authentication","default_endpoint","endpoint_environment","kind","transport"]))
          and $service.kind=="http" and $service.transport=="tcp"
          and ($service.endpoint_environment|text) and ($service.default_endpoint|text) and ($service.authentication|text)
        end)
      and (. as $p | $p.credential_adapter as $a | $p.provider_id as $pid | $p.mode as $pmode |
        any($registry[0].definitions[]; .id==$pid and (
          . as $def | any(.adapters[]; .mode==$pmode and (
            . as $reg_a | $a == $reg_a
            and $p.required_cli == $def.required_cli
            and $p.display_name == $def.display_name
            and $p.description == $def.description
            and $p.security_guidance == $def.security_guidance
            and ($p.host_service == ($def.host_service // {kind:"none"}))
          ))
        )));
    exact(["grants","version"]) and .version==1 and (.grants|type=="array")
    and ([.grants[].id]|length==(unique|length))
    and all(.grants[]; exact(["created_at","decision","id","identity","identity_fingerprint","plan","request_fingerprint"])
      and .decision=="always" and (.id|type=="string" and test("^[0-9a-f]{64}$"))
      and (.identity_fingerprint|type=="string" and test("^[0-9a-f]{64}$"))
      and (.request_fingerprint|type=="string" and test("^[0-9a-f]{64}$"))
      and (.created_at|type=="string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
      and (.identity|identity) and (.plan|plan))
  ' "$candidate_store" >/dev/null 2>&1 || fail E_STORE_SCHEMA 'grant store does not satisfy the closed version-1 schema'

  jq -c '.grants[]' "$candidate_store" | while IFS= read -r record; do
    stored_id=$(printf '%s' "$record" | jq -r .id)
    stored_identity_hash=$(printf '%s' "$record" | jq -r .identity_fingerprint)
    stored_request_hash=$(printf '%s' "$record" | jq -r .request_fingerprint)
    stored_created_at=$(printf '%s' "$record" | jq -r .created_at)
    normalized_created_at=$(date -u -d "$stored_created_at" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || fail E_STORE_SCHEMA 'stored grant timestamp is not a real UTC date-time'
    test "$stored_created_at" = "$normalized_created_at" || fail E_STORE_SCHEMA 'stored grant timestamp is not canonical UTC'
    canonical_identity=$(printf '%s' "$record" | jq -S -c .identity)
    canonical_plan=$(printf '%s' "$record" | jq -S -c .plan)
    computed_identity_hash=$(sha256_text "$canonical_identity")
    computed_request_hash=$(sha256_text "$canonical_plan")
    computed_id=$(sha256_text "$computed_identity_hash:$computed_request_hash")
    test "$stored_identity_hash" = "$computed_identity_hash" || fail E_STORE_INTEGRITY 'stored identity fingerprint does not match its canonical body'
    test "$stored_request_hash" = "$computed_request_hash" || fail E_STORE_INTEGRITY 'stored request fingerprint does not match its canonical body'
    test "$stored_id" = "$computed_id" || fail E_STORE_INTEGRITY 'stored grant ID is not deterministic for its fingerprints'
  done
}

store_setup() {
  if test -n "${CYCLESTONE_DATA_DIR:-}"; then data_root=$CYCLESTONE_DATA_DIR
  elif test -n "${XDG_DATA_HOME:-}"; then data_root=$XDG_DATA_HOME/cyclestone
  else test -n "${HOME:-}" || fail E_STORE_LOCATION 'HOME, XDG_DATA_HOME, or CYCLESTONE_DATA_DIR is required'; data_root=$HOME/.local/share/cyclestone
  fi
  case "$data_root" in /*) :;; *) fail E_STORE_LOCATION 'Cyclestone data directory must be absolute';; esac
  if test -e "$data_root" || test -L "$data_root"; then assert_plain_path "$data_root" directory; assert_mode "$data_root" 700 'data directory'
  else
    mkdir -p -- "$data_root" || fail E_STORE_CREATE 'cannot create Cyclestone data directory'
    chmod 700 -- "$data_root" || fail E_STORE_PERMISSIONS 'cannot set Cyclestone data-directory mode'
  fi
  store_dir=$data_root/provider-permissions-v1
  if test -e "$store_dir" || test -L "$store_dir"; then assert_plain_path "$store_dir" directory; assert_mode "$store_dir" 700 'permission directory'
  else mkdir -m 700 -- "$store_dir" || fail E_STORE_CREATE 'cannot create provider permission directory'; fi
  store_dir=$(realpath -e -- "$store_dir") || fail E_STORE_UNSAFE 'permission directory cannot be canonicalized'
  store_file=$store_dir/grants.json
  lock_file=$store_dir/grants.lock
  if test -e "$lock_file" || test -L "$lock_file"; then assert_plain_path "$lock_file" file; assert_mode "$lock_file" 600 'lock file'
  else : >>"$lock_file"; chmod 600 -- "$lock_file" || fail E_STORE_PERMISSIONS 'cannot set lock-file mode'; fi
  exec 7<>"$lock_file"
  flock -x 7
  if test -e "$store_file" || test -L "$store_file"; then
    assert_plain_path "$store_file" file
    test "$(stat -c %a "$store_file")" = 600 || fail E_STORE_PERMISSIONS 'grant store mode must be 0600'
  else
    printf '%s\n' '{"version":1,"grants":[]}' >"$store_file"
    chmod 600 -- "$store_file"
  fi
  validate_store_file "$store_file"
  flock -u 7
}

assert_store_outside_project() {
  project_path=$(printf '%s' "$1" | jq -r .path)
  if is_within "$store_dir" "$project_path"; then fail E_STORE_LOCATION 'permission state must be outside the project repository'; fi
  if is_within "$project_path" "$store_dir"; then fail E_STORE_LOCATION 'project root must not contain permission state'; fi
}
resolve_context() {
  test "${SAFE_MODE:-false}" != true || fail E_SAFE_MODE_DENIED 'host provider credential grants are blocked in safe mode'
  project_root=$1; request_file=$2; provider_id=$3; platform=$4
  identity=$(identity_json "$project_root")
  identity_fingerprint=$(sha256_text "$identity")
  validate_request "$identity" "$request_file"
  request_file=$canonical_request
  plan=$($resolver "$request_file" "$provider_id" "$platform") || exit $?
  canonical_plan=$(printf '%s' "$plan" | jq -S -c '.') || fail E_PLAN_INVALID 'resolver output is not canonical JSON'
  test "$plan" = "$canonical_plan" || fail E_PLAN_INVALID 'resolver output is not canonical'
  request_fingerprint=$(sha256_text "$plan")
  store_setup
  assert_store_outside_project "$identity"
}
validate_request() {
  request_identity=$1; candidate=$2
  project_path=$(printf '%s' "$request_identity" | jq -r .path)
  test ! -L "$candidate" || fail E_REQUEST_BOUNDARY 'provider request must not be a symbolic link'
  canonical_request=$(realpath -e -- "$candidate") || fail E_REQUEST_BOUNDARY 'provider request cannot be canonicalized'
  is_within "$canonical_request" "$project_path" || fail E_REQUEST_BOUNDARY 'provider request must be inside the project root'
  if test "$(printf '%s' "$request_identity" | jq -r .kind)" = git-worktree; then
    relative_request=${canonical_request#"$project_path"/}
    git -C "$project_path" ls-files --error-unmatch -- "$relative_request" >/dev/null 2>&1 || fail E_REQUEST_UNCOMMITTED 'provider request must be tracked by Git'
    git -C "$project_path" diff --quiet HEAD -- "$relative_request" || fail E_REQUEST_UNCOMMITTED 'provider request must match the committed revision'
  fi
}
revalidate() {
  new_identity=$(identity_json "$project_root")
  validate_request "$new_identity" "$request_file"
  test "$canonical_request" = "$request_file" || fail E_REQUEST_BOUNDARY 'provider request path changed during authorization'
  new_plan=$($resolver "$request_file" "$provider_id" "$platform") || exit $?
  test "$new_identity" = "$identity" || fail E_IDENTITY_CHANGED 'project identity changed during authorization'
  test "$new_plan" = "$plan" || fail E_PLAN_CHANGED 'resolved provider plan changed during authorization'
}
retire_observed_move() {
  updated=$(jq -S -c --argjson current "$identity" '
    .grants |= [.[] | select((.identity.filesystem==$current.filesystem and .identity!=$current)|not)]
  ' "$store_file")
  test "$updated" = "$(jq -S -c . "$store_file")" || write_store "$updated"
}
emit_authorized() {
  jq -M -S -c -n --arg decision "$1" --arg identity_fingerprint "$identity_fingerprint" --arg request_fingerprint "$request_fingerprint" --argjson identity "$identity" --argjson plan "$plan" \
    '{authorization_version:1,authorized:true,decision:$decision,identity_fingerprint:$identity_fingerprint,request_fingerprint:$request_fingerprint,identity:$identity,plan:$plan}'
}
render_prompt() {
  printf '%s\n' 'Cyclestone provider authorization review' >&8
  is_rw=$(printf '%s' "$plan" | jq -r '.mode=="read-write" or .filesystem.access=="read-write"')
  if test "$is_rw" = true; then
    dest=$(printf '%s' "$plan" | jq -r '.filesystem.container_destination // "unknown"')
    prov=$(printf '%s' "$plan" | jq -r '.provider_id')
    printf 'WARNING: Writable provider path requested for provider %s at %s. Isolated credential store will be used; direct writable host mounts are prohibited.\n' "$prov" "$dest" >&8
  fi
  jq -r '
    "Provider: \(.display_name) [\(.provider_id)]", "Description: \(.description)",
    "Platform: \(.platform)", "Access mode: \(.mode)",
    (if .filesystem.kind=="none" then "Source: none\nDestination: none\nFilesystem access: none" else "Source: \(.filesystem.host_source)\nDestination: \(.filesystem.container_destination)\nFilesystem access: \(.filesystem.access)" end),
    "Forwarded variable names: \(if (.environment_names|length)==0 then "none" else (.environment_names|join(", ")) end)",
    (if .host_service.kind=="none" then "Host service: none; transport=none; authentication=none" else "Host service: \(.host_service.default_endpoint) via \(.host_service.transport); authentication=\(.host_service.authentication)\nWarning: this service becomes reachable by untrusted project processes." end),
    "Credential strategy: \(.credential_adapter.strategy)",
    "Import: \(.credential_adapter.import_behavior)", "Synchronization: \(.credential_adapter.synchronization)",
    "Refresh: \(.credential_adapter.refresh_behavior)", "Revocation: \(.credential_adapter.revocation_behavior)",
    "Backup: \(.credential_adapter.backup_policy)", "Security guidance: \(.security_guidance)"' <<EOF >&8
$plan
EOF
  jq -r '"Project identity: \(.kind) \(.path) device=\(.filesystem.device) inode=\(.filesystem.inode)"' <<EOF >&8
$identity
EOF
  if test "$(printf '%s' "$identity" | jq -r .kind)" = git-worktree; then
    jq -r '"Git directory: \(.git.git_dir) device=\(.git.git_dir_filesystem.device) inode=\(.git.git_dir_filesystem.inode)\nGit common directory: \(.git.common_dir) device=\(.git.common_dir_filesystem.device) inode=\(.git.common_dir_filesystem.inode)\nGit evidence: object-format=\(.git.object_format) root-set-sha256=\(.git.root_set_sha256)"' <<EOF >&8
$identity
EOF
  fi
  printf '%s\n' 'Grant duration: [o] allow once; [a] always for this exact project and request; [d] deny' >&8
  printf '%s' 'Decision: ' >&8
}
write_store() {
  content=$1
  tmp=$(mktemp "$store_dir/.grants.XXXXXX") || fail E_STORE_WRITE 'cannot create same-filesystem temporary store'
  trap 'rm -f -- "${tmp:-}"' EXIT HUP INT TERM
  printf '%s\n' "$content" >"$tmp"
  chmod 600 -- "$tmp"
  validate_store_file "$tmp"
  sync -f "$tmp" >/dev/null 2>&1 || fail E_STORE_WRITE 'cannot fsync replacement store'
  mv -f -- "$tmp" "$store_file"
  tmp=
  sync -f "$store_dir" >/dev/null 2>&1 || fail E_STORE_WRITE 'cannot fsync permission directory'
  trap - EXIT HUP INT TERM
}

require_tools
command=${1:-}; test -n "$command" || fail E_USAGE 'usage: devcontainer-permissions.sh COMMAND ...'
shift || :
case "$command" in
  authorize)
    test "$#" -eq 4 || fail E_USAGE 'authorize PROJECT_ROOT REQUEST_FILE PROVIDER_ID PLATFORM'
    resolve_context "$1" "$2" "$3" "$4"
    exec 9<>"$lock_file"; flock -x 9
    revalidate; validate_store_file "$store_file"; retire_observed_move
    matches=$(jq --arg i "$identity_fingerprint" --arg r "$request_fingerprint" --argjson identity "$identity" --argjson plan "$plan" \
      '[.grants[]|select(.identity_fingerprint==$i and .request_fingerprint==$r and .identity==$identity and .plan==$plan)]|length' "$store_file")
    test "$matches" -eq 1 || fail E_APPROVAL_REQUIRED 'run scripts/devcontainer-permissions.sh review PROJECT_ROOT REQUEST_FILE PROVIDER_ID PLATFORM from a terminal'
    emit_authorized always
    ;;
  review)
    test "$#" -eq 4 || fail E_USAGE 'review PROJECT_ROOT REQUEST_FILE PROVIDER_ID PLATFORM'
    resolve_context "$1" "$2" "$3" "$4"
    if test -t 0 && test -t 1; then
      exec 8<>/dev/tty || fail E_INTERACTIVE_REQUIRED 'approval cannot open the controlling terminal'
    else
      fail E_INTERACTIVE_REQUIRED 'approval requires a controlling terminal; use list to inspect existing grants'
    fi
    render_prompt
    IFS= read -r choice <&8 || fail E_DECISION_EOF 'no authorization decision was received'
    choice=$(printf '%s' "$choice" | tr -d '\r')
    case "$choice" in
      d|deny) fail E_DENIED 'provider request denied; no grant was stored';;
      o|once)
        exec 9<>"$lock_file"; flock -x 9; revalidate; validate_store_file "$store_file"; retire_observed_move; emit_authorized once;;
      a|always)
        exec 9<>"$lock_file"; flock -x 9; revalidate; validate_store_file "$store_file"; retire_observed_move
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        grant_id=$(sha256_text "$identity_fingerprint:$request_fingerprint")
        updated=$(jq -S -c --arg id "$grant_id" --arg i "$identity_fingerprint" --arg r "$request_fingerprint" --arg now "$now" --argjson identity "$identity" --argjson plan "$plan" '
          .grants |= ([.[]|select(.id!=$id)] + [{id:$id,identity_fingerprint:$i,request_fingerprint:$r,identity:$identity,plan:$plan,decision:"always",created_at:$now}] | sort_by(.id))' "$store_file")
        write_store "$updated"; emit_authorized always;;
      *) fail E_DECISION_INVALID 'decision must be deny, once, or always';;
    esac
    ;;
  list)
    test "$#" -eq 0 || fail E_USAGE 'list takes no arguments'
    store_setup
    jq -S -c '{version,grants:[.grants[]|{id,decision,created_at,identity_fingerprint,request_fingerprint,project:{kind:.identity.kind,path:.identity.path},request:{provider_id:.plan.provider_id,mode:.plan.mode,platform:.plan.platform}}]}' "$store_file"
    ;;
  revoke)
    test "$#" -eq 1 || fail E_USAGE 'revoke GRANT_ID'
    grant_id=$1; printf '%s' "$grant_id" | grep -Eq '^[0-9a-f]{64}$' || fail E_GRANT_ID 'grant ID must be a SHA-256 value'
    store_setup; exec 9<>"$lock_file"; flock -x 9; validate_store_file "$store_file"
    "$credentials" revoke-grant "$grant_id"
    updated=$(jq -S -c --arg id "$grant_id" '.grants |= [.[]|select(.id!=$id)]' "$store_file")
    write_store "$updated"
    ;;
  revoke-project)
    test "$#" -eq 1 || fail E_USAGE 'revoke-project PROJECT_ROOT'
    identity=$(identity_json "$1"); identity_fingerprint=$(sha256_text "$identity")
    store_setup; assert_store_outside_project "$identity"; exec 9<>"$lock_file"; flock -x 9; validate_store_file "$store_file"
    "$credentials" revoke-project "$identity_fingerprint"
    updated=$(jq -S -c --arg i "$identity_fingerprint" '.grants |= [.[]|select(.identity_fingerprint!=$i)]' "$store_file")
    write_store "$updated"
    ;;
  identity)
    test "$#" -eq 1 || fail E_USAGE 'identity PROJECT_ROOT'; identity_json "$1";;
  *) fail E_USAGE 'command must be authorize, review, list, revoke, revoke-project, or identity';;
esac
