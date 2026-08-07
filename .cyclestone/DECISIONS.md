# Architecture Decisions

This file is append-only and chronological. New decisions may supersede earlier
ones but do not rewrite them.

## 2026-07-31 — D-001 Repository and image identity

- **Context:** The configured origin is private-named while the milestone fixes a
  public OCI family.
- **Outcome:** The canonical source identity is
  `git@github.com:patrick-folster/cyclestone-dev-containers-private.git`; the
  canonical image family is `ghcr.io/patrick-folster/cyclestone-dev`. Visibility
  of either is a separate operational concern.
- **Rationale:** This records configured reality without renaming a remote or
  inferring registry visibility.
- **Consequences:** Source labels use the canonical repository; publication does
  not occur in this milestone.
- **Supersession:** A reviewed identity migration with redirects and consumer
  migration guidance may supersede this entry.

## 2026-07-31 — D-002 Base distribution

- **Context:** The base needs maintained packages, small images, development-tool
  compatibility, and both target architectures.
- **Outcome:** Image line `1.x` selects Ubuntu 24.04 LTS, pinned by OCI digest at
  build/release time.
- **Rationale:** Standard maintenance through May 2029, official `amd64`/`arm64`
  images, glibc, `apt`, and broad tooling compatibility outweigh smaller Alpine
  or Debian-slim footprints.
- **Consequences:** A distribution/LTS move is evaluated as a major change unless
  proven entirely compatible under the version policy.
- **Supersession:** A reviewed major-line decision with complete matrix validation.

## 2026-07-31 — D-003 Platform support

- **Context:** Broad host and architecture claims lack uniform UID, runtime, and
  artifact behavior.
- **Outcome:** Support is bounded to native Ubuntu 22.04/24.04 Linux with the exact
  `amd64`/`arm64` Docker combinations C1–C3. Rootless Podman is experimental; all
  other hosts/architectures are unsupported.
- **Rationale:** The base and Cyclestone have both target artifacts, and each
  supported row has an explicit native validation method.
- **Consequences:** Absence is never support; new combinations require a complete
  row and validation evidence.
- **Supersession:** A reviewed compatibility update and appropriate SemVer change.

## 2026-07-31 — D-004 Filesystem and process interface

- **Context:** Consumers need predictable non-root paths without universal host
  ownership promises.
- **Outcome:** The stable interface is user `developer` (`1000:1000` default),
  `/home/developer`, `/workspace`, XDG/Cyclestone directories, exhaustive
  environment defaults, required OCI labels, and an exec-forwarding entrypoint.
  Runtime UID/GID mutation is not promised.
- **Rationale:** This gives child images stable, writable paths while leaving
  package/helper internals replaceable.
- **Consequences:** Contract overrides require explicit compatibility, migration,
  and versioning notes.
- **Supersession:** A reviewed contract decision; incompatible changes require a
  major line or documented emergency security migration.

## 2026-07-31 — D-005 Cyclestone acquisition source and pin

- **Context:** Installation must not depend on a mutable URL or locally invented
  integrity value.
- **Outcome:** Pin public GitHub Release `v0.0.2`, its annotated tag commit,
  publisher checksum document, and exact Linux `amd64`/`arm64` artifact hashes.
  Acquisition is credential-free and fail-closed before extraction/install.
- **Rationale:** Upstream publishes architecture-specific archives and SHA-256
  checksums; both supported archives were independently verified on this date.
- **Consequences:** Any pin/source/map/checksum change is reviewed. Signature or
  provenance verification remains a compatible future hardening measure.
- **Supersession:** A reviewed acquisition update with fresh publisher evidence.

## 2026-07-31 — D-006 Independent image versioning

- **Context:** Coupling image tags to Cyclestone would obscure OS and contract
  changes.
- **Outcome:** Images use independent Semantic Versioning and expose Cyclestone
  version separately in environment/OCI metadata. Digests are immutable release
  references; convenience tags are not.
- **Rationale:** Each independently evolving contract receives accurate change
  classification and rollback identity.
- **Consequences:** The highest applicable OS/tool/provider/template/contract or
  security classification determines the image version.
- **Supersession:** A reviewed version-policy decision with consumer migration.

## 2026-07-31 — D-007 Trust posture

- **Context:** Development containers execute hostile project content near host
  source and credentials.
- **Outcome:** Workspaces are untrusted; startup does not evaluate them; operation
  is non-root; no credentials, privilege, broad sockets, or mounts are automatic;
  build/download inputs are pinned and validated. Team functionality receives no
  implicit identity or tenant trust.
- **Rationale:** Least authority limits damage while keeping explicit user-approved
  runtime extension possible.
- **Consequences:** Every provider, service, or team feature needs a new boundary
  review before support.
- **Supersession:** Only a reviewed security decision; weakening requires explicit
  rationale and a major compatibility assessment.

## 2026-07-31 — D-008 MVP boundary

- **Context:** The first milestone establishes contracts, not speculative tools.
- **Outcome:** Include the skeleton, contracts, threat model, matrix, policy,
  acquisition evidence, and static tests. Exclude image implementation/publication,
  providers, extra runtimes, orchestration, and team functionality.
- **Rationale:** Later implementation can target stable interfaces without empty
  stubs or unrelated dependencies.
- **Consequences:** Deferred capabilities remain unsupported and must enter through
  documented extension and review rules.
- **Supersession:** Later milestone decisions may add scoped capabilities without
  erasing this historical boundary.

## 2026-07-31 — D-009 Deferral audit

- **Context:** Unowned deferrals create implicit platform and security promises.
- **Outcome:** No unresolved or deferred architecture decision remains for image
  line `1.x`; excluded combinations/capabilities are explicitly experimental or
  unsupported. A future deferral is invalid without an accountable maintainer
  handle and ISO-8601 deadline.
- **Rationale:** A closed allow list is clearer than placeholder decisions.
- **Consequences:** Unsupported items do not block the foundation and gain no
  compatibility or trust promise.
- **Supersession:** Append a dated, owned decision when a concrete proposal enters
  validation.

## 2026-07-31 — D-010 Reviewed Ubuntu base pin

- **Context:** D-002 requires the Ubuntu 24.04 base to be pinned by a reviewed
  multi-architecture OCI identity before implementation.
- **Outcome:** Image line `1.x` pins Docker Official Image index
  `sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90`,
  with amd64 manifest `sha256:52df9b1ee71626e0088f7d400d5c6b5f7bb916f8f0c82b474289a4ece6cf3faf`
  and arm64 manifest `sha256:7f622ca8766bccb22f04242ecb6f19f770b2f08827dc4b8c707de5e78a6da7ab`.
- **Rationale:** The index observed on 2026-07-31 contains both supported native
  platforms and makes the base input and metadata label auditable.
- **Consequences:** Base updates change all reviewed pins together and require
  clean native matrix, package-closure, size, and compatibility review.
- **Supersession:** A later reviewed security/base refresh with replacement index
  and platform-manifest evidence.

## 2026-07-31 — D-011 Git package runtime exception

- **Context:** The milestone requires Git while otherwise excluding project
  runtimes. Ubuntu 24.04's `git` package has a hard dependency on Perl even with
  recommended packages disabled.
- **Outcome:** Permit only the transitive `perl`, `perl-base`, `perl-modules-*`,
  `libperl*`, and `liberror-perl` closure required by Ubuntu's Git package. No
  Perl package is a direct allow-list entry, and no other language runtime is
  permitted.
