# Lightweight Threat Model

## Assets and attacker assumptions

Assets are host and provider credentials, source code and Git history, Cyclestone
configuration/state/reports, image/build integrity, registry identity, CI tokens,
local-service data, and the host/container boundary. Checked-out repositories,
their scripts, configuration, hooks, build files, dependencies, and prompts are
untrusted even when the host user chose to clone them.

An attacker may control repository content, dependencies, network responses not
protected by authenticated integrity, a malicious image tag, or provider input;
may induce commands through project configuration; and may read anything exposed
inside the container. The attacker is not assumed to have already compromised the
host kernel, trusted maintainer account, GitHub TLS endpoint, or reviewed immutable
release digest. Those compromises are residual platform risks.

## Actors and trust decisions

| Actor | Trust and capabilities | Required controls |
| --- | --- | --- |
| Host user | Chooses image, mounts, commands, and credential injection; trusted to authorize them but may make mistakes | Pin digests, review mounts/permissions, use least-privilege runtime mechanisms |
| Untrusted repository | Can run only when explicitly invoked; never a trusted configuration source | No startup evaluation; mount only at `/workspace`; no automatic secrets/sockets |
| Cyclestone | Pinned executable trusted to orchestrate within granted container access; its project input remains untrusted | Checksum before install, non-root execution, bounded paths, version metadata |
| This repository | Reviewed contracts and build inputs are trusted at an approved revision | Protected review, contract tests, pinned inputs, least-privilege CI |
| Built image | Trusted only by verified manifest digest and provenance available at release time | OCI metadata, vulnerability review, no embedded credentials, reproducible inputs |
| Running container | Partially trusted process boundary, not a security boundary equivalent to a VM | Non-root, no privilege, minimal capabilities/mounts, runtime isolation |
| Provider CLIs | May be installed in the base via `INSTALL_TOOLS` build arg or supplied by a child image; either way they process untrusted remote/local data and exposed credentials | Reviewed exact-file/name adapter, non-root runtime, format failure without broader fallback |
| Local services | Ollama access is an explicit approved host-service mode; other services remain unsupported | Exact `OLLAMA_HOST` name and HTTP metadata, runtime-only host value, no socket/model mount |
| Registries/download sources | Serve untrusted bytes until digest/checksum validation; availability is not trusted | HTTPS, pinned image digest, publisher checksum for cyclestone (fetched at build), publisher-trusted installers for agy/ollama/opencode, HTTPS-only for codex, fail closed |
| CI | Trusted release principal with repository, token, cache, runner, and artifact access | Minimal permissions, isolated jobs, protected environments, no secrets on untrusted changes |
| Future teams/users | Have no implicit identity, role, tenant, or shared-resource trust | Feature-specific authentication, authorization, identity, audit, and tenancy design first |

## Trust boundaries and crossings

1. **Host to container:** commands, `/workspace`, optional contract-directory
   mounts, and explicit runtime secrets cross inward; project changes cross back.
   Nothing else is mounted by default. UID mapping and MAC policy remain runtime
   boundaries. Dev Container ID mutation and Podman keep-id are mutually
   exclusive translations; persistent HOME/cache volumes retain numeric
   ownership. A repository lifecycle hook executes only after explicit review
   and consent and receives all access granted to the container.
2. **Untrusted workspace to Cyclestone/tools:** filenames, Git data, configuration,
   prompts, and executed project commands cross at runtime. Entrypoint/build stages
   do not read `/workspace`; tools validate input and operate without root.
3. **Source repository/CI to built image:** reviewed files and pinned dependencies
   cross at build time. Pull-request code must not receive release credentials;
   caches and artifacts are untrusted until validated.
4. **Internet to build:** the Ubuntu image crosses by OCI digest. Cyclestone
   crosses after the publisher-checksum procedure (fetched and trusted at
   build, not pre-pinned). Codex, agy, ollama, and opencode cross via
   publisher-trusted installers over HTTPS; agy's installer performs internal
   SHA-512 manifest verification, while codex, ollama, and opencode are
   trusted over HTTPS without client-side checksum verification. A build
   failure is preferable to a mutable or unverifiable fallback.
5. **Registry to host/runtime:** consumers verify an immutable manifest digest;
   tags are mutable discovery pointers. CI publication identity must be scoped to
   the single image family.
6. **Container to providers/local services:** projects supply only a logical ID
   and mode. The reviewed registry owns exact sources, destinations, names, and
   service metadata; authorization fingerprints the complete plan. The local
   credential interface re-evaluates persistent authorization and canonicalizes
   current-user sources at every prepare, start, or synchronization operation.
   It mounts only Codex's exact `auth.json` read-only, mounts project/provider
   isolated `auth.json` stores writable for Codex/OpenCode, or forwards exact
   environment names at runtime. Ollama's host-selected value is not serialized
   or endpoint-validated; missing `OLLAMA_HOST` fails closed.

