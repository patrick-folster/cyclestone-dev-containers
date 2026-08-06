#!/bin/sh
# Switches .devcontainer/devcontainer.json to the generated local runtime config
# (with provider mounts and env vars), backing up the portable config.
# Run this before opening in VS Code Dev Containers when providers are needed.
# Run with --restore to switch back to the portable config.
set -eu
cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
portable=.devcontainer/devcontainer.json
local_runtime=.cyclestone/runtime/devcontainer.json
backup=.devcontainer/devcontainer.json.portable-bak

if test "${1:-}" = "--restore"; then
  if test -f "$backup"; then cp "$backup" "$portable"; rm -f "$backup"; echo "Restored portable config"; else echo "No backup found"; fi
  exit 0
fi

if ! test -f "$local_runtime"; then echo "ERROR: $local_runtime not found. Run scripts/devcontainer-generate.sh first." >&2; exit 1; fi
cp "$portable" "$backup"
cp "$local_runtime" "$portable"
echo "Switched to local runtime config (provider mounts + env vars active)"
echo "Restore with: ./scripts/switch-devcontainer-config.sh --restore"