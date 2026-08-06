# Tests

Owns automated contract, image, integration, and regression tests. Contributors
changing behavior own corresponding coverage; the repository maintainer owns the
required check set. Tests must not require undocumented credentials or host paths.

- `contracts.sh` checks repository and implementation contracts and runs the
  deterministic build-wrapper, acquisition, and image-archive regressions.
- `provider-registry.sh` validates both provider contracts, stable resolver
  failures, all six built-ins, platform/mode compatibility, hostile registry
  mutations, deterministic plans, the reviewed access-boundary snapshot, and
  a 7th-provider JSON-only drop-in (proving data-driven registration without
  shell edits).
  It uses an installed Draft 2020-12 `jsonschema` command when available and
  always enforces the equivalent access-family constraint snapshot with `jq`,
  so the documented shell-and-`jq` toolchain remains sufficient offline.
- `provider-authorization.sh` uses isolated host state, real Git clones and
  linked worktrees, and `socat` pseudo-terminals to validate exact-plan grants,
  prompt snapshots, allow-once non-persistence, observed move/return and
  replacement identity, hostile record integrity, interrupted writes, private
  storage, concurrent writers, fail-closed diagnostics, listing, and immediate
  revocation. It also exercises a naturally resolved Codex read-only plan through
  once, persistent approval, listing, exact evaluation, read-write escalation,
  exact and project-wide revocation, and failure of the immediately following
  matching authorization evaluation. It is offline and uses only inert
  value-free fixtures.
  Allow-once remains invocation-local and is intentionally not accepted by the
  persistent-authorization credential interface; reusable replay-proof
  capability semantics remain outside this milestone.
- `provider-credentials.sh` creates runtime-only canaries and exercises every
  built-in adapter through persistent authorization, initial access, explicit
  stop/start recreation, applicable refresh/synchronization, active-session
  refusal, project revocation, and per-provider post-revocation denial. It also
  covers exact read-only mounts, both writable isolated stores, hostile
  siblings/types/metadata/source replacement, atomic import/sync failures, and
  scans retained output, state, repository diffs, caches, and the built image.
- `runtime-config.sh` creates a disposable committed project with fake provider
  state and exact approvals, then checks deterministic portable/local rendering,
  host-independent goldens, CLI `0.86.0`, closed generated shapes, mandatory
  output presence and type, disabled/single/mixed/multi-provider combinations,
  stale metadata, redaction, mode changes, revocation, missing environment and
  host-service prerequisites, unsafe credential sources, hostile input, CLI
  absence/version errors, a deterministic source-inode substitution, and
  handled-failure rollback across staging and publication. Expected negative
  statuses are internal.
- `image-inspect-archive.sh` generates classic Docker and OCI blob-layout
  fixtures and proves archive inspection fails closed for invalid layer coverage
  and prohibited content.
- `image-smoke.sh` exercises a loaded image's runtime contract and PID-1 signals.
- `child-image-static.sh` checks base/platform rejection, local image-ID trust,
  deterministic local/registry builder selection, and all four negative
  validator diagnostics without Docker; `child-image-inheritance.sh` builds the
  real Go child and hostile variants on each native C1-C3 row and emits an
  auditable success line for every rejection and PID-1 signal probe.
- `image-inspect.sh` audits metadata, packages, linkage, filesystem/layers, and
  optionally compares normalized evidence from two builds. Set `IMAGE_ARCHIVE`
  to audit a saved Docker or OCI archive directly; for a multi-platform OCI
  archive, also set `IMAGE_PLATFORM=linux/amd64` or `linux/arm64`.
- `rootless-bind-mount.sh` proves that C2's default non-root user can read and
  write a normally host-owned workspace without startup ownership changes.
- `devcontainer.sh` uses the pinned Dev Container CLI and the validation fixture
  under `tests/fixtures/devcontainer/` to verify V5's numeric mutation, workspace,
  Git, persistent HOME, privilege, and daemon-socket boundaries.
- `rootless-podman.sh` verifies V6's direct keep-id mapping, persistent HOME, and
  crun `keep-groups` access without Dev Container mutation.
- `workspace-identity.sh` and the shared fixture assertions verify V7's host-side
  ownership, Git operations, build output, namespace evidence, restart behavior,
  and unchanged pre-existing workspace metadata for both modes.
- `devcontainer-podman.sh` uses the checked-in project template with CLI `0.86.0`
  and rootless Podman. Separate matching and differing host identities verify
  V8's local base-ID trust, keep-id mapping, lifecycle reruns, named Go cache,
  full workspace, optional customizations, stop/reopen, and clean rebuild.

Local milestone completion uses
`./scripts/validate-milestone-local.sh ms-pf-0005`. Only successful rootless
Podman execution is a local runtime gate; Docker validation remains in GitHub
Actions and is not required to finish a milestone cycle. Because V8 covers both
identity translations, run the local command under a `1000:1000` account and a
nonmatching account against the same commit and shared evidence directory.

