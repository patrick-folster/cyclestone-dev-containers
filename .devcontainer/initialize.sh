#!/bin/sh
# Runs on the host before the Dev Container starts.
# Ensures the Ollama forwarder is running so containers can reach
# the host's Ollama instance. Can be configured via environment variables.
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

# Save current env values if they are set
env_ollama_forward=${CYCLESTONE_OLLAMA_FORWARD:-}
env_ollama_port=${CYCLESTONE_OLLAMA_PORT:-}
env_forward_port=${CYCLESTONE_OLLAMA_FORWARD_PORT:-}
env_ollama_host=${CYCLESTONE_OLLAMA_HOST:-}

# Load default configuration
if [ -f "$repo_root/.devcontainer/.init" ]; then
  # shellcheck source=.devcontainer/.init
  . "$repo_root/.devcontainer/.init"
fi

# Load local overrides
if [ -f "$repo_root/.devcontainer/.init.local" ]; then
  # shellcheck source=.devcontainer/.init.local
  . "$repo_root/.devcontainer/.init.local"
fi

# Apply priority hierarchy (Env > .init.local > .init > Defaults)
ollama_forward=${env_ollama_forward:-${CYCLESTONE_OLLAMA_FORWARD:-true}}
ollama_port=${env_ollama_port:-${CYCLESTONE_OLLAMA_PORT:-11434}}
forward_port=${env_forward_port:-${CYCLESTONE_OLLAMA_FORWARD_PORT:-11435}}
CYCLESTONE_OLLAMA_HOST=${env_ollama_host:-${CYCLESTONE_OLLAMA_HOST:-}}


# base_image_staleness_check: warn if the local base image predates the
# newest source file baked into it. A stale base can ship an outdated
# installer (e.g. cyclestone-tools) that the child Containerfile then runs
# with surprising failures (Permission denied on /usr/local/share/licenses).
# Warn-only; never blocks container start.
#
# Two signals are checked:
#   1. Committed: newest git commit time among watched files vs image Created.
#      Commit time is stable across git operations (checkout, pull, clone)
#      and reflects when the tracked content last changed in the repo.
#   2. Uncommitted: `git status --porcelain` on watched files. If any are
#      modified/added/deleted, the working tree has changes the image cannot
#      contain regardless of commit time.
#
# Env overrides:
#   CYCLESTONE_BASE_IMAGE_REF  base image ref (default localhost/cyclestone-base:local)
#   CYCLESTONE_BASE_STALENESS_WATCH  space-separated repo-relative paths to watch
#     (default: scripts/install-tools.sh images/base/Containerfile
#      images/base/packages.txt images/base/entrypoint.sh images/base/versions.env)
base_image_staleness_check() {
  ref=${CYCLESTONE_BASE_IMAGE_REF:-localhost/cyclestone-base:local}
  default_watch='scripts/install-tools.sh images/base/Containerfile
    images/base/packages.txt images/base/entrypoint.sh images/base/versions.env'
  watch=${CYCLESTONE_BASE_STALENESS_WATCH:-$default_watch}

  img_created_raw=$(podman image inspect --format '{{.Created}}' "$ref" 2>/dev/null) || {
    echo "base-staleness: image not found: $ref (skip)" >&2
    return 0
  }
  # Normalize podman's "2026-08-05 00:25:08.446102318 +0000 UTC" to RFC 3339
  # so GNU date can parse it to an epoch second.
  img_created_norm=$(printf '%s' "$img_created_raw" \
    | sed 's# +0000 UTC$#Z#; s# #T#')
  img_epoch=$(date -u -d "$img_created_norm" +%s 2>/dev/null) || {
    echo "base-staleness: cannot parse image Created '$img_created_raw' (skip)" >&2
    return 0
  }

  # Signal 1: newest committed change among watched files.
  have_git=
  if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then have_git=1; fi
  newest_file=
  newest_epoch=0
  if [ -n "$have_git" ]; then
    for rel in $watch; do
      [ -f "$repo_root/$rel" ] || continue
      commit_epoch=$(git -C "$repo_root" log -1 --format=%ct -- "$rel" 2>/dev/null || true)
      case "$commit_epoch" in *[!0-9]*) continue ;; esac
      [ -n "$commit_epoch" ] || continue
      if [ "$commit_epoch" -gt "$newest_epoch" ]; then
        newest_epoch=$commit_epoch
        newest_file=$rel
      fi
    done
  else
    # No git: fall back to filesystem mtime.
    for rel in $watch; do
      abs=$repo_root/$rel
      [ -f "$abs" ] || continue
      fs_epoch=$(stat -c %Y "$abs" 2>/dev/null || stat -f %m "$abs" 2>/dev/null || true)
      case "$fs_epoch" in *[!0-9]*) continue ;; esac
      [ -n "$fs_epoch" ] || continue
      if [ "$fs_epoch" -gt "$newest_epoch" ]; then
        newest_epoch=$fs_epoch
        newest_file=$rel
      fi
    done
  fi

  if [ "$newest_epoch" -gt 0 ] && [ "$newest_epoch" -gt "$img_epoch" ]; then
    gap=$((newest_epoch - img_epoch))
    echo "base-staleness: $ref predates newest committed source file." >&2
    printf 'base-staleness:   %-28s committed %s ago\n' \
      "$newest_file" "$(printf '%dd %02dh%02dm' \
        $((gap/86400)) $(((gap%86400)/3600)) $(((gap%3600)/60)))" >&2
    echo "base-staleness: rebuild the base image before relying on it:" >&2
    echo "base-staleness:   IMAGE_VERSION=<x> IMAGE_REVISION=<sha> IMAGE_CREATED=<ts> \\" >&2
    echo "base-staleness:     IMAGE_LICENSES=<expr> INSTALL_TOOLS=<list> \\" >&2
    echo "base-staleness:     ./scripts/build-base-podman.sh" >&2
  fi

  # Signal 2: uncommitted changes to watched files (git only).
  if [ -n "$have_git" ]; then
    uncommitted=
    for rel in $watch; do
      [ -e "$repo_root/$rel" ] || continue
      if git -C "$repo_root" status --porcelain -- "$rel" 2>/dev/null | grep -q .; then
        uncommitted="$uncommitted $rel"
      fi
    done
    if [ -n "$uncommitted" ]; then
      echo "base-staleness: uncommitted changes to watched files:" >&2
      for rel in $uncommitted; do
        printf 'base-staleness:   %s\n' "$rel" >&2
      done
      echo "base-staleness: rebuild the base image to include them." >&2
    fi
  fi
}

