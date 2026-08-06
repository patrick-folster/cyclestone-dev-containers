# Trusted Providers

Registry version 2 converts a committed, value-free logical request into a
deterministic plan version 2. The complete selected credential adapter is part
of the authorization fingerprint. Earlier plans that exposed whole Codex or
OpenCode directories cannot authorize materialization after this change.

Registry version 2 is a breaking cutover from version 1. The registry file is
`providers/registry.json` (the version lives in the `registry_version` field, not
the filename). Adapter definitions are self-describing; the resolver validates
each adapter against generic strategy-family coherence rules (mode/strategy/
source/destination pairing) plus closed enums on `source_files`,
`environment_names`, and `container_destination`. Adding a provider that reuses
existing enum values requires only a registry edit, snapshot update, and
CHANGELOG entry — zero shell edits. Adding a provider with a new source path,
env name, or destination requires a schema enum expansion (security review).

Projects may supply only `version`, provider ID, `enabled`, and `mode`. The
repository-owned registry contains every source, destination, environment
name, endpoint, access mode, import/synchronization rule, refresh and revocation
behavior, permission, backup warning, and stable failure family. The resolver
accepts no project-defined adapter, path, value, environment name, endpoint, or
mount option.

| ID | Modes | Credential strategy and exact boundary |
| --- | --- | --- |
| `claude` | `environment` | Runtime inheritance of `ANTHROPIC_API_KEY` by name only |
| `codex` | `read-only`, `read-write` | Exact `${HOME}/.codex/auth.json`; read-only direct file or read-write project-scoped isolated store; destination `/home/developer/.codex/auth.json` |
| `generic-environment` | `environment` | Exact `HTTPS_PROXY`, `HTTP_PROXY`, and `NO_PROXY` names |
| `ollama` | `host-service` | Exact runtime name `OLLAMA_HOST` and reviewed unauthenticated TCP/HTTP metadata; the current host selects the value, with no socket or model mount |
| `opencode` | `read-write` | Exact `${HOME}/.local/share/opencode/auth.json` imported into a project-scoped isolated store; destination `/home/developer/.local/share/opencode/auth.json` |
| `agy` | `environment` | Runtime inheritance of `GEMINI_API_KEY` by name only |

Run `scripts/resolve-providers.sh PROJECT PROVIDER linux`. Output is sorted,
compact JSON and contains no credential value. Duplicate keys, root/home/config
or authentication-directory grants, traversal, links expressed as paths,
engine sockets, undeclared files, arbitrary destinations, unknown environment
names, endpoint drift, and registry extensions fail with stable errors.
Endpoint drift here means mutation of trusted registry metadata. The project
cannot supply an endpoint; the invoking host supplies the runtime-only
`OLLAMA_HOST` value. Cyclestone checks that the name is present and reports
`E_ENV_MISSING` when absent, but does not parse, allowlist, serialize, or probe
that host-selected value.

The boundary snapshot in
`tests/fixtures/providers/snapshots/access-boundaries.json` records all adapter
metadata. Expansion requires maintainer security review, schema and hostile
fixture updates, snapshot review, a changelog entry, and release classification.
Provider format changes are external contract changes and fail closed until the
file validator and lifecycle evidence are reviewed. Registry version 2 still
requires maintainer security review for every provider addition; the win is
"data-driven registration without shell code edits," not "no review."

See [provider-authorization.md](provider-authorization.md) for consent and
[provider-credentials.md](provider-credentials.md) for materialization,
refresh, synchronization, revocation, recovery, and backup operations.
