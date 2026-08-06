# Trusted Provider Registry Changelog

## Registry version 2 — 2026-08-05 (breaking cutover)

Registry version 2 is a breaking cutover from version 1. The registry file is
renamed from `registry-v1.json` to `registry.json` (the version lives in the
`registry_version` field). Adapter definitions are now self-describing: the
resolver validates each adapter against generic strategy-family coherence
rules (mode/strategy/source/destination pairing) plus closed enums on
`source_files`, `environment_names`, and `container_destination`, instead of
per-provider ID code branches.

**What changed:** The four core scripts (`resolve-providers.sh`,
`devcontainer-permissions.sh`, `provider-credentials.sh`,
`runtime-config-lib.sh`) no longer contain per-provider ID `if/elif` branches
or hardcoded allowlists. Provider registration is data-driven: adding a
provider that reuses existing enum values (source paths, env names,
destinations) requires only a `registry.json` edit, schema validation, snapshot
update, and this CHANGELOG — zero shell edits. Adding a provider with a new
source path, env name, or destination requires a schema enum expansion in
`trusted-provider-registry-v2.schema.json` and security review.

**What did NOT change:** The 6 existing providers' adapter metadata is
byte-identical. The access-boundary snapshot is unchanged. The closed-enum
posture on source paths, env names, and destinations is preserved. The
maintainer security review gate for every provider addition is unchanged.
The fail-closed behavior for structural and access-boundary violations is
unchanged. The v1 registry file (`registry-v1.json`) and v1 schema
(`trusted-provider-registry-v1.schema.json`) are retired.

**Consequences:** Existing grants whose plans reference `registry_version: 1`
will fail with `E_STORE_SCHEMA` and require re-approval. Plans for the 6
unchanged providers (excluding `registry_version`) are byte-identical. The
`local-provider-grants-v1.schema.json` is updated to accept
`registry_version: 2` and use generic adapter validation instead of per-ID
`oneOf` branches. Descriptive metadata fields (`import_behavior` text,
`failure_codes` list contents) are no longer pinned to exact values in the
shell validator — the fingerprint (which includes the full adapter) and the
access-boundary snapshot remain the security gates for semantic changes.

## Registry version 1 — 2026-08-04 (note)

Provider CLIs (`codex`, `agy`, `ollama`, `opencode`) may now be installed in the
base image via the `INSTALL_TOOLS` build arg, in addition to the existing child
image pattern. The registry definition for each provider is unchanged;
`required_cli.location: "container"` already covers both install locations.
Cyclestone is not added to the registry; it remains the orchestrator that
consumes providers.

## Registry version 1 — 2026-08-03 (updated)

Added `agy` (Google Antigravity CLI) as a sixth provider with an `environment`
adapter inheriting `GEMINI_API_KEY` by name only. This mirrors the Claude
environment pattern: no file source, no mount, no isolated store. The API key
is readable by every process running as the container user.

## Registry version 1 — 2026-08-01

Initial reviewed definitions: `claude`, `codex`, `generic-environment`,
`ollama`, and `opencode`. This version introduces exact Linux-only filesystem,
environment-name, host-service, CLI, write, and security metadata.

Secure-credential plan version 2 narrows Codex from its former directory plan to
the exact `${HOME}/.codex/auth.json` file. Read-only uses a direct file mount;
read-write imports that one file into a project-scoped isolated store. OpenCode
uses the same isolated-file pattern for its exact
`${HOME}/.local/share/opencode/auth.json`. Claude and proxy variables are
forwarded by exact name only, and Ollama retains its reviewed name/service
metadata without a socket. Ollama reports `E_ENV_MISSING` when its host-selected
runtime value is absent; no endpoint allowlist or separate endpoint-rejection
behavior is declared. Earlier plan-version-1 grants cannot authorize any of these adapters.
This reviewed access reduction retains registry version 1 while changing the
complete authorization fingerprint.

Changing a host source, container destination, exact environment name,
host-service endpoint or exposure, supported/recommended mode, platform, or
provider set can expand access. Such a change requires security review, an
intentional access-boundary snapshot update, this changelog, release notes, and
the image-version classification defined by the version policy. Format-breaking
changes require a new registry version. Custom definitions remain unsupported.
