# Project Dev Container

The base template contains no provider access. Approved access is added only by
the [generated runtime configuration workflow](runtime-configuration.md), whose
ignored local output must be selected explicitly at startup.

> **Review before consent:** a repository's Containerfile, Dev Container
> configuration, lifecycle hooks, mounts, build inputs, and editor
> customizations are untrusted code. Read all of them before opening or running
> the container. Non-root execution limits authority but does not make hostile
> repository code safe, especially when source or credentials are accessible.

The template at `templates/project-devcontainer/.devcontainer/` builds a project
child image from the inherited Cyclestone contract, installs checksum-pinned Go
1.26.5, and bind-mounts the complete repository at `/workspace`. Source is never
copied into an image layer. Copy `.devcontainer/` into the root of the project
that will use it.

## Qualified CLI and rootless Podman mode

The supported host is native Linux amd64 with Dev Container CLI `0.86.0`,
rootless Podman 4.9 or newer, and crun. The invoking non-root account needs
entries in `/etc/subuid` and `/etc/subgid`. Every account participating in the
two-identity gate needs the pinned CLI on its own `PATH`. Check the exact runtime
before use:

```sh
npm install --global @devcontainers/cli@0.86.0
podman info --format '{{.Host.Security.Rootless}}'
podman info --format '{{.Host.OCIRuntime.Name}}'
grep "^$(id -un):" /etc/subuid /etc/subgid
```

If a qualification-only account has Node/npm but no persistent CLI installation,
run the gate through the pinned package without changing the repository:

```sh
npm exec --yes --package=@devcontainers/cli@0.86.0 -- \
  env EVIDENCE_DIR="$EVIDENCE_DIR" \
  REGISTRY_AUTH_FILE="$REGISTRY_AUTH_FILE" \
  ./scripts/validate-milestone-local.sh ms-pf-0005
```

## Local cycle qualification

GitHub Actions is not required to finish this milestone. From a host session
with rootless Podman and the pinned CLI, run:

```sh
./scripts/validate-milestone-local.sh ms-pf-0005
```

Run the command against the same commit and shared `dist/evidence` tree (a
local-only qualification output, not committed to the repository) first as
a `1000:1000` account and then as any non-root account whose UID/GID differs
from `1000:1000` (order does not matter). Each account needs subordinate UID and
GID ranges. The command builds the base with rootless Podman, obtains the
builder-reported content-addressed ID independently of tag lookup, checks that
the local tag resolves to it, and runs the complete V8 lifecycle. It exits
successfully only after both identity cases have passing evidence for the same
commit and exact tracked/untracked source-content digest.
The first run creates the evidence root with sticky shared-directory semantics;
each case directory remains owned by the account that produced it. If the two
accounts use separate checkouts, set the same absolute `EVIDENCE_DIR` for both.
After one identity passes, the command deliberately returns status `1` with a
message naming the missing peer. That is an incomplete aggregate result, not a
failure of the completed identity case. The second passing identity returns
status `0` and emits
`PASS: both local rootless-Podman identity cases qualify the milestone cycle`.

Run this host-native command outside a development container that hides or
read-only mounts `/run/user/$UID`. Docker results remain useful GitHub Actions
coverage, but they are not a milestone-cycle completion prerequisite.

The CLI selects the host executable directly with `--docker-path podman`; it
does not use Docker socket emulation, need an activated Podman API socket, or
mount a daemon socket into the container. Set the reviewed, canonical consumer
reference and start from the repository root:

```sh
export CYCLESTONE_BASE_IMAGE_REF='ghcr.io/patrick-folster/cyclestone-dev-container-base@sha256:<reviewed-manifest-digest>'
up_result=$(devcontainer --docker-path podman up --workspace-folder "$PWD")
printf '%s\n' "$up_result"
container_id=$(printf '%s\n' "$up_result" | jq -r '.containerId')
podman exec "$container_id" /bin/pwd
podman exec "$container_id" /usr/bin/id
podman exec "$container_id" /usr/bin/getent passwd developer
```

Mutable tags are not trusted base inputs. The repository's native test may use
a loaded tag only after proving that it resolves to a separately supplied
content-addressed Podman image ID; that is a local-only fixture mechanism, not a
consumer reference. After that check, the fixture passes the verified image ID
to the Dev Container build. For its required no-cache rebuild only, the local
fixture appends `--pull=never` through `build.options`; CLI `0.86.0` otherwise
adds `--pull`, which Podman cannot apply to an image ID. This override is not
part of the reusable consumer template, whose base remains registry-digest
pinned.
In the qualified host toolchain, CLI `0.86.0`'s `exec` path forwards its own
subcommand token as the container executable. Use the `containerId` returned by
`up` with the selected engine's direct `exec`, as the native fixture does. The
CLI remains responsible for build, start, lifecycle startup, reopen, and rebuild.

The template sets both user fields to `developer`, disables
`updateRemoteUserUID`, and asks rootless Podman to map the invoking host identity
to the unchanged image `1000:1000` account with
`keep-id:uid=1000,gid=1000`. New files therefore retain `developer:1000:1000`
inside and the invoking UID/GID on the host. CLI UID mutation and keep-id must
not be combined. On 2026-08-01, the diagnostic `true` configuration started for
the matching `1000:1000` account and remained `developer:1000:1000`. Under the
differing `1001:1001` account it failed at `postCreateCommand` with a workspace
lifecycle-script permission denial after CLI UID mutation was combined with
keep-id. Only the explicit `false` configuration with keep-id is supported.

