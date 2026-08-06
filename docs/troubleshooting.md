# Troubleshooting

Common failure modes and their solutions. Each section links to the detailed
guide for the underlying topic.

## Volume and workspace ownership issues

### Bind mount is not writable

**Symptom:** `mkdir`, `touch`, or `git` operations in `/workspace` fail with
`Permission denied`.

**Cause:** The host directory does not have permissions suitable for the
selected identity mode. Under rootless Podman `keep-id:uid=1000,gid=1000`, the
host user is mapped to container UID 0, and container UID 1000 is mapped from
`/etc/subuid`. A host-owned mode-0755 directory is not automatically writable by
the mapped container user.

**Solution:**

- For a matching `1000:1000` host account, ensure the workspace is
  owner-writable: `chmod u+w "$PWD"`.
- For a differing host account, grant the mapped container UID a POSIX ACL:

  ```sh
  # Compute the mapped host UID for container UID 1000
  start=$(awk -F: -v u="$(id -un)" '$1==u{print $2}' /etc/subuid)
  mapped=$((start + 1000 - 1))
  setfacl -m "u:$mapped:rwx" "$PWD"
  ```

- Alternatively, use the Dev Container CLI UID mutation mode (C4) instead of
  Podman `keep-id` when the host UID differs from 1000.

See [workspace-identity.md](workspace-identity.md) for the full identity modes
and D-014 in `.cyclestone/DECISIONS.md` for the ACL rationale.

### Git "dubious ownership" error

**Symptom:** `git -C /workspace status` fails with
`fatal: detected dubious ownership in repository at '/workspace'`.

**Cause:** Git detects that the repository owner does not match the current
user. Under rootless Podman, the host UID is mapped to container UID 0 while
the workspace files appear owned by a mapped identity.

**Solution:** Add a `safe.directory` exception for the workspace. The base
image lifecycle and the workspace-identity fixture already cover this. For a
manual fix:

```sh
git config --global --add safe.directory /workspace
```

This is safe because `/workspace` is a bind mount of a reviewed project; it
does not grant trust to arbitrary repositories. See
[workspace-identity.md](workspace-identity.md).

## Non-1000 host UID/GID mappings

### Dev Container UID update vs Podman keep-id

The two supported identity translation mechanisms are mutually exclusive:

| Mode | Mechanism | When to use |
| --- | --- | --- |
| Dev Container (C4) | CLI updates `developer` UID/GID to host values | Rootful Docker, host UID differs from 1000 |
| Podman keep-id (C5/C6) | User namespace maps host to image `1000:1000` | Rootless Podman, host UID is 1000 or differs |

Combining `updateRemoteUserUID=true` with `--userns=keep-id` causes a
`postCreateCommand` permission denial. Always use one mechanism at a time.

See D-016 in `.cyclestone/DECISIONS.md` and
[workspace-identity.md](workspace-identity.md).

### /etc/subuid range exhaustion

**Symptom:** Podman fails to start with an error about subordinate UID range
exhaustion or `could not find enough available UIDs`.

**Cause:** The user's `/etc/subuid` range is too small or already in use by
another rootless container.

**Solution:**

```sh
# Check the current range
awk -F: -v u="$(id -un)" '$1==u{print $2, $3}' /etc/subuid

# A range of at least 65536 is recommended
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$(id -un)"
```

After changing the range, log out and back in or run
`podman system migrate`.

## Supplementary group issues

### keep-groups and unmapped GID overflow

**Symptom:** Files created by a supplementary host group are not accessible
inside the container.

**Cause:** Rootless Podman with `--group-add keep-groups` maps the host
supplementary GID directly without a namespace translation. If the GID falls
outside the `/etc/subgid` range, it appears as `nobody` or `overflow` inside
the container.

**Solution:** Ensure the supplementary GID is within the user's `/etc/subgid`
range, or grant explicit host permissions (ACL) for the mapped container GID.
See [workspace-identity.md](workspace-identity.md) and the rootless-podman test
for the `keep-groups` behavior.