- **Rationale:** Using the maintained distribution Git package preserves security
  updates and complete Git behavior; copying partial Git binaries or breaking apt
  dependency state would be less auditable.
- **Consequences:** Inspection proves Git still declares the dependency and fails
  on an expanded Perl package set. Cyclestone remains standalone.
- **Supersession:** A reviewed Git packaging choice that removes or changes the
  runtime dependency, with complete native validation.

## 2026-07-31 — D-012 Native validation execution

- **Context:** Repeated local milestone cycles could validate only Fedora amd64
  and could not supply the native C1-C3, rootless, arm64, Dev Container, or
  combined OCI evidence required by D-003.
- **Outcome:** A manually dispatched GitHub Actions workflow maps C1-C3 to native
  Ubuntu runners, installs a pinned Dev Container CLI, validates C2 against a
  rootless daemon and host-owned bind mount, and retains attributable evidence.
  A separately gated Docker Build Cloud job creates the non-published combined
  amd64/arm64 OCI archive.
- **Rationale:** Qualification must change execution environments rather than
  repeat unsupported-host diagnostics, while keeping image acquisition
  credential-free and publication outside this milestone.
- **Consequences:** Native jobs are release evidence only when their runner and
  daemon assertions pass. Cloud-builder credentials remain workflow-only and are
  not image inputs. Failure of the C2 mount probe is a contract finding, not a
  reason to change ownership during image startup.
- **Supersession:** A reviewed validation topology that preserves every supported
  row and produces equally attributable native evidence.

## 2026-07-31 — D-013 Repeated OCI layer references

- **Context:** Native C2 inspection encountered Docker's canonical empty-layer
  blob at multiple positions in one OCI manifest. The initial audit rejected any
  repeated descriptor even though each position had a matching configuration
  diff ID and OCI descriptors are content-addressed references.
- **Outcome:** Permit repeated OCI blob descriptors while retaining the complete
  ordered descriptor count and auditing every occurrence against its positional
  diff ID, digest, size, media type, archive safety, and prohibited content.
- **Rationale:** Blob identity is not stack-position identity. Deduplicating or
  rejecting a valid content-addressed reference would make inspection dependent
  on exporter behavior without adding security coverage.
- **Consequences:** Zero, missing, extra, corrupt, unreadable, count-mismatched,
  unsafe, and prohibited-content layers still fail closed. The regression suite
  positively covers repeated references and keeps hostile coverage fixtures.
- **Supersession:** A later OCI requirement may tighten this policy only with a
  standards-compatible way to distinguish invalid repetition from blob reuse.

## 2026-07-31 — D-014 Rootless workspace permission evidence

- **Context:** Rootless Docker maps its host user to container UID 0 and maps
  nonzero container identities into `/etc/subuid`; therefore a host-owned
  mode-0755 workspace is not automatically writable by image user `developer`.
- **Outcome:** C2 validation computes `developer`'s mapped host UID and grants
  only that identity a POSIX ACL on the disposable host-owned workspace before
  mounting it. The probe verifies bidirectional I/O and unchanged ownership.
- **Rationale:** Explicit host permission is the runtime's responsibility under
  the image contract. A narrow ACL demonstrates the supported path without
  world-writable permissions, container root, or startup ownership mutation.
- **Consequences:** C2 does not promise transparent numeric UID alignment. Users
  must arrange suitable host permissions or an equivalent runtime mechanism for
  bind mounts; the image remains non-root and never changes mount ownership.
- **Supersession:** A reviewed idmapped-mount or runtime mechanism may replace
  the ACL when it provides equivalent non-root access without host ownership
  mutation.

## 2026-07-31 — D-015 Deterministic Dev Container identity validation

- **Context:** Dev Container CLI 0.86.0 does not support the previously supplied
  `--no-lockfile` argument, and its default remote-user UID update can replace the
  image's declared numeric identity according to the host runner.
- **Outcome:** V5 uses only supported `up` arguments and sets
  `updateRemoteUserUID` to false in its disposable validation fixture.
- **Rationale:** The probe must exercise the image's `developer` identity rather
  than a host-dependent derived identity, and its command line must match the
  pinned CLI's actual interface.
- **Consequences:** The fixture may create its normal disposable metadata, but it
  does not rewrite the image user. Runtime bind-mount permissions remain an
  explicit host/runtime responsibility.
- **Supersession:** A later pinned CLI may change this only with equivalent,
  deterministic evidence of the image-supplied user contract.

## 2026-07-31 — D-016 Separate supported workspace identity modes

- **Context:** Host-owned bind mounts need numeric identity alignment, while
  D-003, D-004, and D-015 exclude supported Podman and Dev Container mutation.
- **Outcome:** Image line `1.x` adds two independent, Linux-amd64 modes. C4 uses
  rootful Docker and Dev Container CLI `0.86.0` to mutate the fixed `developer`
  name to the invoking UID/GID. C5 uses rootless Podman 4.9 with crun and
  `keep-id:uid=1000,gid=1000` to map the invoking identity to the unchanged image
  account. Combining these mechanisms is unsupported and diagnosed.
- **Rationale:** Each runtime supplies one ownership translation layer while the
  image stays non-root, preserves the username, and performs no ownership repair.
- **Consequences:** C4/C5 require native V5–V7 evidence, separate HOME volumes,
  correct subordinate IDs for Podman, and explicit host permission for
  supplementary groups. Other clients, Podman versions/runtimes, filesystems,
  and mode combinations remain unsupported. D-003, D-004, and D-015 are
  superseded only for these bounded rows; C1–C3 and the image defaults are
  unchanged.
- **Supersession:** A reviewed compatibility decision with equally explicit
  identity, persistence, filesystem, security, and native validation evidence.

## 2026-07-31 — D-017 Supported child-image inheritance pattern

- **Context:** Project images need an SDK extension pattern without weakening the
  base contract or relying on a base release digest that has not been published.
- **Outcome:** The supported example installs checksum-pinned Go 1.26.5 archives
  for native `linux/amd64` and `linux/arm64`, restores the complete inherited
  execution contract, and mounts project source at runtime. Consumers must use
  the canonical GHCR manifest digest; repository tests may inject only a loaded
  base's content-addressed Docker image ID as the trust identity, verify a loaded
  tag resolves to it for BuildKit, and identify that mechanism as local-only.
- **Rationale:** A bounded SDK exercises privileged installation, architecture
  selection, command inheritance, and non-root use while avoiding mutable package
  repositories, source capture, publication, or a universal runtime manager.
- **Consequences:** C1-C3 each build and run the child and reject root, HOME,
  workdir, and Cyclestone regressions. Deprecated inherited elements remain for
  all later minors in a major line and incompatible removal waits for a major
  release except under the existing urgent security process.
- **Supersession:** A reviewed SDK or inheritance-contract decision with complete
  native architecture, supply-chain, migration, and Semantic Versioning evidence.

## 2026-08-01 — D-018 Podman-backed project Dev Container mode

- **Context:** A reusable project workflow needs Dev Container lifecycle and
  rebuild behavior while preserving C5's rootless workspace ownership and
  D-017's child-image trust identity.
- **Outcome:** C6 selects rootless Podman directly on native Linux amd64 with
  Dev Container CLI `0.86.0`, keeps image user `developer:1000:1000`, sets
  `updateRemoteUserUID=false`, and uses only
  `keep-id:uid=1000,gid=1000`. Consumers supply the canonical GHCR manifest
  digest. Native fixtures may use a loaded locator only after it resolves to a
  separately verified content-addressed image ID. The only default persistence
  is a named, disposable Go build cache.
