# Foundation MVP Boundary

## Included

This milestone delivers a reviewable repository skeleton and normative contracts
for repository ownership, canonical source/image identity, Ubuntu 24.04 base,
Linux `amd64`/`arm64` platforms, non-root filesystem/environment/entrypoint
behavior, pinned Cyclestone acquisition, downstream extensions, compatibility,
image versioning, trust boundaries, and validation evidence. It also provides
dependency-free automated checks for internal consistency.

The foundation is implementation-ready documentation. It intentionally does not
claim that an image has been built or published.

## Deferred from the MVP

The following remain unsupported until a later reviewed milestone adds an
implementation, compatibility row, validation, version classification, and any
new trust-boundary analysis:

- concrete provider definitions, provider CLIs, credentials, and remote APIs;
- additional language runtimes, SDKs, databases, and project toolchains;
- local services, multi-container orchestration, daemon sockets, and privileged
  host integrations;
- team/multi-user features, shared state, authentication, authorization, identity,
  tenancy, audit, and remote control planes;
- non-Ubuntu bases, additional CPU architectures, non-Linux containers, WSL2,
  macOS, and Windows host support;
- image build, signing/attestation, publication, Dev Container template release,
  and registry lifecycle automation.

These deferrals do not reserve implicit support or trust. Compatible additions
use the documented child-image and provider/template areas; incompatible changes
start a new major image line. No current extension point requires a host path,
credential, service, or socket.