The runtime scripts use `IMAGE=cyclestone-base:1.0.0` by default. Native release
evidence is still required for every supported matrix row.

The repository-local acceptance command for
`ms-pf-0006-trusted-provider-registry` is `./tests/contracts.sh`. It is static,
requires only the documented shell toolchain and `jq`, uses no credentials, and
makes no network or provider-service request. Do not add this milestone to the
rootless-Podman runtime gate.

The same `./tests/contracts.sh` command is the local acceptance gate for
`ms-pf-0007-local-provider-authorization`. Authorization additionally requires
Linux `realpath`, `stat`, Git, `jq`, `sha256sum`, `flock`, `sync`, and test-only
`socat`; it uses one local account, so no intermediate nonzero multi-account
status is expected. No credential, network, container engine, or provider
service is used.

Secure-provider-credential qualification uses
`./scripts/validate-milestone-local.sh ms-pf-0008` under one non-root Linux
account with rootless Podman and crun. It builds the test image when absent.
Negative write, synchronization, and active-revocation commands are asserted
inside the test, so no intermediate nonzero aggregate status is expected and
the final command must return zero.

## Milestone ms-pf-0012-automate-testing Validation

Automated functional and compatibility testing qualification uses `./scripts/validate-milestone-local.sh ms-pf-0012`.

### Support Matrix
- **Base Host OS**: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS (with native `amd64` / `arm64` architectures)
- **Container Runtimes**: Rootless Podman 4.9.0+ (with crun OCI runtime) and rootful/rootless Docker.
- **Orchestration / Tooling**: Dev Container CLI 0.86.0.

### Local Test Commands
To execute the complete milestone functional and compatibility validation locally:
```bash
./scripts/validate-milestone-local.sh ms-pf-0012
```

### Runner Prerequisites
The local validation runner requires the following tools and configuration:
- Operating System: Native Linux (AMD64 / `x86_64` architecture)
- Running Account: Non-root user (with valid subordinate UID/GID range allocated in `/etc/subuid` and `/etc/subgid`)
- Installed Tools: `git`, `jq`, `podman`, `devcontainer` (v0.86.0), `socat`, `realpath`, `stat`, `sha256sum`, `flock`, `sync`, `base64`.
- Podman Configuration: Must be rootless and configured to use the `crun` runtime.

### Expected Skips
- Non-Linux/non-x86_64 host validation runs: Static checks (contracts, registry, child-image validation, runtime configuration) can run statically without full container execution. On environments missing Podman or matching setup, container-based tests are skipped if run outside the local runner.
- Environment check skips: Host-service validation probes (like Ollama connectivity checks) will display warning diagnostics and degrade/skip service synchronization rather than failing outright if service network ports are occupied or blocked.

### Reproduction of Failures
If any test suite fails during validation, follow these steps to reproduce and diagnose:
1. Examine the corresponding log file collected under `dist/evidence/ms-pf-0012/local/<identity_case>/` (e.g., `contracts.log`, `provider-registry.log`, `provider-authorization.log`, `child-image-static.log`, `runtime-config.log`, `provider-credentials.log`, `rootless-podman.log`, or `devcontainer-podman.log`).
2. Verify that no raw credentials or host secrets have leaked into the evidence log. The validation script automatically scrubs hex/base64 credential values.
3. Run the specific failing test suite script directly with verbose mode or check the internal assertions. For instance, for credential failures, run `tests/provider-credentials.sh` manually.
4. Clean up any left-over container or volume artifacts using `podman rm` and `podman volume rm` before retrying validation.

## Milestone ms-pf-0014-templates-examples-documentation Validation

Templates, examples, and documentation qualification uses
`./scripts/validate-milestone-local.sh ms-pf-0014`. It runs static contract
checks, documentation command validation, child-image static checks, and
provider example validation (resolution and noninteractive fail-closed).
SDK example builds (Go, Node.js, .NET) run when `BASE_IMAGE` and a container
engine are available; otherwise they are skipped.

### Additional Tests

- `examples-build.sh` validates all five example projects. Provider examples
  (Codex, Ollama) are checked statically through `resolve-providers.sh` and the
  noninteractive fail-closed authorization path. SDK examples are built and
  contract-checked (USER, WORKDIR, ENTRYPOINT, CMD, identity, Cyclestone, and
  SDK version) when a container engine and base image are available.
- `scripts/validate-docs.sh` extracts fenced shell code blocks from markdown
  files under `docs/`, `examples/`, and `templates/`, and validates them with
  `sh -n` syntax checks and script-existence/flag verification. Interactive
  approval blocks, placeholder blocks, and install-via-curl blocks are skipped
  with clear diagnostics.

- `mvp-qualification.sh` — verify the MVP delivery roadmap, validation checklist,
  compatibility deferred-evidence documentation, and security confirmation
  decision are complete and internally consistent.