- **Rationale:** One namespace translation works for both matching and differing
  host identities without changing the image account, repairing ownership, or
  exposing an engine socket. Direct client selection makes host orchestration
  explicit.
- **Consequences:** V8 records both identity cases, actual conflicting
  `updateRemoteUserUID=true` behavior, lifecycle reruns, cache persistence,
  reopen/rebuild, and optional-customization removal. Repository lifecycle code
  remains untrusted and requires review before consent. Other clients, editors,
  platforms, sockets, provider additions, and combined identity mechanisms are
  unsupported.
- **Supersession:** A reviewed compatibility decision with equivalent identity,
  lifecycle, persistence, supply-chain, security, and native evidence.

## 2026-08-01 — D-019 Local-first milestone qualification

- **Context:** Cycle 001 could not finish because its mandatory V8 result was
  available only through a GitHub-hosted job, while static checks could not
  substitute for real rootless-Podman behavior.
- **Outcome:** Milestone-cycle completion uses checked-in host-native validation.
  For C6/V8, only rootless Podman must pass locally: the gate builds through
  Podman, validates both matching and differing identities against one commit,
  and retains local evidence. Docker checks remain GitHub Actions coverage and
  are not prerequisites for finishing a milestone cycle.
- **Rationale:** A contributor must be able to establish the acceptance result
  without an external CI service, while retaining empirical identity, lifecycle,
  ownership, rebuild, and trust-chain evidence.
- **Consequences:** The local command must run outside containers that prevent a
  writable user runtime directory or user namespaces. GitHub workflows may
  repeat or extend coverage, but cannot be the sole source of a cycle-completion
  verdict. Future milestone criteria must name repository-local verification.
  This decision narrowly supersedes D-017 for C6 fixtures: a rootless Podman
  build's `--iidfile` is the independent expected image ID, and the mutable test
  tag must resolve to that ID before use. Consumer digest requirements remain.
- **Supersession:** A reviewed local execution model that retains equally
  attributable evidence without requiring an external service.

## 2026-08-01 — D-020 Stage build-only package input internally

- **Context:** Native rootless-Podman qualification on an enforcing SELinux host
  denied a final-stage `RUN --mount=type=bind` read of the repository package
  allow-list because the source retained its `user_home_t` host label.
- **Outcome:** Copy the allow-list into the non-final acquisition stage and bind
  it into the final-stage package-install step from that internal stage.
- **Rationale:** Cross-stage input preserves the single reviewed allow-list,
  avoids disabling SELinux or relabeling project source, and keeps the build-only
  file out of every final-image layer.
- **Consequences:** Static contracts retain the cross-stage mount, and native
  Podman validation must prove the build on enforcing SELinux as part of C6/V8.
- **Supersession:** A reviewed build-input mechanism with equivalent host-label
  independence and final-layer exclusion.

## 2026-08-01 — D-021 Use selected-engine exec after Dev Container startup

- **Context:** In the qualified host toolchain, Dev Container CLI `0.86.0`
  rejected option-like command arguments and then forwarded its own `exec`
  subcommand token as the container executable even for argument-free commands.
- **Outcome:** The CLI performs build, start, lifecycle startup, reopen, and
  rebuild. Runtime assertions and explicit hook reruns use the selected engine's
  direct `exec` against the `containerId` returned by `up`.
- **Rationale:** Engine exec is deterministic, preserves the configured container
  user, and avoids an empirically broken CLI path without changing runtime,
  namespace, privilege, mount, or lifecycle behavior.
- **Consequences:** Static contracts reject `devcontainer exec`, the Podman
  fixture retains compound checks in an auditable helper, and documentation
  records the bounded CLI limitation and exact engine command.
- **Supersession:** A later pinned CLI may change the syntax only with equivalent
  host-native execution evidence.

## 2026-08-01 — D-022 Keep local-ID rebuilds local

- **Context:** Dev Container CLI `0.86.0` adds `--pull` during a clean rebuild;
  rootless Podman rejected both a short local locator, because resolution could
  not prompt, and the verified image ID, because an always-pull policy cannot be
  applied to an ID.
- **Outcome:** The fixture still proves that its disposable tag resolves to the
  independently captured `--iidfile` value, then supplies that verified image
  ID as `BASE_IMAGE_REF`. The local fixture appends `--pull=never` through
  `build.options` for the required no-cache rebuild.
- **Rationale:** An image ID is a local content address and cannot be refreshed
  from a registry. The later explicit option overrides the CLI's incompatible
  pull request without trusting a mutable tag or weakening the no-cache rebuild.
- **Consequences:** The tag remains only a fixture identity check. The pull
  override is confined to the generated native-test workspace and does not alter
  the reusable consumer template's registry-digest-pinned base behavior.
- **Supersession:** A reviewed local image transport with equivalent identity
  verification and noninteractive rebuild behavior.

## 2026-08-01 — D-023 Distinguish null Podman metadata from credentials

- **Context:** The V8 evidence scan matched Podman's literal
  `authorization: null` capability field after all runtime checks passed.
- **Outcome:** The scan excludes only an exact null authorization field while
  retaining failure for non-null authorization values and every other prohibited
  credential pattern. A failure reports affected filenames without echoing
  potentially sensitive matching content.
- **Rationale:** Null capability metadata contains no credential. Printing actual
  matches during diagnosis could itself expose the material the gate protects.
- **Consequences:** Normal Podman information is retainable as required evidence,
  while credential-bearing configuration or output continues to fail closed.
- **Supersession:** A structured evidence-redaction or secret-scanning mechanism
  with equivalent or stronger coverage and safe diagnostics.

## 2026-08-01 — D-024 Trusted provider registry boundary

- **Context:** Projects need logical provider selection without gaining control
  of credential values, host paths, container destinations, mounts, service
  endpoints, or custom integration definitions.
- **Outcome:** Registry version 1 is repository-owned reviewed code and contains
  exactly `claude`, `codex`, `generic-environment`, `ollama`, and `opencode`.
  Projects provide only version, logical ID, enabled state, and mode. Resolution
  validates raw duplicate keys, exact registry boundaries, platform and mode,
  then emits a deterministic value-free plan without applying access.
- **Rationale:** Separating untrusted intent from trusted access metadata makes
  every expansion reviewable and prevents repository configuration from turning
  a logical request into arbitrary host access.
- **Consequences:** Version-1 resolution is Linux-only static qualification.
  Filesystem application still requires runtime canonicalization and symlink
  protection; provider CLIs, mounts, environment injection, and service access
  remain unsupported until a separate runtime decision and evidence exist.
- **Supersession:** A reviewed registry/runtime decision with schema migration,
  boundary snapshot, security analysis, release classification, and applicable
  native evidence.

## 2026-08-01 — D-025 Local provider authorization boundary

- **Context:** Value-free provider requests need local consent without allowing
  repositories to select access details or inherit stale approval.
- **Outcome:** Linux authorization binds the complete canonical registry plan to
  a versioned project identity and requires exact fingerprint equality. Identity
  combines canonical worktree path, device/inode data, and, for Git, canonical
  per-worktree/common directories with their filesystem identities, object
  format, and root-commit-set evidence. Moves, replacements, clones, and sibling
  worktrees require fresh approval. Grants live below the local Cyclestone data
  directory in a locked 0700/0600 versioned store; allow-once is emitted only by
  its approving invocation and is never persisted.
