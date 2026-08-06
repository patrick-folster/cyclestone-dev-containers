# Fedora SELinux Configuration

Fedora uses SELinux in enforcing mode by default. Rootless Podman on an
enforcing SELinux host can deny bind mounts that retain their host file label
because container processes are confined to a different SELinux context. This
page covers the supported configuration and the internal build-input workaround
that keeps builds working without disabling SELinux.

## Check SELinux mode

```sh
getenforce
```

`Enforcing` is the supported mode. `Permissive` logs denials but does not block
them. `Disabled` removes SELinux entirely and is not recommended.

## Bind mount labels

Podman can relabel bind-mounted content with the `:Z` (private) or `:z` (shared)
suffix so the container process can access it under its SELinux context:

```sh
podman run --rm -v "$PWD:/workspace:Z" cyclestone-base:1.0.0 ls /workspace
```

`:Z` labels the content with a private container-specific label. `:z` labels it
with a shared label that all containers can read. Use `:Z` for project
workspaces to avoid cross-container sharing.

The project Dev Container template does not add `:Z` automatically because the
Dev Container CLI generates the mount specification. When using
`devcontainer-generate.sh`, the generated local runtime file applies
`relabel=private` for provider credential mounts. Project workspace mounts are
handled by the rootless Podman runtime.

## Build-time SELinux denials (D-020)

The base image Containerfile copies the package allow-list into a non-final
acquisition stage and binds it into the final-stage package-install step from
that internal stage. This avoids a `RUN --mount=type=bind` read of a file that
retains its `user_home_t` host label, which an enforcing SELinux host denies:

```dockerfile
FROM ${BASE_IMAGE} AS acquisition
COPY images/base/packages.txt /tmp/base-packages.txt

FROM ${BASE_IMAGE} AS final
RUN --mount=type=bind,from=acquisition,source=/tmp/base-packages.txt,target=/tmp/base-packages.txt,readonly \
    xargs -r apt-get install -y --no-install-recommends < /tmp/base-packages.txt
```

The cross-stage copy preserves the single reviewed allow-list, avoids disabling
SELinux or relabeling project source, and keeps the build-only file out of every
final-image layer. This is architectural decision D-020; see
`.cyclestone/DECISIONS.md`.

## Diagnosing SELinux denials

### View recent denials

```sh
sudo ausearch -m AVC -ts recent
```

### Translate a denial to a readable description

```sh
sudo ausearch -m AVC -ts recent | audit2allow -w
```

### Generate a local policy module (last resort)

If a legitimate operation is denied and no supported configuration avoids it,
generate and install a custom policy module:

```sh
sudo ausearch -m AVC -ts recent | audit2allow -M cyclestone-local
sudo semodule -i cyclestone-local.pp
```

Prefer `:Z`/`:z` relabeling, the internal-stage build workaround, or adjusting
the host file context over a broad `audit2allow` policy. Document any custom
policy and its rationale.

## Set file context for a project workspace

If a project workspace retains an inappropriate label after a `git clone` into a
home directory:

```sh
sudo semanage fcontext -a -t container_file_t "$PWD(/.*)?"
restorecon -Rv "$PWD"
```

This relabels the workspace to the container file type so rootless Podman can
bind-mount it without `:Z`. Use this only for disposable project directories;
it affects all containers that mount the path.

## Supported configuration summary

| Scenario | Supported action |
| --- | --- |
| Bind mount project workspace | Use `:Z` or relabel to `container_file_t` |
| Build with repository build inputs | Cross-stage internal copy (D-020, already implemented) |
| Provider credential mount | `relabel=private` applied by `devcontainer-generate.sh` |
| Disabling SELinux | Not supported; use relabeling or policy modules instead |

See [troubleshooting.md](troubleshooting.md) for common SELinux failure modes
and [workspace-identity.md](workspace-identity.md) for the rootless Podman
identity modes.