### setgid directories

If the workspace or a subdirectory has the setgid bit, new files inherit the
directory's group rather than the creating user's group. This is normal POSIX
behavior and does not indicate a permission error.

## Fedora SELinux denials

### user_home_t label on bind-mounted content

**Symptom:** Podman or the build fails with
`Permission denied` on a bind-mounted file, and `ausearch -m AVC` shows an
`user_home_t` denial.

**Cause:** Files created in the home directory retain the `user_home_t` SELinux
label, which container processes cannot access.

**Solution:** Relabel the mount with `:Z` (private) or `:z` (shared):

```sh
podman run --rm -v "$PWD:/workspace:Z" cyclestone-base:1.0.0 ls /workspace
```

Or set the file context permanently:

```sh
sudo semanage fcontext -a -t container_file_t "$PWD(/.*)?"
restorecon -Rv "$PWD"
```

See [selinux.md](selinux.md) for the full configuration guide.

### Build-time SELinux denials (D-020)

**Symptom:** `podman build` fails during the final-stage package installation
with a denial on a `RUN --mount=type=bind` of a repository file.

**Cause:** The bind-mounted repository file retains its `user_home_t` label,
and an enforcing SELinux host denies the container process access.

**Solution:** This is already handled by the base image Containerfile, which
copies the package allow-list into an internal acquisition stage and binds it
from there (D-020). If you are extending the base and encounter a similar
denial, use the same cross-stage copy pattern. Do not disable SELinux.