- **Rationale:** No single path, Git field, or history identifies a checkout.
  Conservative combined identity and full-plan equality make every effective
  expansion and checkout substitution an approval boundary.
- **Consequences:** The repository-local command authorizes but does not apply a
  plan. It revalidates identity and resolution before emission, rejects unsafe
  storage and noninteractive approval, and stores no environment values. The
  pinned upstream Cyclestone v0.0.2 has no extension point for the requested
  `cyclestone devcontainer permissions` spelling; wrapping it is forbidden.
  Read-only remains representable but registry v1 has no approved read-only
  provider. Device/inode reuse and races after authorization remain residual;
  future materialization must canonicalize again at point of access.
- **Supersession:** A reviewed CLI/runtime integration with equivalent exact-plan,
  project-identity, local-storage, revocation, race, and secret-exclusion controls.

## 2026-08-01 — D-026 Strict grant loading and observed-move retirement

- **Context:** Shape-valid local records could contain inconsistent canonical
  bodies, fingerprints, or deterministic IDs, and a checkout moved away and
  returned could regain its old path-scoped approval.
- **Outcome:** Every store load and locked use validates the closed schema,
  canonical UTC timestamp, recomputed identity and plan fingerprints, unique
  deterministic IDs, and exact record bodies. Pre-existing unsafe modes fail
  without repair. Observing the same project filesystem identity at a different
  canonical identity during authorization atomically retires its prior grants.
- **Rationale:** Local state is input, not authority by itself. Derived fields
  must be verified, and an observed identity transition must not leave approval
  that becomes valid again after a move-back.
- **Consequences:** Interrupted writes preserve the prior store. An unobserved
  move away and back remains indistinguishable if path and inode both return.
  Allow-once output is non-persistent but not replay-proof until a future
  materialization boundary defines an audience and atomic consumer.
- **Supersession:** A reviewed local-state or runtime-consumer design with equal
  or stronger integrity, move, storage, and one-time-consumption evidence.

## 2026-08-01 — D-027 Invocation-local allow-once milestone boundary

- **Context:** The authorization milestone has no provider-materialization
  consumer in which to bind an audience, expire a result, or atomically consume
  it a second time.
- **Outcome:** For this milestone, allow-once is sufficient only when the
  approving invocation emits the value-free authorization result, persists no
  grant, and every later authorization call requires fresh explicit approval.
  The emitted JSON is not a replay-proof or reusable capability.
- **Rationale:** Non-persistence and fresh later consent establish the local
  decision boundary without inventing runtime semantics that have no genuine
  consumer.
- **Consequences:** Audience binding, expiry, atomic one-time consumption, and a
  real second-consumption replay test are deferred to the provider
  materialization/runtime milestone. Denial, revocation, restrictive storage,
  exact-plan matching, and noninteractive fail-closed behavior remain required.
- **Supersession:** A reviewed provider-materialization/runtime decision with an
  identified consumer and empirical replay-resistance evidence.

## 2026-08-01 — D-028 Codex read-only authorization mode

- **Context:** Registry v1 represented read-only plans but had no reviewed
  provider definition with which to exercise approval and escalation naturally.
- **Outcome:** Codex supports both `read-only` and `read-write` authorization for
  its existing exact `${HOME}/.codex` to `/home/developer/.codex` directory
  boundary; `read-write` remains recommended for normal stateful sessions.
- **Rationale:** Read-only gives a meaningful least-mutation choice for existing
  authentication and configuration visibility without adding a source,
  destination, variable, service, provider, or project-controlled definition.
- **Consequences:** Both modes disclose the full reviewed directory to untrusted
  container-user processes. Read-only prevents host-state mutation but does not
  make credentials non-secret, guarantee that every Codex operation succeeds,
  or qualify runtime mount application. Exact plan matching requires fresh
  approval for either mode change. This supersedes only D-025's statement that
  registry v1 has no approved read-only provider.
- **Supersession:** A reviewed provider/runtime design with narrower credential
  separation or equally explicit read-only behavior and qualification evidence.

## 2026-08-01 — D-029 Script-only authorization interface and runtime deferral

- **Context:** The authorization boundary is complete as a repository-local
  decision service, while Cyclestone v0.0.2 neither needs nor provides a
  `devcontainer` command namespace or a provider-materialization consumer.
- **Outcome:** `scripts/devcontainer-permissions.sh` is the supported interface
  for review, authorize, list, revoke, and revoke-project. No wrapper, alias,
  shadow binary, or upstream Cyclestone command is added. Immediate revocation
  means that the next matching repository-local authorize evaluation fails.
- **Rationale:** Naming the implemented interface avoids inventing an upstream
  extension point or a fake runtime consumer while retaining an independently
  testable local authorization boundary.
- **Consequences:** Dev Container configuration generation, provider access
  materialization, point-of-access revalidation, post-revocation generation,
  and replay-resistant allow-once audience, expiry, and atomic consumption are
  deferred to a future configuration-generation/provider-materialization
  milestone. The value-free authorization result applies no access. This
  supersedes only D-025's obsolete command-spelling expectation and any D-025 or
  D-027 implication that runtime integration is acceptance work for this
  milestone; their exact-plan, identity, storage, revocation, race,
  secret-exclusion, and invocation-local allow-once controls remain unchanged.
- **Supersession:** A reviewed configuration-generation/provider-materialization
  design with a real consumer and equivalent or stronger authorization controls.

## 2026-08-01 — D-030 Provider credential adapters and isolated synchronization

- **Context:** Plan-version-1 authorization described broad provider directories
  but did not apply credentials. The secure-credential milestone needs a real
  consumer without permitting projects to choose values, paths, destinations,
  names, endpoints, mount options, or provider definitions.
- **Outcome:** Plan version 2 makes the complete reviewed adapter part of the
  authorization fingerprint. Claude and generic proxy access use exact name-only
  runtime environment inheritance; Ollama uses its exact name and reviewed
  unauthenticated HTTP metadata; Codex read-only mounts only `auth.json`; and
  Codex read-write plus OpenCode use project/provider isolated stores containing
  only `auth.json`. Persistent authorization is re-evaluated at every operation.
  Imports and provider-specific synchronization require current-user 0700/0600
  state, exact contents, provider-shape validation, source identity, fsync, and
  same-filesystem atomic rename. No prior broad-directory grant is reusable.
- **Rationale:** Exact files and names minimize host exposure while isolated
  writable copies preserve provider refresh without mounting live host
  authentication directories writable. Binding untrusted metadata back to the
  fresh plan prevents local state from redirecting a mount or synchronization.
- **Consequences:** Rootless Podman with `keep-id`, private SELinux relabeling,
  and no-new-privileges is the supported Linux runtime path. Tracked active
  sessions make revocation fail with `E_ACTIVE_SESSION`; after stop, isolated
  state is deleted before the grant and later access is denied. Revocation
  cannot retract bytes already read, stop untracked processes, or delete
  external backups; suspected disclosure or restoration requires provider-side
  rotation. Provider formats are narrow reviewed shapes, not semantic token
  validation. Canonicalization-to-use, inode-reuse, process-retention, and
  filesystem durability races remain residual.
