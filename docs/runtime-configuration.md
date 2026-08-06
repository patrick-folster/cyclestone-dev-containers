# Generated Runtime Configuration

Cyclestone keeps consent, credential preparation, configuration generation, and
container startup as separate boundaries:

1. `scripts/devcontainer-permissions.sh review` records a local exact-plan grant.
2. `scripts/provider-credentials.sh prepare` revalidates it and emits a
   value-free plan from the trusted adapter.
3. `scripts/devcontainer-generate.sh PROJECT_ROOT REQUEST_FILE` renders the
   effective intersection.
4. `scripts/devcontainer-validate.sh PROJECT_ROOT REQUEST_FILE` repeats request,
   registry, grant, source, variable, service, template, metadata, and CLI checks
   without replacing output.
5. The user explicitly starts the container with the ignored local output.

These are repository-local scripts, not `cyclestone devcontainer` subcommands.
The pinned upstream binary is not wrapped, shadowed, or extended.

## Outputs and replacement

Generation owns exactly two project-relative destinations:

- `.devcontainer/devcontainer.json` is reproducible and eligible to commit. It
  contains the structural template and SHA-256 identities of the canonical
  request, trusted registry, and template.
- `.cyclestone/runtime/devcontainer.json` is ignored local state. It adds only
  authorized bind sources, exact `${localEnv:NAME}` inheritance, and reviewed
  host-service metadata. It may contain local absolute paths, but never values.

Portable metadata has no timestamp, project identity, grant fingerprint/body,
host path, or secret-derived value. Both outputs are canonical, stably ordered
JSON. Identical reruns are byte-for-byte unchanged.

Use `--dry-run` to preview creates or a unified diff. Portable managed content
uses project-relative labels; machine-local content and unmanaged bodies are
redacted. Dry-run performs normal authorization and credential preparation, so
it may create or synchronize an isolated local credential store, but it never
creates or replaces either generated output. Current generator-managed output
is replaced normally. An unrecognized file requires `--replace` and is never
overwritten silently. Generation validates sources before creating missing
output directories, stages both outputs, fsyncs same-directory temporary files,
then rechecks source identity immediately before the final renames. Every handled
validation, render, staging, fsync, and rename failure restores the prior pair.
A host crash between the two final renames is a residual multi-file atomicity
limit; `validate` detects the resulting stale output.

## Closed merge and access policy

Projects control only logical provider ID, enabled state, and mode. They cannot
supply JSON fragments, mount strings, paths, destinations, environment names or
values, endpoints, runtime arguments, lifecycle commands, Features,
customizations, or definitions. The structural template owns build, users,
workspace, lifecycle, cache, and security arguments. Provider access is an
additive allow-listed layer.

Enabled providers resolve in ID order. Every one needs a fresh persistent exact
grant and valid credential runtime plan. Disabled providers contribute nothing.
Missing, denied, stale, mode-changed, or narrower grants fail before output and
never contribute partial access. Duplicate environment names or mount targets
and reserved destinations fail closed; there is no privilege-bearing precedence.
For file-backed access, generation independently derives the only acceptable
host file or grant-fingerprint-bound isolated store from that fresh authorization;
an otherwise well-formed helper result cannot redirect the mount source.

File sources are canonical non-links bound to device/inode evidence during
rendering and rechecked after staging and backup preparation, immediately before
the first publication rename. Substitution between generation and later
container use remains possible: review local output and revalidate immediately
before startup. Revocation prevents the next supported generation or validation,
but cannot retract an existing container or bytes already read.

## Validation and startup

Validation requires both generated destinations to be regular non-link files,
checks their closed shapes and provenance, freshly resolves authorization and
credential prerequisites, rerenders both documents, and requires byte equality.
Diagnostics use stable categories for tools/CLI version, request JSON/schema/
path, permission, prerequisite, runtime plan, conflict, destination, source,
missing or malformed output, stale metadata, CLI parsing, unmanaged output, and
pair inconsistency, and writes. The supported parser is Dev Container CLI
`0.86.0`.

```sh
devcontainer --docker-path podman up \
  --workspace-folder "$PWD" \
  --config "$PWD/.cyclestone/runtime/devcontainer.json"
```

The inherited contract remains CLI `0.86.0`, `developer`,
`updateRemoteUserUID=false`, `/workspace`, the child build/lifecycle/cache,
`keep-id:uid=1000,gid=1000`, and `no-new-privileges`. Provider plans remain
version 2 with fresh authorization, canonical sources, isolated writable stores,
and value-free runtime output.

Run `scripts/validate-milestone-local.sh ms-pf-0009` as one non-root Linux
account. It verifies the named Git/jq/GNU tools, socat, CLI `0.86.0`, rootless
Podman with crun, and subordinate IDs. Fixtures use fake credentials and need no
provider account or network API. Expected hostile, unmanaged, missing-grant,
and fault-injection probes return nonzero internally; the aggregate returns zero.

## Threat Boundaries & Security Controls

| Threat Boundary | Technical Control | Residual Risks |
|---|---|---|
| Safe Mode Isolation | `--safe-mode` flag suppresses all lifecycle commands (`postCreateCommand`, etc.), blocks host provider credential grants, and enforces clean container metadata. | Manual invocation required when analyzing untrusted repositories. |
| Environment Variable Secret Leakage | Strict allowlisting (`ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`, `OLLAMA_HOST`) and redaction of machine-local values and secrets from output logs and dry-run previews. | User environment variables manually passed to sub-shells inside container. |
| Time-of-Check to Time-of-Use (TOCTOU) | Pre-publication re-validation of mount sources (path, device, inode) immediately before same-directory atomic replacement and directory fsync. | Host filesystem mutation after container engine launch. |
| Engine Socket Exposure | Engine daemon sockets (`docker.sock`, `podman.sock`, `*.sock`) are strictly prohibited in mount sources and destinations (`E_PROHIBITED_MOUNT`). | Nested socket forwarding manually configured inside container user scripts. |
| Host Path Traversal & Symlink Escape | Mount sources and destinations reject `..` traversal and symlink sources (`E_PATH_TRAVERSAL`, `E_SOURCE_LINK`), canonicalizing paths against allowed scopes. | Internal container symlink creation inside mounted volumes. |
| Writable Provider Path Escalation | Direct host writable mounts are prohibited; `read-write` mode requires an isolated current-user store (`0700`/`0600`) and issues security warnings on review. | Modified credentials in isolated store before host sync. |

