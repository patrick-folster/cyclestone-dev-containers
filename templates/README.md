# Dev Container Templates

Owns Dev Container templates and their consumer-facing defaults. Template
maintainers own implementation; `@patrick-folster` approves changes to promised
Dev Container behavior. Image definitions and general examples belong elsewhere.

`project-devcontainer/.devcontainer/` is the reusable project template. Copy
that directory to a reviewed project repository, supply the canonical Cyclestone
base manifest digest through `CYCLESTONE_BASE_IMAGE_REF`, and follow
[`../docs/devcontainers.md`](../docs/devcontainers.md). It installs the same
checksum-pinned Go SDK as the inheritance example, mounts the entire project at
`/workspace`, and persists only the named, disposable Go build cache.
This file is also the reviewed structural input for runtime generation. Projects
cannot override its privilege-bearing fields through provider input; see
[`../docs/runtime-configuration.md`](../docs/runtime-configuration.md).

## Related examples

The [`../examples/`](../examples/) directory contains five example projects that
demonstrate the template and child-image patterns:

- [`../examples/child-image/`](../examples/child-image/) — Go SDK child image
- [`../examples/nodejs/`](../examples/nodejs/) — Node.js/TypeScript SDK child image
- [`../examples/dotnet/`](../examples/dotnet/) — .NET SDK child image
- [`../examples/codex/`](../examples/codex/) — Codex provider request example
- [`../examples/ollama/`](../examples/ollama/) — Ollama provider request example

See [`../docs/quick-start.md`](../docs/quick-start.md) for a guided path and
[`../docs/troubleshooting.md`](../docs/troubleshooting.md) for common failure
modes.
