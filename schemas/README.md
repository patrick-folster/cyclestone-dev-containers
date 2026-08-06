# Schemas

Owns machine-readable public data formats and validation schemas. Schema authors
own tests and migration notes; `@patrick-folster` approves compatibility changes.
Schemas must not duplicate contracts that have no machine-readable representation.

`project-providers-v1.schema.json` is the closed project-controlled request
format. Projects may select only a logical ID, `enabled`, and one enumerated
mode. `trusted-provider-registry-v2.schema.json` describes the data-driven,
self-describing registry. Its strategy-family `oneOf` branches make filesystem,
environment, and host-service access mutually exclusive and bind each family to
matching validation metadata. Closed enums on `source_files`,
`environment_names`, and `container_destination` preserve the v1 fail-closed
access boundary. Adding a provider with a new source path, env name, or
destination requires an enum expansion (schema change + security review + snapshot
update). Adding a provider that reuses existing enum values requires only a
registry edit + snapshot update + CHANGELOG — zero shell edits. The resolver
adds repository policy checks including generic adapter coherence, duplicate
raw keys, mode/platform compatibility, and unique provider IDs.

`local-provider-grants-v1.schema.json` is the closed, host-local persistent
grant format. It records only canonical project identity, complete value-free
resolved plans, SHA-256 fingerprints, the persistent decision, and timestamp;
it is never project configuration and must not contain secret values. Runtime
loading recomputes both body fingerprints and the deterministic grant ID because
JSON Schema cannot express those cross-field derivations. The v2 update removes
per-ID `oneOf` plan branches in favor of generic mode-driven `if/then` branches
and accepts `registry_version: 2`.

`runtime-config-input-v1.schema.json` closes the generator envelope around the
existing project request. `generated-devcontainer-metadata-v1.schema.json`
defines content-derived portable provenance and intentionally has no path,
timestamp, grant, project-identity, or credential field.