- **Supersession:** A reviewed credential/runtime design with an explicit schema
  migration, equal or narrower exposure, equivalent authorization and atomicity,
  provider-format evidence, active-session semantics, and native qualification.

## 2026-08-01 — D-031 Deterministic split runtime configuration

- **Context:** Provider plans now have a Dev Container consumer, but local
  credential paths and grant-bound access cannot enter reproducible committed
  configuration.
- **Outcome:** Repository-local `devcontainer-generate.sh` and
  `devcontainer-validate.sh` reuse plan-version-2 authorization and credential
  preparation. Generation owns one portable structural file and one ignored
  local runtime file. Closed additive merging rejects conflicts; canonical JSON
  uses content-derived provenance and same-directory atomic replacement.
- **Rationale:** Splitting portable structure from machine-local access preserves
  reproducibility and review without extending or shadowing upstream
  Cyclestone v0.0.2.
- **Consequences:** Every enabled request needs fresh persistent authorization
  and valid prerequisites. CLI 0.86.0 validates the explicit local config.
  Source identity is rechecked at write time, but races at later container use
  and a crash between two output renames remain residual and diagnosable.
- **Supersession:** A reviewed runtime-config format or genuine upstream command
  integration with equivalent closed inputs, provenance, atomicity, access
  intersection, source revalidation, migration, and native evidence.

## 2026-08-02 — D-032 End-to-end security boundary hardening and safe mode

- **Context:** Untrusted repository analysis requires guaranteed suppression of
  lifecycle commands, host socket mounts, and host provider credential grants,
  as well as strict environment variable allowlisting, path traversal rejection,
  and grant scoping enforcement.
- **Outcome:** `devcontainer-generate.sh` and `devcontainer-validate.sh` support
  a `--safe-mode` flag that strips all lifecycle hooks (`postCreateCommand`, etc.),
  rejects host provider credential grants (`E_SAFE_MODE_DENIED`), prohibits socket
  mounts (`E_PROHIBITED_MOUNT`), and records `safeMode: true` in metadata. Generated
  environment variables are validated against a strict allowlist
  (`ANTHROPIC_API_KEY`, `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`, `OLLAMA_HOST`).
  Mount validation rejects path traversal (`..`), symlinks outside workspace bounds,
  socket mounts, and non-fixed container destinations. Writable provider paths emit
  explicit security warnings during review.
- **Rationale:** Establishing non-bypassable technical controls for untrusted
  code isolation and credential protection prevents malicious repositories from
  executing host code or capturing host provider credentials.
- **Consequences:** All generated configurations and validation routines enforce
  safe mode flags, strict env var allowlisting, non-root user execution (`developer`),
  prohibition of passwordless root escalation, and isolated credential storage.
- **Supersession:** A reviewed security policy decision with equal or stronger
  isolation and credential protection evidence.

## 2026-08-03 — D-033 Automated release publication workflow

- **Context:** Pushing built images, SBOMs, and SLSA provenance to GHCR must be secure, automated, and prevent unauthorized forks or pull requests from triggering publication or leaking secrets.
- **Outcome:** Implement `.github/workflows/release-image.yml` triggered on release publication, running under a protected environment `release`, with restricted permissions (`packages: write`, `contents: read`, `id-token: write`). Pin all workflow actions to 40-character commit SHAs. Build the base image for both `linux/amd64` and `linux/arm64` using QEMU. Run automated vulnerability scanning prior to pushing using Trivy. Generate and attach SBOM and cryptographically signed build provenance using Sigstore and `actions/attest-build-provenance`.
- **Rationale:** Pinned commit SHAs mitigate tag-spoofing and compromise risks. Pre-scanning guarantees that vulnerable images are never published to GHCR. SLSA build provenance and SBOMs allow consumers to verify image integrity and package details transparently.
- **Consequences:** Release workflow runs sequentially and halts on any high or critical vulnerability violation. Tag mapping correctly distinguishes stable version aliases (`0.1`, `0`, `latest`) from prerelease tags which only map to their exact version.
- **Supersession:** A reviewed release-publication or signing decision with equivalent or stronger integrity and automation.



## 2026-08-03 — D-034 Example SDK checksum formats

- **Context:** The templates-and-examples milestone adds Node.js and .NET SDK
  child-image examples alongside the existing Go example. Go and Node.js
  publishers provide SHA-256 checksums, while the .NET publisher provides
  SHA-512 checksums.
- **Outcome:** Each example uses its publisher's native checksum format: Go and
  Node.js verify with `sha256sum --check --strict`, and .NET verifies with
  `sha512sum --check --strict`. All three follow the same fail-closed
  acquisition pattern (download, verify before extraction, fail on mismatch).
- **Rationale:** Using the publisher's native checksum format preserves the
  fail-closed acquisition principle without inventing a locally computed
  substitute hash. SHA-512 is strictly stronger than SHA-256 for integrity
  verification.
- **Consequences:** The contract checks distinguish `sha256sum` (Go, Node.js)
  from `sha512sum` (.NET). Example version updates must refresh the
  publisher-format checksum for both architectures.
- **Supersession:** A reviewed acquisition policy may standardize on one format
  if a publisher changes its checksum distribution.

## 2026-08-03 — D-035 .NET invariant globalization on ICU-free base

- **Context:** The .NET SDK runtime requires libicu for full globalization, but
  the base image allow-list (D-008, D-011) deliberately excludes ICU to keep the
  minimal non-runtime package closure. The first .NET example build failed with
  a missing-libicu abort during `dotnet --version`.
- **Outcome:** The .NET child-image example sets
  `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` in both the build-time verification
  step and the final image `ENV`.  This enables .NET invariant globalization
  mode, which runs without libicu.
- **Rationale:** Adding ICU to the base image would violate the minimal package
  closure and introduce a transitive runtime dependency for a single SDK
  example.  Invariant mode is the Microsoft-recommended approach for minimal
  containers without ICU, and the base image intentionally excludes language
  runtimes.
- **Consequences:** .NET consumers on this base run in invariant globalization
  mode and cannot use culture-sensitive formatting, sorting, or casing unless
  they add ICU in their own child image.  The static contract check enforces the
  presence of `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` in the .NET Containerfile.
  Consumers needing full globalization must install `libicu-dev` (or equivalent)
  and remove the invariant flag in their own image.
- **Supersession:** A reviewed base-package decision that adds ICU or a reviewed
  .NET runtime decision that changes the globalization strategy.

## 2026-08-03 — D-036 Node.js archive directory naming

- **Context:** The Node.js Containerfile used `dir=node-$NODE_VERSION-linux-x64`
  to rename the extracted archive directory, but Node.js archives extract to
  `node-v$VERSION-linux-x64` (with a `v` prefix on the version).  The build failed
  with `mv: cannot stat '/usr/local/node-22.11.0-linux-x64'`.
- **Outcome:** The Node.js Containerfile uses `dir=node-v$NODE_VERSION-linux-x64`
  (and `-linux-arm64`) to match the publisher's actual archive directory naming.
- **Rationale:** Node.js archive directory names include the `v` version prefix
  that matches the archive filename; the Containerfile must match this exactly.
- **Consequences:** Example version updates must preserve the `v` prefix in the
  directory naming.
- **Supersession:** None expected unless the Node.js publisher changes its
  archive directory naming convention.

## 2026-08-03 — D-037 MVP security default confirmation

- **Context:** The MVP qualification milestone requires confirming that no
  deferred security decision has leaked into a default behavior.
