# Workspace Identity

The supported Linux identity modes all keep the in-container account name
`developer` and make new bind-mounted files belong to the invoking host user.
They achieve that result with one translation layer at a time.

| Mode | Numeric identity in container | Ownership mechanism | Qualified runtime |
| --- | --- | --- | --- |
| Dev Container | Host UID and GID | Client updates `developer` before start | Rootful Docker, Dev Container CLI `0.86.0`, Ubuntu 24.04 amd64 |
| Direct Podman | `1000:1000` | Rootless user namespace maps host user to image IDs | Podman 4.9 with crun, Ubuntu 24.04 amd64 |
| Project Dev Container on Podman | `1000:1000` | CLI selects rootless Podman keep-id; client mutation is disabled | Dev Container CLI 0.86.0, rootless Podman 4.9 with crun, native Linux amd64 |

In either mode, mounting a repository at `/workspace` hides the image directory
entirely. The host directory must already exist and have permissions suitable for
the selected mapping. Startup validates access and exits; it never runs project
content or repairs ownership with `chown`, `chmod`, or `sudo`.

## Dev Container mode

Use both user fields and enable the pinned client's Linux UID/GID update:

```json
{
  "image": "cyclestone-base:1.0.0",
  "remoteUser": "developer",
  "containerUser": "developer",
  "updateRemoteUserUID": true,
  "workspaceFolder": "/workspace",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind",
  "mounts": [
    "source=cyclestone-devcontainer-home,target=/home/developer,type=volume"
  ],
  "privileged": false,
  "runArgs": []
}
```

On native Linux, CLI `0.86.0` updates the numeric UID/GID behind the fixed name
`developer` to the invoking account before the container starts. Verify with
`id`, `getent passwd developer`, and `stat -c '%u:%g' /workspace`. Other editors
and Dev Container implementations may update only the UID, update at another
lifecycle point, or decline a conflicting ID; they are unsupported until added
to the compatibility matrix.

Never add `--userns=keep-id` to `runArgs` when `updateRemoteUserUID` is enabled.
That would create two identity translators, and the supplied validation rejects
it as a client-mutation conflict.

## Direct rootless Podman mode

Confirm that Podman is rootless and that the invoking user has subordinate-ID
ranges:

```sh
podman info --format '{{.Host.Security.Rootless}}'
grep "^$(id -un):" /etc/subuid /etc/subgid
podman info --format '{{.Host.OCIRuntime.Name}}'
```

The supported minimum is Podman 4.9 with crun. Run the default image account and
map the host principal specifically to its `1000:1000` IDs:

```sh
podman volume create cyclestone-podman-home
podman run --rm -it \
  --user developer \
  --userns=keep-id:uid=1000,gid=1000 \
  --security-opt=no-new-privileges \
  --mount "type=bind,source=$PWD,destination=/workspace" \
  --volume cyclestone-podman-home:/home/developer \
  cyclestone-base:1.0.0
```

This command does not use a Dev Container client or `updateRemoteUserUID`.
Inside, `id -un` remains `developer` and `id -u`/`id -g` remain `1000`; files
created under `/workspace` appear on the host as `$(id -u):$(id -g)`.

Podman still needs usable `/etc/subuid` and `/etc/subgid` ranges for the rest of
the namespace. A missing-range diagnostic is distinct from an exhausted range,
namespace creation failure, or ordinary filesystem denial. Administrators must
allocate ranges according to host policy; do not weaken repository modes.

## HOME, caches, and mode switching

The examples persist all of `/home/developer`, including global Git settings and
the XDG configuration, cache, and data directories. Named volumes preserve
numeric owners, not knowledge of which identity mode created them. Use separate
volumes (`cyclestone-devcontainer-home` and `cyclestone-podman-home`) by default.
Before reusing one, inspect its contents from the destination mode and confirm
they are writable. An incompatible old owner is a volume diagnostic, never a
reason for recursive startup ownership repair.

## Git ownership and supplementary groups

Correctly mapped repositories require no `safe.directory` override. Git's
"dubious ownership" error indicates a real identity mismatch. Do not set
`safe.directory=*`, which trusts every repository. If a user explicitly accepts
one exceptional repository, `git config --global --add safe.directory
/workspace` narrowly trusts that path but does not correct its ownership; remove
the exception after fixing the mapping.

For a host group-writable path, the invoking user must already belong to that
group. With the supported Podman/crun combination, add both the mount and
`--group-add keep-groups`; the host directory should normally be setgid so new
files retain its group. Diagnose with `id -G`, `stat -c '%u:%g %a' PATH`, and the
container's `/proc/self/gid_map`. An unmapped host supplementary GID can appear as
an overflow value rather than its literal host number inside the container; with
`keep-groups`, successful access plus the expected host-side ownership and mode is
the authoritative check. If crun is not active or the filesystem refuses the
write, stop and correct the host/runtime configuration. Dev Container
supplementary-group behavior is not part of C4.

## Troubleshooting and boundaries

For non-1000 hosts, compare host `id -u`/`id -g` with container `id`, HOME and
workspace `stat`, and `/proc/self/uid_map` plus `/proc/self/gid_map`. A Dev
Container should show the host IDs directly; Podman should show `1000:1000`
inside and the host IDs outside. Rebuild or recreate a mode-specific HOME volume
if it was initialized by an incompatible identity.

NFS root squashing, CIFS identity projection, SELinux labels, ACLs, remote
filesystems, and unsupported Podman/editor versions may override ordinary Unix
ownership. They are outside the supported rows. Diagnose their host policy or,
for SELinux on an appropriate host, deliberately select the required relabeling
option; do not make the workspace world-writable.

The image intentionally contains no `sudo`. Granting it would let any malicious
project tool expand its effect toward container root and any mounted data. It
does not solve host namespace or filesystem ownership and is not a supported
permission-repair mechanism.

## Project Dev Container on rootless Podman

The reusable child-image workflow is a third, bounded mode. It uses the direct
Podman executable through Dev Container CLI rather than the C4 mutation path or
a Docker-compatible socket. Its full trust review, build/start/rebuild commands,
cache lifecycle, matching/differing identity evidence, and editor smoke are in
[`devcontainers.md`](devcontainers.md).
