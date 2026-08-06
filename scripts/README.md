# Scripts

Owns shared build, installation, entrypoint, and validation scripts. Script
authors own implementation and tests; `@patrick-folster` approves changes that
alter public image behavior. Image-only logic belongs beside its image instead.

`build-base.sh` is the supported local Buildx entrypoint. It validates platforms
and release metadata and produces either one Docker-loaded native image or a
multi-platform OCI archive; it never pushes.

`build-base-podman.sh` is the rootless-Podman-only native fixture builder used
by local milestone qualification. Its `--iidfile` result is the independent
content-addressed identity against which the resulting local tag is checked.

`validate-milestone-local.sh ms-pf-0005` is the cycle-completion gate for the
project Dev Container milestone. Run it from the host, once as a `1000:1000`
account and once as a nonmatching account. It requires both results for the same
commit and does not require or invoke Docker. Both accounts need CLI `0.86.0`
on `PATH` and the same absolute `EVIDENCE_DIR`. The first passing case returns
nonzero until the peer exists; only the second passing case emits the aggregate
success result.

`build-child-image.sh` builds and loads the reviewed Go child fixture for exactly
one native platform. It requires either a canonical Cyclestone GHCR manifest
digest or an explicitly local content-addressed image ID and never pushes.

`validate-base-native.sh` is the CI-facing C1-C3 runner. It rejects the wrong
host, architecture, or Docker privilege mode before building, then records the
native build, smoke, inspection, reproducibility, non-provider, bind-mount, and
Dev Container evidence applicable to that supported row.
It also builds, executes, and negatively validates the child image, writing the
result into that row's evidence directory.

`resolve-providers.sh PROJECT PROVIDER_ID PLATFORM` validates the version-1
project request and the repository-owned version-1 trusted registry, then emits
one compact canonical access plan. It accepts no registry argument, expands no
host path, reads no environment value, and applies no mount or service access.
Failures use stable `ERROR E_*` identifiers without echoing hostile values.

`devcontainer-permissions.sh` is the supported repository-local authorization
interface for interactive review, exact persistent evaluation, audit-safe
listing, and exact or project-wide revocation. It requires Linux `realpath`,
`stat`, Git, `jq`,
`sha256sum`, `flock`, `sync`, and the standard GNU file/text utilities named by
its startup check. It validates stored canonical bodies, recomputed hashes, and
deterministic IDs under lock; it authorizes resolver plans but applies no
provider access. See `docs/provider-authorization.md`.
It is not a Cyclestone subcommand, wrapper, alias, or shadow binary, and no
Cyclestone `devcontainer` command namespace is provided by this repository.
Codex read-only and read-write plans travel through this same evaluator and are
never treated as interchangeable grants.

`provider-credentials.sh` is the Linux/rootless-Podman materialization
interface for exact-file mounts, name-only environment forwarding, reviewed
host-service metadata, and project/provider isolated stores. It re-evaluates a
persistent authorization at every operation, imports and synchronizes only the
reviewed regular `auth.json`, tracks sessions for deterministic revocation, and
emits no credential values. See `docs/provider-credentials.md`.

`devcontainer-generate.sh PROJECT_ROOT REQUEST_FILE [--dry-run] [--replace]`
and `devcontainer-validate.sh PROJECT_ROOT REQUEST_FILE` are the supported
repository-local runtime-configuration interfaces. They reuse permissions,
provider resolution, and credential preparation, emit canonical portable and
ignored local output, independently bind mount sources to the fresh grant and
prepared isolated-store identity, and parse the result with Dev Container CLI
`0.86.0`. They are not upstream Cyclestone subcommands. See
`docs/runtime-configuration.md`.

`validate-milestone-local.sh ms-pf-0008` is the single-account credential gate.
It requires the tools checked by the script, rootless Podman with crun, and no
real provider account. It builds a verified local base image when one is not
supplied and retains attributable, value-free evidence. Expected negative
probes are handled inside the test; the aggregate command must return zero.

`validate-milestone-local.sh ms-pf-0009` is the single-account generator gate.
It checks the named host tools, rootless Podman/crun prerequisites, pinned CLI,
provider contracts, goldens, hostile inputs, redacted previews, mandatory
generated outputs, and handled-failure rollback at each publication stage.
