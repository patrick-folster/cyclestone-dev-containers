# Delivery Roadmap

Date: 2026-08-03. Owner: `@patrick-folster`.

This document records the final dependency graph across milestones
ms-pf-0001 through ms-pf-0015, measured compatibility results from the
allow-listed matrix, deferred decisions, prioritized follow-up release
candidates, and explicit out-of-scope items.

## MVP release scope

The smallest viable first release consists of:

- One independently versioned base image (`ghcr.io/patrick-folster/cyclestone-dev-container-base`,
  image line `1.x`) built from pinned Ubuntu 24.04 LTS.
- The `developer` (`1000:1000`) non-root user and `/workspace` contract.
- Direct rootless Podman `keep-id` support (C5).
- One validated Dev Container path via Dev Container CLI `0.86.0` with
  rootless Podman (C6/V8) for both matching `1000:1000` and differing
  `1001:1001` host identities.
- Deterministic provider configuration generation and validation.
- Local per-project provider authorization (default-deny, value-free).
- Codex and Ollama reference providers with secure credential handling.
- Fedora SELinux guidance for enforcing-SELinux hosts.
- Automated CI tests and GHCR publication workflow with SBOM and SLSA
  provenance.
- At least one fully exercised child-image example (Go 1.26.5).

## Dependency graph

The graph is linear along the recommended order except that provider schema
work (ms-pf-0006) may proceed after repository contracts (ms-pf-0001) and
converges with Dev Container integration at runtime generation (ms-pf-0009).

```
ms-pf-0001 ──▶ ms-pf-0002 ──▶ ms-pf-0003 ──▶ ms-pf-0004 ──▶ ms-pf-0005 ──┐
    │                                                                     │
    └──▶ ms-pf-0006 ──▶ ms-pf-0007 ──▶ ms-pf-0008 ──▶ ms-pf-0009 ◀────────┘
                                                          │
                                                          ▼
ms-pf-0010 ──▶ ms-pf-0011 ──▶ ms-pf-0012 ──▶ ms-pf-0013 ──▶ ms-pf-0014 ──▶ ms-pf-0015
```

| Milestone | Title | Status |
| --- | --- | --- |
| ms-pf-0001 | Repository and image contracts | Approved |
| ms-pf-0002 | Minimal Cyclestone base image | Approved |
| ms-pf-0003 | Rootless workspace identity | Approved |
| ms-pf-0004 | Validate child-image inheritance | Approved |
| ms-pf-0005 | Integrate Dev Container workflows | Approved |
| ms-pf-0006 | Trusted provider registry | Approved |
| ms-pf-0007 | Local provider authorization | Approved |
| ms-pf-0008 | Secure provider credentials | Approved |
| ms-pf-0009 | Generate and validate runtime config | Approved |
| ms-pf-0010 | Support host services and SELinux | Approved |
| ms-pf-0011 | Harden end-to-end security boundary | Approved |
| ms-pf-0012 | Automate testing | Approved |
| ms-pf-0013 | Automate versioned image releases | Approved |
| ms-pf-0014 | Templates, examples, and documentation | Approved |
| ms-pf-0015 | Qualify MVP and publish delivery roadmap | This milestone |

## Compatibility matrix results

The matrix below records compatibility rows C1 through C10 with their validation status, deferred decisions, and unsupported combinations.

| ID | Host | CPU | Runtime | Status | Validation | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | Native Ubuntu 22.04 LTS | `amd64` | Rootful Docker | Supported | V1, V4 | Pending native evidence — see limitations |
| C2 | Native Ubuntu 24.04 LTS | `amd64` | Rootless Docker | Supported | V2, V4 | Pending native evidence — see limitations |
| C3 | Native Ubuntu 24.04 LTS | `arm64` | Rootful Docker | Supported | V3, V4 | Pending native evidence — see limitations |
| C4 | Native Ubuntu 24.04 LTS | `amd64` | Rootful Docker + Dev Container CLI | Supported | V5, V7 | Pending native evidence — see limitations |
| C5 | Native Ubuntu 24.04 LTS | `amd64` | Rootless Podman 4.9 + crun | Supported | V6, V7 | Pending native evidence — see limitations |
| C6 | Native Linux | `amd64` | Rootless Podman + Dev Container CLI | Supported | V8 | PASS (2026-08-01, commit `c65f1f9`) |
| C7 | WSL2, macOS, Windows | Any | Any | Unsupported | — | — |
| C8 | Any Linux | `arm/v7`+ | Any | Unsupported | — | Cyclestone artifact absent |
| C9 | Any | Any | Other distribution | Unsupported | — | — |
| C10 | Any | Any | Other Cyclestone version | Unsupported | — | — |