See [selinux.md](selinux.md#build-time-selinux-denials-d-020) for details.

### Using audit2allow

As a last resort for a legitimate operation that cannot be addressed by
relabeling:

```sh
sudo ausearch -m AVC -ts recent | audit2allow -M cyclestone-local
sudo semodule -i cyclestone-local.pp
```

Document the custom policy and its rationale. Prefer relabeling or file-context
changes over broad `audit2allow` policies.

## Container engine and CLI version mismatches

### Podman older than 4.9

**Symptom:** `--userns=keep-id:uid=1000,gid=1000` is rejected or behaves
incorrectly.

**Cause:** The `keep-id:uid=N,gid=N` syntax requires Podman 4.9 or newer.

**Solution:** Upgrade Podman to 4.9 or newer. Check the version:

```sh
podman version --format '{{.Client.Version}}'
```

See D-016 in `.cyclestone/DECISIONS.md`.

### Wrong OCI runtime

**Symptom:** Rootless Podman starts but `keep-groups` or user namespace
behavior is incorrect.

**Cause:** Podman must use `crun` as the OCI runtime. `runc` does not support
all rootless features used by the supported configurations.

**Solution:**

```sh
podman info --format '{{.Host.OCIRuntime.Name}}'
```

If the runtime is not `crun`, configure it:

```sh
# Fedora
sudo dnf install crun
podman system migrate
```

### Dev Container CLI version mismatch

**Symptom:** `devcontainer up` behaves unexpectedly, `exec` forwards the
subcommand token, or `--no-lockfile` is rejected.

**Cause:** Dev Container CLI `0.86.0` is the pinned and qualified version. Newer
or older versions may have different behavior.

**Solution:** Install the exact pinned version:

```sh
npm install --global @devcontainers/cli@0.86.0
devcontainer --version
```

See D-015, D-021, and D-022 in `.cyclestone/DECISIONS.md` for the specific
CLI behaviors that motivated the pin.

## Podman and Dev Container integration issues

### exec subcommand token bug (D-021)

**Symptom:** `devcontainer exec` passes its own `exec` subcommand token as the
container executable, causing `exec: "exec": executable file not found`.

**Cause:** CLI 0.86.0's `exec` path forwards the subcommand token. This is a
known bounded limitation of the pinned CLI.

**Solution:** Use the selected engine's direct `exec` against the `containerId`
returned by `up`:

```sh
container_id=$(devcontainer --docker-path podman up --workspace-folder "$PWD" | jq -r '.containerId')
podman exec "$container_id" /bin/pwd
```

Do not use `devcontainer exec` for runtime assertions. The CLI remains
responsible for build, start, lifecycle, reopen, and rebuild. See D-021.

### --pull=never for local image IDs (D-022)

**Symptom:** A no-cache rebuild with a local image ID fails because CLI 0.86.0
adds `--pull`, and Podman cannot pull an image ID.

**Cause:** An image ID is a local content address, not a registry reference.
CLI 0.86.0's `--pull` policy cannot be applied to an ID.

**Solution:** The local fixture appends `--pull=never` through `build.options`
for the required no-cache rebuild only. This override is confined to the
generated native-test workspace and does not alter the consumer template's
registry-digest-pinned base behavior. See D-022.

### Null authorization metadata (D-023)

**Symptom:** The evidence scan matches `authorization: null` in Podman metadata
and reports it as a credential.

**Cause:** Podman's capability metadata includes a literal `authorization: null`
field. This is null metadata, not a credential.

**Solution:** This is already handled by the evidence scan, which excludes only
an exact null authorization field while retaining failure for non-null
authorization values and all other prohibited credential patterns. See D-023.

## Unavailable host services

### Ollama not running

**Symptom:** `curl "$OLLAMA_HOST/api/tags"` fails with `Connection refused`.

**Cause:** The Ollama daemon is not running on the host, or
`OLLAMA_HOST` points to the wrong endpoint.

**Solution:**

```sh
# Verify Ollama is running on the host
systemctl --user status ollama
curl -sSf http://127.0.0.1:11434/api/tags

# Verify the container can reach the host
curl -sSf http://host.containers.internal:11434/api/tags
```

The trusted registry's default endpoint is
`http://host.containers.internal:11434`. If Ollama listens on a different port
or address, set `OLLAMA_HOST` in the host environment before starting the
container. See [ollama.md](ollama.md).

### OLLAMA_HOST not set

**Symptom:** Provider credential or runtime configuration validation fails with
`E_ENV_MISSING` for `OLLAMA_HOST`.

**Cause:** The `OLLAMA_HOST` environment variable is not set in the host
environment.

**Solution:** Set it before generating or starting the container:

```sh
export OLLAMA_HOST=http://host.containers.internal:11434
```

Cyclestone checks that the name is present but does not parse or probe the
value. See [ollama.md](ollama.md).

## Provider authorization issues

### E_APPROVAL_REQUIRED

**Symptom:** `scripts/devcontainer-permissions.sh authorize` fails with
`E_APPROVAL_REQUIRED`.

**Cause:** No active persistent grant matches the exact plan and project
identity. This happens on first use, after a move, after a clone, after a
mode change, or after revocation.

**Solution:** Run `review` first (requires a controlling terminal):

```sh
scripts/devcontainer-permissions.sh review "$PWD" providers.json <provider-id> linux
```

Choose `always` for persistent approval or `once` for a single-use plan. See
[provider-authorization.md](provider-authorization.md).

### E_ACTIVE_SESSION

**Symptom:** `scripts/devcontainer-permissions.sh revoke` or
`scripts/provider-credentials.sh` fails with `E_ACTIVE_SESSION`.

**Cause:** A tracked session is still active for the provider. Revocation is
refused while a session is running.

**Solution:** Stop the active session first, then revoke:

```sh
scripts/provider-credentials.sh stop "$PWD" <provider-id>
scripts/devcontainer-permissions.sh revoke <grant-id>
```

See [provider-credentials.md](provider-credentials.md).

## Documentation command drift

If documented commands fail, run the documentation validator to check for
drift between markdown examples and actual script interfaces:

```sh
./scripts/validate-docs.sh
```

The validator checks that referenced scripts exist, documented flags are
accepted, and inline shell snippets pass `sh -n` syntax validation.
