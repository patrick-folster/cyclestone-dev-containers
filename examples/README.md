# Examples

Owns reviewed, non-normative usage examples. Example authors own correctness and
must link to the normative contract rather than redefining it. Examples must not
contain credentials or imply unsupported compatibility.

## SDK child-image examples

Each SDK example installs a checksum-pinned runtime for both base architectures,
restores the inherited non-root contract, and deliberately contains no `COPY` or
`ADD` instruction. Project source is bind-mounted at `/workspace` at runtime.
See [`../docs/child-images.md`](../docs/child-images.md) before adapting any of
them.

| Example | Runtime | Version | Checksum |
| --- | --- | --- | --- |
| [`child-image/`](child-image/) | Go | 1.26.5 | Publisher SHA-256 |
| [`nodejs/`](nodejs/) | Node.js / TypeScript | 22.11.0 | Publisher SHA-256 |
| [`dotnet/`](dotnet/) | .NET SDK | 8.0.423 | Publisher SHA-512 |

`child-image/Containerfile` is the original Go inheritance fixture from
milestone D-017. `nodejs/` and `dotnet/` follow the same pattern with their
respective pinned SDK downloads.

## Provider request examples

Provider examples demonstrate the value-free provider request and explicit local
authorization flow. They contain no credential values, personal host paths, or
API keys. Each has a `providers.json` project request and a
`.devcontainer/devcontainer.json` using the base image with the rootless Podman
template pattern. Provider access is never baked into an image layer; it is added
only through the reviewed authorization and runtime-configuration workflow.

| Example | Provider | Mode | Access strategy |
| --- | --- | --- | --- |
| [`codex/`](codex/) | Codex CLI | read-write | Isolated store for `${HOME}/.codex/auth.json` |
| [`ollama/`](ollama/) | Ollama | host-service | Runtime `OLLAMA_HOST` environment name |

See [`../docs/providers.md`](../docs/providers.md) for the trusted registry,
[`../docs/provider-authorization.md`](../docs/provider-authorization.md) for
the consent interface, and [`../docs/runtime-configuration.md`](../docs/runtime-configuration.md)
for the generated configuration workflow.

### Authorizing a provider request

The request file is value-free. Authorization requires a controlling terminal
and a tracked file matching `HEAD`:

```sh
scripts/devcontainer-permissions.sh review "$PWD" providers.json codex linux
scripts/devcontainer-permissions.sh authorize "$PWD" providers.json codex linux
```

`review` displays the exact resolved plan and prompts for `once`, `always`, or
`deny`. `authorize` is noninteractive and succeeds only for one exact active
persistent grant. See
[`../docs/provider-authorization.md`](../docs/provider-authorization.md) for
identity semantics, revocation, and residual risks.

### Generating runtime configuration

After authorization, generate and validate the Dev Container configuration:

```sh
scripts/devcontainer-generate.sh "$PWD" providers.json --dry-run
scripts/devcontainer-validate.sh "$PWD" providers.json
```

The generated local runtime file is git-ignored and must be selected explicitly
at startup. See [`../docs/runtime-configuration.md`](../docs/runtime-configuration.md).
