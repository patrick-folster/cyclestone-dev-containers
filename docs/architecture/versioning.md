# Image Version Policy

The image family uses Semantic Versioning independently of Cyclestone. An image
tag such as `1.2.3` does not mean Cyclestone `1.2.3`; the included Cyclestone
version is exposed by `io.cyclestone.version` and `CYCLESTONE_VERSION`.

Consumers should pin an immutable manifest digest, optionally alongside a full
`MAJOR.MINOR.PATCH` tag. Mutable convenience tags such as `1`, `1.2`, or `latest`
may be published for discovery but never replace immutable release references.
Pre-1.0 development tags are not part of the supported image line.

## Change classification

The highest applicable classification wins.

| Category | Patch | Minor | Major |
| --- | --- | --- | --- |
| Operating system | Rebuild/security package updates within Ubuntu 24.04 that preserve behavior | Compatible package additions or opt-in capabilities on the same LTS | Distribution/LTS change, removed OS facility, or changed observable behavior |
| Tool updates | Compatible bug/security update with unchanged interface | Compatible feature/tool addition or opt-in update via `INSTALL_TOOLS` | Removed tool or incompatible defaults/interface |
| Cyclestone updates | Latest v-tag resolved at build; compatible patch update validated against all supported rows | Compatible feature release or additional supported Cyclestone selection | Incompatible Cyclestone behavior, removed accepted workflow, or contract break |
| Provider definitions | Correct metadata without behavior/trust change | New opt-in provider or compatible fields with declared validation and trust boundary | Removed provider, incompatible schema/credential/mount behavior, or implicit trust expansion |
| Dev Container behavior | Bug/security fix restoring documented behavior | Compatible opt-in feature/default that does not disrupt existing configs | Default lifecycle, user, workdir, mount, entrypoint, or command behavior break |
| Public contracts | Clarification or implementation fix with no consumer effect | Backward-compatible addition | Removal, rename, changed guarantee/default, or newly required host path/credential |
| Security fixes | Compatible remediation | Compatible new mitigation or defense in depth | Contract-breaking remediation unless emergency policy below is used |

Deprecations are announced in release notes and in the affected normative
contract or user guide. Every announcement names the deprecated element, its
replacement, affected consumers, migration and rollback steps, and the earliest
major release that may remove it. Once introduced, the deprecated element
remains available in every later minor release of that major line; removal or an
incompatible semantic change waits for the next major release.

Removing or incompatibly changing `USER`, user identity behavior, `HOME`, a
public path or environment variable, Cyclestone command availability,
`WORKDIR`/workspace semantics, `ENTRYPOINT`/`CMD` behavior, PID-1 signal
forwarding, OCI label semantics, acquisition source, or a supported matrix
guarantee requires a new major line, except through the maintainer-authorized
urgent security process below. These remain public-contract changes even when
driven by another category.

## Urgent security exception

A compatible fix ships as a patch as soon as validation permits. A breaking fix
normally starts a new major line. If delaying creates greater material harm,
`@patrick-folster` may authorize an emergency migration on the affected line only
with a dated security decision, affected tags/digests, explicit break description,
migration/rollback instructions, support window, and prominent release notice.
The exception does not relabel a breaking change as compatible and does not allow
mutable tags to obscure the replacement digest.

Every release records image version, Cyclestone version, source revision, base
digest, creation time, supported platforms, and migration notes in OCI metadata
and release notes.

Provider registry format and data carry their own integer versions independently
of the image. Adding a provider or expanding a host source, destination,
environment-name allowlist, supported/recommended mode, platform, or service
exposure requires security review, an intentional boundary-snapshot update,
provider changelog and release note, and the image SemVer classification above.
A format-breaking registry change increments the registry version and provides
migration guidance. Project configuration cannot select a registry, include a
URL, or load custom definitions.