# ensure_rootless_podman_cgroup_fix: rootless podman + systemd cgroup manager
# fails with "sd-bus call: Access denied ... interactive authentication"
# whenever the OCI runtime (crun OR runc) tries to start a systemd scope unit
# for cgroup management without a usable polkit rule or interactive auth. This
# is NOT runtime-specific: both crun and runc use sd-bus under the systemd
# cgroup manager. It breaks BOTH `podman run`/`start` AND the Dev Containers
# CLI build step (`podman buildx build`), because buildx does NOT inherit
# devcontainer.json `runArgs`.
#
# devcontainer.json `runArgs` pins `--runtime=runc` and `--cgroupns=private`,
# but those only fix the run path. The build path (buildx) reads its defaults
# from containers.conf.
#
# Fix: pin BOTH the default OCI runtime to runc AND the cgroup manager to
# cgroupfs in the rootless containers.conf (~/.config/containers/containers.conf),
# which podman reads for ALL commands including buildx. cgroupfs bypasses
# systemd/sd-bus entirely for cgroup setup; runc is the mature runtime for the
# cgroupfs path. Idempotent: writes only when the file does not already pin
# both keys to the desired values.
#
# Env: reads oci_runtime and cgroup_mgr (set by caller from `podman info`).
ensure_rootless_podman_cgroup_fix() {
  # Only act when the active config is the problematic one (systemd cgroup mgr).
  # If the user already switched to cgroupfs out-of-band, respect it.
  [ "$cgroup_mgr" = "systemd" ] || return 0
  conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/containers"
  conf="$conf_dir/containers.conf"
  mkdir -p "$conf_dir"
  # Idempotency: if [engine] already pins both runtime="runc" and
  # cgroup_manager="cgroupfs", nothing to do. Tolerate quote/space variants.
  if [ -f "$conf" ] \
     && grep -qE '^[[:space:]]*runtime[[:space:]]*=[[:space:]]*"?runc"?' "$conf" \
     && grep -qE '^[[:space:]]*cgroup_manager[[:space:]]*=[[:space:]]*"?cgroupfs"?' "$conf"; then
    return 0
  fi
  if ! command -v runc >/dev/null 2>&1; then
    echo "podman-guard: systemd cgroup manager detected but runc not installed;" \
         "build/run may fail with sd-bus Access denied." >&2
    echo "podman-guard: install 'runc', switch cgroup_manager to cgroupfs," \
         "or add a polkit rule for systemd unit management." >&2
    return 0
  fi
  # Rewrite preserving existing content: ensure [engine] section has both
  # runtime = "runc" and cgroup_manager = "cgroupfs". If a key already exists
  # in [engine], overwrite it in place; if [engine] is absent, append it.
  tmp=$(mktemp 2>/dev/null) || return 0
  if [ -f "$conf" ]; then
    awk '
      BEGIN { in_engine=0; set_rt=0; set_cg=0; seen_engine=0 }
      /^\[engine\]/ { in_engine=1; seen_engine=1; print; next }
      /^\[/ {
        if (in_engine) {
          if (!set_rt) { print "runtime = \"runc\""; set_rt=1 }
          if (!set_cg) { print "cgroup_manager = \"cgroupfs\""; set_cg=1 }
        }
        in_engine=0; print; next
      }
      in_engine && /^[[:space:]]*runtime[[:space:]]*=/ { print "runtime = \"runc\""; set_rt=1; next }
      in_engine && /^[[:space:]]*cgroup_manager[[:space:]]*=/ { print "cgroup_manager = \"cgroupfs\""; set_cg=1; next }
      { print }
      END {
        if (!seen_engine) { print ""; print "[engine]"; print "runtime = \"runc\""; print "cgroup_manager = \"cgroupfs\"" }
        else if (in_engine) {
          if (!set_rt) { print "runtime = \"runc\"" }
          if (!set_cg) { print "cgroup_manager = \"cgroupfs\"" }
        }
      }
    ' "$conf" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  else
    {
      echo "# Managed by Cyclestone .devcontainer/initialize.sh"
      echo "# Pins runc + cgroupfs to avoid rootless podman sd-bus Access denied"
      echo "# under systemd cgroup manager (affects buildx build + run)."
      echo "[engine]"
      echo "runtime = \"runc\""
      echo "cgroup_manager = \"cgroupfs\""
    } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  fi
  mv "$tmp" "$conf"
  echo "podman-guard: pinned runtime=runc + cgroup_manager=cgroupfs via $conf" >&2
  echo "podman-guard: (systemd sd-bus path bypassed for buildx + run)" >&2
}

# Podman guards: base-image staleness + cgroup fix. Run BEFORE the
# ollama-forwarder section so the early exits below (forwarder already up,
# socat missing) cannot skip the cgroup fix.
if command -v podman >/dev/null 2>&1; then
  base_image_staleness_check
  oci_runtime=$(podman info --format '{{.Host.OCIRuntime.Name}}' 2>/dev/null || true)
  cgroup_mgr=$(podman info --format '{{.Host.CgroupManager}}' 2>/dev/null || true)
  ensure_rootless_podman_cgroup_fix
fi

# Generate the dynamic environment file for the container
env_file="$repo_root/.devcontainer/.env.dynamic"

if [ "$ollama_forward" = "true" ] || [ "$ollama_forward" = "1" ] || [ "$ollama_forward" = "yes" ]; then
  if ss -tlnp 2>/dev/null | grep -q ":${forward_port}\b"; then
    echo "ollama-forwarder: already listening on ${forward_port}"
  elif ! command -v socat >/dev/null 2>&1; then
    echo "ollama-forwarder: socat not found, skipping forwarder startup" >&2
  else
    setsid socat "TCP-LISTEN:${forward_port},bind=0.0.0.0,fork,reuseaddr" "TCP:127.0.0.1:${ollama_port}" </dev/null >/dev/null 2>&1 &
    sleep 0.5

    if ss -tlnp 2>/dev/null | grep -q ":${forward_port}\b"; then
      echo "ollama-forwarder: started on ${forward_port} -> 127.0.0.1:${ollama_port}"
    else
      echo "ollama-forwarder: failed to start" >&2
    fi
  fi
  container_ollama_port=$forward_port
else
  echo "ollama-forwarder: disabled by configuration"
  container_ollama_port=$ollama_port
fi

# Determine final OLLAMA_HOST
container_ollama_host=${CYCLESTONE_OLLAMA_HOST:-http://host.containers.internal:${container_ollama_port}}

# Generate OPENCODE_CONFIG_CONTENT JSON matching the selected host/port
opencode_config=$(cat <<EOF
{"\$schema":"https://opencode.ai/config.json","provider":{"ollama":{"options":{"baseURL":"${container_ollama_host}/v1"}}}}
EOF
)

# Write to the env file
cat <<EOF > "$env_file"
# Generated by .devcontainer/initialize.sh - DO NOT EDIT MANUALLY
OLLAMA_HOST=${container_ollama_host}
OPENCODE_CONFIG_CONTENT=${opencode_config}
EOF