### Native evidence limitations

V1–V7 require native Ubuntu hosts (22.04 amd64, 24.04 amd64, 24.04 arm64) with
the specified Docker and Podman versions. V8 was qualified locally on
2026-08-01 under matching `1000:1000` and differing `1001:1001` identities on
native Linux amd64 with Podman `5.8.4`, crun, and Dev Container CLI `0.86.0`
(commit `c65f1f91eb356c1dc9ef0377db50cc6080be7567`, source digest
`1e51c7210f07ec42ffe338b364fe35301ebef42473d9ce3cb9838353c0b87e8a`).

Each unresolved V1–V7 item is converted to an explicit support limitation
with an accountable owner and ISO-8601 deadline (see
[compatibility.md](compatibility.md) "Deferred native evidence" section):

| Item | Methods | Owner | Deadline |
| --- | --- | --- | --- |
| Native runtime, filesystem, metadata, linkage, and layer inspection | V1–V4 | `@patrick-folster` | 2026-09-30 |
| Dev Container behavior (rootful Docker UID mutation) | V5 | `@patrick-folster` | 2026-09-30 |
| Rootless Podman keep-id and supplementary groups | V6 | `@patrick-folster` | 2026-09-30 |
| Shared workspace, Git, HOME restart, and mutation regression | V7 | `@patrick-folster` | 2026-09-30 |
| Child Go SDK inheritance and hostile child rejection on amd64/arm64 | C1–C3 | `@patrick-folster` | 2026-09-30 |

Static contract checks, provider registry/authorization/credential tests,
runtime configuration tests, child-image static checks, and local rootless
Podman + Dev Container CLI validation (C6/V8) pass on the current commit.

## Deferred decisions

The following decisions from earlier milestones are documented as deferrals
with accountable owners:

| Decision | Summary | Status |
| --- | --- | --- |
| D-008 | MVP boundary excludes image implementation, providers, extra runtimes, orchestration, and team functionality | Superseded by later milestones for implemented capabilities; remaining exclusions are out-of-scope |
| D-027 | Invocation-local allow-once has no replay-proof consumer yet | Deferred to provider-materialization/runtime milestone |
| D-029 | Script-only authorization interface; runtime config generation deferred | Partially resolved by ms-pf-0009; provider materialization remains deferred |
| D-030 | Provider credential adapters and isolated synchronization | Implemented; canonicalization-to-use and inode-reuse races remain residual |

## Follow-up release candidates

Prioritized follow-up releases beyond the MVP:

1. **Claude and OpenCode write behavior validation** — Exercise write-mode
   credential synchronization and lifecycle for Claude and OpenCode providers
   with native evidence.
2. **Additional environment providers** — Expand the registry with new
   reviewed provider definitions, boundary snapshots, and security analysis.
3. **Additional architectures** — Validate arm64-native hosts for C1–C5
   beyond QEMU emulation.
4. **Enhanced signing and reproducibility** — Signature verification of
   Cyclestone artifacts, reproducible build attestation, and cross-registry
   digest verification.
5. **Richer custom-provider tooling** — Developer tooling for creating and
   validating custom provider definitions within the reviewed boundary.
6. **More templates** — Additional Dev Container templates for common project
   workflows beyond the Go example.
7. **Remote environments** — Support for remote Dev Container hosts with
   equivalent identity, mount, and credential controls.
8. **Team policy** — Multi-user authorization, tenancy, audit, and revocation
   with authenticated identity.
9. **Centralized secret integrations** — Credential-helper and agent-socket
   support with reviewed runtime boundaries.

## Out of scope

The following are explicitly excluded from the MVP and future follow-up
releases until a reviewed milestone adds them:

- Kubernetes and container orchestration platforms
- Shared or multi-tenant hosts
- Organization-level enforcement or policy engines
- Every language runtime (only Go is exercised; Node.js and .NET are examples)
- Unrestricted custom mounts (only enumerated contract paths are supported)
- Marketplace or public template distribution