- **Outcome:** On 2026-08-03, the following confirmation is recorded for image
  line `1.x` at commit `ce2bfdfc6d124af8c210ccedcb1cfd730b6e0ce9`:
  - The base image embeds no credentials (environment table in `image-contract.md`
    defines no credential variable; `cyclestone-acquisition.md` uses public
    downloads with fail-closed checksum verification).
  - Authorization is value-free and default-deny (`scripts/devcontainer-permissions.sh`
    rejects noninteractive authorization; `tests/provider-authorization.sh`
    passes; provider example requests contain no credential values per
    `tests/contracts.sh`).
  - Credential injection is runtime-only and provider-documented
    (`scripts/provider-credentials.sh` materializes exact reviewed files at
    runtime; `tests/provider-credentials.sh` passes; no credential is a build
    argument, layer, default, or label).
  - No unspecified host path is required (`image-contract.md` filesystem table
    enumerates every path; `threat-model.md` boundary 1 confirms only
    `/workspace` and optional contract-directory mounts cross inward).
  - Privileged mode and engine sockets are not required (`image-contract.md`
    forbids privileged mode and broad sockets; `threat-model.md` confirms
    non-root, minimal capabilities; `tests/contracts.sh` rejects socket and
    provider-mount patterns in templates).
  - Every optional mount is enumerated in the image contract (`image-contract.md`
    public filesystem interface table lists all optional volume targets).
- **Rationale:** The end-to-end qualification run exercises contracts,
  provider denial, credential access, generation, validation, and child-image
  inheritance on the same commit; no gap was found between the security posture
  decisions (D-007, D-024, D-025, D-030, D-032) and the implementation defaults.
- **Consequences:** Any future change that introduces a credential default,
  broad mount, privileged requirement, or implicit trust assumption must be a
  reviewed decision with a security assessment. This confirmation is point-in-time;
  future commits require re-confirmation if defaults change.
- **Supersession:** A later security audit or formal verification may strengthen
  this confirmation with automated runtime probing.

## 2026-08-04 — D-038 Native tool installation framework

- **Context:** The base image previously installed only Cyclestone from a
  checksum-pinned release archive and was provider-free by hard contract.
  The maintainer requested a uniform native installation framework for
  Cyclestone, Codex, Agy, Ollama, and OpenCode, with build-arg selection and
  a runtime update script.
- **Outcome:**
  - `scripts/install-tools.sh` is the uniform native installer for all five
    tools. It replaces `images/base/install-cyclestone.sh`.
  - `INSTALL_TOOLS` build arg (comma-separated list) selects tools at build.
    Empty selection produces a valid empty-toolset base image. No tool is
    mandatory, including Cyclestone.
  - Cyclestone is treated uniformly with the other tools and is NOT added to
    `providers/registry-v1.json` (it is the orchestrator, not an LLM backend).
  - Cyclestone resolves to the latest v-tag at build via the GitHub releases
    API; publisher `checksums.txt` is fetched and trusted at build (not
    pre-pinned in `versions.env`); archive digest verified against it.
  - Codex: publisher-trusted over HTTPS; no client-side checksum.
  - Agy: publisher installer with internal SHA-512 manifest verification;
    `--dir` override used at build.
  - Ollama: publisher installer, root-aware, writes `/usr/local/bin/ollama`.
  - OpenCode: publisher installer with `--no-modify-path`; installs to
    `$HOME/.opencode/bin`.
  - `cyclestone-tools` shipped at `/usr/local/bin/cyclestone-tools` for
    runtime updates of user-installable tools.
  - `io.cyclestone.version` label replaced by `io.cyclestone.tools`.
  - `CYCLESTONE_VERSION` env var removed; `INSTALL_TOOLS` env var added.
- **Rationale:** Uniform native installation removes the npm/SDK dependency
  for AI tools, enables opt-in toolset selection, and supports runtime updates
  without image rebuilds (except ollama). Latest v-tag resolution keeps tools
  current at the cost of build non-reproducibility, which is accepted and
  documented.
- **Consequences:** Builds are non-reproducible for tool installs; resolved
  versions must be recorded in release evidence per build. The provider-free
  contract is retired; the base is now a toolset image with empty default.
  `docs/architecture/cyclestone-acquisition.md`, `image-contract.md`,
  `base-image.md`, `threat-model.md`, `versioning.md`, `compatibility.md`,
  `validation-checklist.md`, and `release-reproduction.md` are updated.
- **Supersession:** D-005's pinned-archive acquisition model is superseded for
  Cyclestone. D-037's MVP security default confirmation is re-confirmed for
  the new defaults (empty toolset, no credentials).

## 2026-08-04 — D-039 PATH order: user prefix before system prefix

- **Context:** The base image ENV PATH listed `/usr/local/bin` (system prefix,
  S) before `/home/developer/.local/bin` (user prefix, U). Runtime
  `cyclestone-tools update` installs cyclestone, codex, and agy to U, but S
  copies shadowed them, making runtime updates a no-op in practice. Only
  opencode (at `$HOME/.opencode/bin`, no S copy) was unaffected.
- **Outcome:** PATH order in `images/base/Containerfile` ENV changed to
  `/home/developer/.local/bin:/home/developer/.opencode/bin:/usr/local/bin:...`.
  U now shadows S, so `cyclestone-tools update` for system tools (cyclestone,
  codex, agy) takes effect at runtime. `cyclestone-tools status` already
  scanned both prefixes and continues to report the active (U-first) version.
- **Rationale:** D-038 documented runtime updates as a supported capability,
  but the PATH order made them ineffective for three of the four updatable
  tools. Aligning PATH with the update mechanism fulfills the documented
  contract instead of weakening it.
- **Consequences:** This is a contract change to default PATH behavior,
  classified as a major change per `docs/architecture/versioning.md` (default
  behavior break). Child images inheriting the base ENV are affected. System
  tools remain at S for build-time installation; runtime updates overlay them
  at U. `cyclestone-tools install --tool <name>` at runtime still targets S
  for system tools and requires root (unchanged); only `update` installs to U.
  No contract test or doc hard-coded the old PATH order string, so no test or
  doc text needs updating for the swap itself.
- **Supersession:** D-004's filesystem and process interface decision is
  amended for the PATH ordering detail only; all other D-004 interface
  elements remain in force.

## 2026-08-05 — D-040 agy install context: user, not system

- **Context:** `cyclestone-tools update` for agy failed at runtime with
  `curl: (23) Failure writing output to destination`. The official agy
  installer (antigravity.google/cli/install.sh) hardcodes its download
  staging tree at `$HOME/.cache/antigravity/staging` and its EXIT trap only
  reaps files inside staging, not the staging directories themselves. At
  build time the child `.devcontainer/Containerfile` ran `cyclestone-tools
  install --tool agy` under `USER root` while `HOME=/home/developer`
  (inherited from the base image ENV), so root-owned
  `~/.cache/antigravity/` and `.../staging/` persisted into the image. At
  runtime the non-root developer cannot write into that root-owned staging
  tree, so every update/self-update fails. The misleading "check your
  internet connection or firewall" message was unrelated to the cause.
