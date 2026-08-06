# Providers

Owns provider definitions, metadata, and provider-specific policy. Provider
maintainers own their definitions; `@patrick-folster` approves compatibility or
trust-boundary changes. `registry.json` is the only resolver input and is
reviewed as code; project configuration cannot include or override definitions.
Registry version 2 is a data-driven, self-describing registry: adapter
coherence is enforced by generic strategy-family rules and closed enums, not
per-provider ID code branches. Adding a provider that reuses existing enum
values requires only a registry edit, snapshot update, and CHANGELOG — zero
shell edits. Adding a provider with a new source path, env name, or destination
requires a schema enum expansion and security review.
Provider CLI installation and real provider/API qualification remain outside
this repository. The reviewed runtime adapters are implemented by
[`scripts/provider-credentials.sh`](../scripts/provider-credentials.sh); see the
[provider reference](../docs/providers.md), [credential lifecycle
guide](../docs/provider-credentials.md), and [registry changes](CHANGELOG.md).
Codex read-only exposes only `auth.json`; Codex read-write and OpenCode mount
project-scoped isolated stores, never their live host authentication directories
writable. Ollama fixes only the `OLLAMA_HOST` name and unauthenticated service
metadata; the invoking host supplies its runtime-only value, and missing input
fails with `E_ENV_MISSING`. Agy inherits `GEMINI_API_KEY` by name only at
runtime, mirroring the Claude environment pattern.