## Latest native qualification

C6/V8 passed on 2026-08-01 for commit
`c65f1f91eb356c1dc9ef0377db50cc6080be7567` and source digest
`1e51c7210f07ec42ffe338b364fe35301ebef42473d9ce3cb9838353c0b87e8a`.
Both `1000:1000` and `1001:1001` accounts passed build, child inheritance,
workspace ownership, lifecycle reruns, cache persistence, reopen, no-cache
rebuild, post-rebuild reopen, customization removal, and evidence credential
scanning on native Linux amd64 with Podman `5.8.4`, crun, and CLI `0.86.0`.
The host-local evidence root was
`/var/tmp/cyclestone-ms-pf-0005-<commit>-final` (a disposable local path).

## Lifecycle, reopen, rebuild, and cache

`postCreateCommand` runs `.devcontainer/lifecycle.sh postCreate` as `developer`.
The hook only validates identity and writable paths, creates the Go cache marker,
and emits a fixed non-sensitive status line. Rerunning it is safe: it performs no
package installation, ownership repair, environment dump, credential lookup, or
project command. Native evidence scanning treats Podman's exact
`authorization: null` information field as an absent authorization configuration;
non-null authorization values and all other prohibited credential patterns still
fail closed.

Normal reopen needs no manual cleanup: rerun `up` and the CLI reuses or restarts
the container. To rebuild/recreate explicitly:

```sh
devcontainer --docker-path podman up --workspace-folder "$PWD" \
  --remove-existing-container --build-no-cache
```

The sole persistent mount is the project-scoped
`cyclestone-project-go-cache` volume at `/home/developer/.cache/go-build`. It is
non-sensitive, disposable compiler output, expected to be owned and writable by
`developer:1000:1000`, and survives reopen/rebuild. Do not reuse it with another
identity strategy. Remove it after closing the container with:

```sh
podman volume rm cyclestone-project-go-cache
```

No HOME, provider, credential, SSH, cloud-tool, or daemon-socket directory is
persisted. Provider integration is reserved for the later deterministic
generation model and must not be added manually to this base template.

## Editor-open smoke checklist

This observational VS Code-compatible check supplements, but does not replace,
the qualified CLI/Podman test:

1. Review and consent to every file and input named in the warning above.
2. Open the project root in the Dev Container and confirm the editor root is
   `/workspace`, including root files and multiple top-level directories.
3. In the integrated terminal run `pwd`, `id`, and `getent passwd developer`;
   expect `/workspace`, non-root `developer`, and numeric `1000:1000`.
4. Create a probe in `/workspace`; on the host confirm its owner is the invoking
   UID/GID and pre-existing repository files are unchanged.
5. rebuild, reopen, and repeat steps 2–4. Confirm the Go cache marker remains.
6. Close the container and use the documented volume cleanup command when the
   cache is no longer wanted.

The empty `customizations` object is optional. Editor-specific extensions or
settings may be placed only below it; removing the whole object must not affect
builds, CLI startup, identity, lifecycle, mounts, or workspace behavior.

Unsupported boundaries include Docker-based UID mutation, combined translation
mechanisms, macOS, Windows, WSL2, arm64 Podman hosts, other clients/editors,
Podman API emulation, SELinux relabeling, and remote filesystems. Diagnose host
filesystem policy rather than adding privilege, recursive ownership repair, or
world-writable modes.

## Threat Boundaries & Security Controls

| Threat Boundary | Implemented Technical Control | Remaining Residual Risks |
|---|---|---|
| Untrusted Repository Isolation / Safe Mode | Dedicated `--safe-mode` flag suppresses all lifecycle hooks (`postCreateCommand`, etc.), blocks host provider credential grants (`E_SAFE_MODE_DENIED`), and enforces clean image state. | Local developer must explicitly invoke `--safe-mode` when opening untrusted repositories. |
| Time-of-Check to Time-of-Use (TOCTOU) | Source paths, devices, inodes, and file digests are re-validated immediately before atomic directory fsync and output replacement. | Host filesystem races between generation and container execution. |
| Socket Mount Disclosure | Container engine daemon sockets (`*.sock`) are strictly prohibited in mount sources and targets (`E_PROHIBITED_MOUNT`). | Subprocesses attempting to create custom sockets inside workspace paths. |
| Host Path Traversal & Symlink Escape | Mount paths are canonicalized with `realpath`, prohibited from containing `..` or symlinks (`E_PATH_TRAVERSAL`, `E_SOURCE_LINK`), and restricted to allowed workspace bounds. | Symlinks inside container workspace created after container startup. |
| Grant Scope & Cross-Project Leakage | Identity binding uses canonical paths, device/inode hashes, Git worktree/commit roots, and exact plan fingerprints. | Host UID/GID reuse or unobserved directory move-and-return. |
| Writable Provider Path Escalation | Direct host writable mounts are prohibited; `read-write` mode enforces isolated current-user credential stores (`0700` dir / `0600` file) and emits security warnings. | Malicious container processes modifying isolated credentials before sync. |