- **Outcome:** agy is now a *user* tool, not a system tool:
  - `scripts/install-tools.sh` `run_install_tool` dispatch routes agy to
    `prefix_for_user` (`$HOME/.local/bin/agy`) alongside opencode, instead
    of `prefix_for_system` (`/usr/local/bin/agy`). The install must run as
    the developer user so the staging tree is developer-owned.
  - `images/base/Containerfile` final stage installs agy as developer
    (via `su -s /bin/sh developer -c '... install --tool agy'`), matching
    the existing opencode handling; the acquisition stage's root-context
    agy install is discarded with that stage as before.
  - `.devcontainer/Containerfile` moves agy from `INSTALL_TOOLS_SYSTEM`
    to `INSTALL_TOOLS_USER`; `.devcontainer/devcontainer.json` build args
    updated accordingly.
  - `docs/architecture/cyclestone-acquisition.md` agy row and acquisition
    sequence updated to the user install location and rationale.
- **Rationale:** D-039 established that runtime `cyclestone-tools update`
  installs to the user prefix and PATH shadows the system copy, so a
  system-copy of agy is no longer needed. Installing agy as root was the
  sole cause of the root-owned staging tree; installing as developer
  removes the failure mode entirely without any post-install cleanup hack.
  This is the minimal change that aligns the install context with the
  runtime update contract.
- **Consequences:** agy's build install location changes from
  `/usr/local/bin/agy` to `/home/developer/.local/bin/agy` (already first
  on PATH per D-039, so resolution is unchanged). `status_agy` already
  scanned both prefixes and continues to work. No contract test or image
  inspection asserted agy at `/usr/local/bin/agy`. The base image
  acquisition stage still downloads agy into `/root/.local/bin` (discarded)
  before the final-stage developer install — a minor waste, consistent
  with the existing opencode pattern, kept to avoid splitting the
  `INSTALL_TOOLS` build arg into system/user halves. A regression test in
  `tests/install-tools.sh` asserts agy installs to the user prefix and
  not the system prefix.
- **Supersession:** D-039's "system tools remain at S for build-time
  installation" is amended for agy only; cyclestone and codex remain system
  tools. D-004's filesystem interface is amended for agy's install
  location only.

## 2026-08-05 — D-041 All AI tools install under the developer user

- **Context:** D-040 moved agy from a system tool (root, `/usr/local/bin`)
  to a user tool (developer, `~/.local/bin`) to fix the root-owned staging
  tree that broke `cyclestone-tools update` with curl exit 23. cyclestone
  and codex remained system tools installed as root at `/usr/local/bin`,
  with runtime `update` overlaying them at `~/.local/bin` per D-039. The
  split between "system tools installed as root" and "user tools installed
  as developer" added conceptual and mechanical complexity for no benefit:
  the system copies of cyclestone and codex were never needed at runtime
  (the user copy shadows them on PATH) and a root install context cannot
  be exercised at runtime as the non-root developer.
- **Outcome:** All four AI tools — cyclestone, codex, agy, opencode — are
  now user tools installed as the `developer` user under `$HOME`:
  - `scripts/install-tools.sh` `run_install_tool` dispatch routes
    cyclestone and codex to `prefix_for_user` (`~/.local/bin`) alongside
    agy and opencode. Ollama is the only remaining system tool
    (`prefix_for_system` → `/usr/local/bin`, root, no runtime update).
  - `images/base/Containerfile` final stage installs cyclestone, codex,
    agy, and opencode as developer via `su -s /bin/sh developer -c '...'`;
    the acquisition stage now only stages ollama (if selected) into `/out`.
    The verification RUN checks cyclestone/codex/agy at
    `/home/developer/.local/bin/<tool>` and opencode at
    `/home/developer/.opencode/bin/opencode`.
  - `.devcontainer/Containerfile` collapses to a single
    `INSTALL_TOOLS_USER` build arg containing all four tools, run as
    `USER developer` (no `USER root` install step remains).
  - `cyclestone-tools update` behavior is unchanged (it already installed
    to the user prefix); the system copies at `/usr/local/bin` simply no
    longer exist for cyclestone/codex/agy.
- **Rationale:** Unifying all AI tools under one install context (developer,
  user prefix) is simpler, removes the root-owned-staging failure mode for
  any future tool whose installer writes under `$HOME`, and matches the
  runtime reality that `update` already installs to the user prefix. There
  is no functional loss: PATH (per D-039) puts `~/.local/bin` and
  `~/.opencode/bin` ahead of `/usr/local/bin`, so the tools resolve
  identically. Ollama remains a system tool because it is a system service
  binary requiring root and is excluded from runtime updates by design.
- **Consequences:** Build install locations change for cyclestone
  (`/usr/local/bin/cyclestone` → `/home/developer/.local/bin/cyclestone`)
  and codex (`/usr/local/bin/codex` → `/home/developer/.local/bin/codex`);
  the cyclestone license moves to
  `/home/developer/.local/share/licenses/cyclestone/`. `status_*` functions
  still scan `/usr/local/bin/<tool>` first for backward compatibility with
  images built before this change, then fall through to the user prefix.
  Tests (`tests/install-tools.sh`, `tests/image-inspect.sh`,
  `scripts/validate-base-native.sh`, the `child-image-invalid/cyclestone`
  fixture) were updated to the new paths. This is a major change per
  `docs/architecture/versioning.md` (default behavior break: build install
  location and ownership). The acquisition stage still downloads user
  tools into `/root` (discarded with the stage) before the final-stage
  developer install — a minor waste kept to avoid splitting the
  `INSTALL_TOOLS` build arg into system/user halves; future work could
  skip user tools in the acquisition stage.
- **Supersession:** D-040's "cyclestone and codex remain system tools" is
  superseded — they are now user tools. D-039's PATH ordering remains
  correct and is now the *only* resolution path for these tools (no system
  copy to shadow). D-004's filesystem interface is amended for cyclestone
  and codex install locations.

## 2026-08-04 — D-042 `cyclestone-tools update` removes the agy binary before fresh install

- **Context:** The upstream agy installer (`https://antigravity.google/cli/install.sh`)
  refuses to overwrite an existing binary at the target prefix
  (`$prefix/agy`). At runtime, `cyclestone-tools update` invokes the
  installer against the user prefix (`~/.local/bin`), where an older agy
  already lives from the build-time install or a prior update. The
  installer's refusal surfaced as a runtime update failure with an error
  pointing at the existing binary, and the official guidance was to delete
  the binary first (`rm "$HOME/.local/bin/agy"`).
- **Outcome:** `scripts/install-tools.sh` `update_agy` now removes
  `$prefix/agy` (`rm -f`) before invoking `install_agy` against the user
  prefix, so the installer always sees a clean target. `install_agy` is
  unchanged. A regression test in `tests/install-tools.sh` (Test 4c)
  plants a stale sentinel binary, runs `update --tool agy` against a
  fixture installer that mirrors the upstream refusal behavior, and
  asserts the binary is replaced with the fresh build.
- **Rationale:** The installer's no-overwrite contract is a publisher-side
  invariant; the update flow is the right place to satisfy it. Removing
  the binary before install is the documented upstream remediation, makes
  the update idempotent across runs, and avoids any post-install
  inconsistency. `rm -f` is safe: the path is under the developer's user
  prefix, the install that follows recreates the binary, and a missing
  binary (first update on a fresh image) is handled by `-f`.
- **Consequences:** `cyclestone-tools update` now reliably refreshes agy
  at runtime as the non-root developer. The fixture installer in
  `tests/install-tools.sh` was hardened to mirror the upstream refusal
  (exit 1 on an existing target) so the regression stays under test.
  No contract or image inspection assertion is affected; install location
  (`~/.local/bin/agy`) is unchanged from D-040/D-041.