Build-time trust is narrower and credential-free: it permits reviewed source,
the pinned base digest, and the pinned Cyclestone download only. Runtime trust is
user-selected and may include a hostile repository; build secrets must never be
converted into runtime state.

## Representative threats and mitigations

| Threat | Mitigation | Residual risk |
| --- | --- | --- |
| Workspace startup script steals host credentials | Entrypoint never evaluates workspace; no automatic credential or home mount | User can explicitly execute malicious code or mount secrets |
| Container escapes through privilege or daemon socket | Non-root default; no privileged mode, broad capabilities, or Docker/Podman socket | Runtime/kernel vulnerabilities |
| Bind-mount ownership damage | No recursive startup `chown`; documented UID/GID policy and runtime-managed mapping | Misconfigured host permissions |
| Conflicting identity mechanisms | Separate supported modes; reject Dev Container UID mutation combined with keep-id; record effective IDs and namespace maps | Unsupported clients may interpret settings differently |
| Repository lifecycle hook exfiltrates data | Review before consent; fixed non-sensitive output; no environment/HOME enumeration, credential input, provider mount, package install, or ownership repair | A user can approve a malicious later repository change |
| Cache retains sensitive or incompatible data | Persist only the named disposable Go build cache; isolate identity cases; document exact removal | Tools or users may place unexpected data in any writable volume |
| Persistent HOME becomes inaccessible | Separate named volumes by mode; validate ownership and write access before and after restart; never repair recursively | Manual cross-mode reuse can preserve incompatible numeric owners |
| Supplementary group is lost | Podman/crun `keep-groups` fixture proves access; fail with group-map and filesystem diagnostics | Remote filesystems and MAC policy may still deny access |
| Sudo turns project compromise into container-root control | Sudo absent; mount access solved through one runtime mapping, not escalation | User may build an unsupported privileged child image |
| Release or dependency substitution | Pinned base digest; Cyclestone resolved at build to latest v-tag with publisher checksum verification; publisher-trusted installers for codex/agy/ollama/opencode over HTTPS; fail closed | Compromised publisher plus installer, or GitHub TLS endpoint compromise |
| Publisher installer compromise (codex/ollama/opencode) | HTTPS + publisher trust; no client-side checksum for codex/ollama/opencode; agy verifies via internal manifest | Publisher-side compromise or installer script tampering |
| Codex release tampering | HTTPS + GitHub asset digest in API metadata; no client-side checksum verification | Publisher-side compromise |
| Malicious archive traversal | Inspect members; reject absolute/traversal/link/device/unexpected payloads before atomic install | Extractor implementation flaws |
| Tag retargeting | Consumers and CI record/pin manifest digests; mutable tags are convenience only | Users may ignore guidance |
| CI secret exfiltration/cache poisoning | No secrets for untrusted changes; minimal token permissions; validate artifacts; separate release gate | CI/platform compromise |
| Provider CLI leaks credentials | Exact reviewed files/names only; non-root sessions; no configuration-directory fallback; retained surfaces are canary-scanned | Provider, child image, remote service, or already-read process compromise |
| Local service exposes host data/network | Ollama requires explicit exact-plan approval, forwards only `OLLAMA_HOST` by name, and exposes no socket/model path | The host-selected endpoint and unauthenticated service can expose authority outside Cyclestone's validation |
| Project configuration widens provider access | Closed value-free project schema; repository-owned versioned registry; exact-name/path validation; reviewed boundary snapshot | A user may later authorize a plan for a malicious workspace |
| Registry path escapes through symlink or race | Resolver leaves placeholders unexpanded; credential operations expand only reviewed templates, reject links/types, canonicalize, and bind state to source identity before use | Canonicalization-to-use races, inode reuse, and filesystem semantics remain residual |
| Stale local approval applies to another checkout or broader plan | Canonical path plus filesystem/Git worktree identity; recomputed body fingerprints and deterministic grant IDs; exact locked matching; observed-move retirement; the credential runtime re-evaluates persistent authorization and state/source identity at every supported operation | An unobserved move away and back, device/inode reuse, and races between revalidation and access remain residual |
| Approval prompt hides effective authority or leaks a value | Prompt renders the immutable plan with explicit none fields, exact names and service risk; runtime plans preserve it and inherit environment values by name only | Container-user processes can retain values after access |
| Read-only provider access is mistaken for secrecy or full CLI support | Prompt shows Codex's exact `auth.json` file and mode; guidance distinguishes host mutation protection from credential disclosure | Untrusted processes can still read the exposed file; some CLI operations may require separate writable state |
| Multi-user data crossover | No team functionality or implicit shared trust | Future implementation must establish tenant isolation before use |

## Future team functionality

Extension points do not grant trust. Before team or multi-user behavior is added,
its design must define authenticated principals, authorization rules, identity
lifecycle, tenant/resource isolation, secret ownership, audit events, revocation,
data retention/deletion, cross-tenant tests, and incident boundaries. Until that
review is approved, all team functionality is unsupported.