- **Supersession:** None.

## 2026-08-05 — D-042 Data-driven provider registry (v2 cutover)

- **Context:** The v1 registry required per-provider ID `if/elif` code branches in
  four core scripts (`resolve-providers.sh`, `devcontainer-permissions.sh`,
  `provider-credentials.sh`, `runtime-config-lib.sh`). Adding a 7th provider
  required editing all four scripts with hardcoded source paths, env names,
  destinations, and adapter metadata — a multi-file code change with security
  review, not a JSON drop-in. This blocked general-use extensibility by design.
- **Outcome:** Registry version 2 is a breaking cutover. The registry file is
  `providers/registry.json` (version in the `registry_version` field, not the
  filename). The v2 schema (`trusted-provider-registry-v2.schema.json`) uses
  generic strategy-family `oneOf` branches (runtime-environment, host-service,
  direct-file-mount, isolated-store) with closed enums on `source_files`,
  `environment_names`, and `container_destination`. The four core scripts no
  longer contain per-provider ID branches or hardcoded allowlists; adapter
  validation is data-driven via registry lookup and generic coherence rules.
  Adding a provider that reuses existing enum values requires only a
  `registry.json` edit, schema validation, snapshot update, and CHANGELOG —
  zero shell edits. Adding a provider with a new source path, env name, or
  destination requires a schema enum expansion and security review.
- **Rationale:** The closed-enum approach preserves the v1 fail-closed access
  boundary (a registry compromise cannot introduce unreviewed paths/names) while
  removing the per-ID code coupling. The registry remains reviewed code with a
  maintainer approval gate; the win is "data-driven registration without shell
  code edits," not "no review." The access-boundary snapshot remains the
  human-reviewable manifest for semantic changes; the fingerprint remains the
  security gate for plan integrity.
- **Consequences:** Existing grants referencing `registry_version: 1` fail with
  `E_STORE_SCHEMA` and require re-approval. Plans for the 6 unchanged providers
  (excluding `registry_version`) are byte-identical — verified by golden test.
  The `local-provider-grants-v1.schema.json` is updated to accept
  `registry_version: 2` with generic mode-driven `if/then` branches. The
  `provider-credential-state-v1.schema.json` `provider_id` enum is replaced with
  a pattern. Descriptive metadata fields (`import_behavior` text,
  `failure_codes` list contents) are no longer pinned to exact values in the
  shell validator — the fingerprint and snapshot remain the gates. The v1
  registry file and v1 schema are retired. Source↔destination pairing is
  enforced both in the schema (`if/then` on `source_files` ↔
  `container_destination`) and in the shell validator (generic coherence check).
  This is classified as a major change per the versioning policy.
- **Supersession:** D-024's statement that registry v1 contains exactly five
  (later six) providers with per-ID code enforcement is superseded by the
  data-driven v2 approach. D-030's per-ID `adapter_is` branches in
  `devcontainer-permissions.sh` are superseded by the registry-lookup validator.
  The security invariants (D-007, D-032) are preserved: fail-closed posture,
  closed-enum access boundary, snapshot review, and maintainer approval gate.

## 2026-08-06 — D-043 Image renaming to cyclestone-dev-container-base

- **Context:** The image name `cyclestone-dev` can be confused with developer builds of the Cyclestone application. An upcoming release requires a clearer name that indicates its status as a base image for development containers.
- **Outcome:** The OCI image family name is renamed from `ghcr.io/patrick-folster/cyclestone-dev` to `ghcr.io/patrick-folster/cyclestone-dev-container-base`.
- **Rationale:** The new name `cyclestone-dev-container-base` accurately states the image's purpose and role as a base development container image.
- **Consequences:** All references across GitHub Actions workflows, tests, builder scripts, and documentation files are updated.
- **Supersession:** D-001's canonical image family outcome of `ghcr.io/patrick-folster/cyclestone-dev` is superseded by this decision.

## 2026-08-06 — D-044 Shellcheck source directive for optional local init file

- **Context:** The `initialize.sh` script sources `.devcontainer/.init.local` if it exists. However, because `.init.local` is gitignored, it is not present in the repository on CI/CD (GitHub Actions), which causes ShellCheck to fail with a warning/error when analyzing `initialize.sh` (as it tries to follow the specified source path directive `# shellcheck source=.devcontainer/.init.local`).
- **Outcome:** The ShellCheck directive in `.devcontainer/initialize.sh` for the optional local config file was changed to `# shellcheck source=/dev/null`.
- **Rationale:** Sourcing `/dev/null` tells ShellCheck to ignore the missing file without attempting to trace it. This resolves the linting failure in the GitHub Action while maintaining the optional local overrides feature.
- **Consequences:** The GitHub Action's ShellCheck step passes when `.init.local` is missing.
- **Supersession:** None.

## 2026-08-06 — D-045 DCO workflow fallback for empty commit range

- **Context:** The Developer Certificate of Origin (DCO) check fails with exit code 128 (`fatal: ambiguous argument '': unknown revision or path not in the working tree.`) during `workflow_dispatch` triggers or manual runs. This is because both `BASE_REF` and `HEAD_REF` are empty, resulting in `range` being set to an empty string when passed to `git rev-list`.
- **Outcome:** Added a check in `.github/workflows/dco.yml` that falls back to `HEAD^!` (only the latest commit) if `range` resolves to an empty string.
- **Rationale:** Defaulting to `HEAD^!` ensures that `git rev-list` receives a valid target, avoiding the exit 128 error while checking only the latest commit to prevent scanning the entire repository history.
- **Consequences:** The DCO check workflow runs successfully on `workflow_dispatch` events without throwing git range errors.
- **Supersession:** None.

## 2026-08-06 — D-046 Correct docker/login-action commit hash in release workflow

- **Context:** The `Publish Release Image` workflow fails during execution with a GitHub Actions runner error: `Error: Unable to resolve action docker/login-action@49ed152c8eca002446f25032049e7514a60155b4, unable to find version 49ed152c8eca002446f25032049e7514a60155b4`. The hash `49ed152c8eca002446f25032049e7514a60155b4` is invalid for `docker/login-action`.
- **Outcome:** Replaced the invalid commit hash with the correct commit SHA `9780b0c442fbb1117ed29e0efdff1e18412f7567` for `docker/login-action@v3.3.0`.
- **Rationale:** Using the verified, immutable commit hash for `v3.3.0` ensures the action resolves correctly while maintaining the repository's security posture of pinning GitHub Actions to exact commit SHAs.
- **Consequences:** The `Publish Release Image` workflow can successfully download and run the log in action.
- **Supersession:** None.

## 2026-08-07 — D-047 Add attestations: write permission to release workflow

- **Context:** The `Publish Release Image` workflow fails during the build attestation steps with: `Error: Error: Failed to persist attestation: Resource not accessible by integration - https://docs.github.com/rest/repos/attestations#create-an-attestation`. This is because the workflow's `GITHUB_TOKEN` does not have the permissions required to write/persist build attestations.
- **Outcome:** Added the `attestations: write` permission to the top-level permissions block in `.github/workflows/release-image.yml`.
- **Rationale:** The `actions/attest-build-provenance` action requires explicit `attestations: write` privileges (along with `id-token: write`) to securely publish and link attestation metadata back to the repository.
- **Consequences:** Build attestations can be successfully created and persisted when running the release workflow.
- **Supersession:** None.
