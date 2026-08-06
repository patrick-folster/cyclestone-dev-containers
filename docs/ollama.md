# Ollama Host Service Setup

Ollama is a supported `host-service` provider. The trusted registry defines
exactly one unauthenticated TCP/HTTP endpoint selected at runtime by the
`OLLAMA_HOST` environment variable name. No engine socket, model directory, or
credential file is mounted into the container.

> **Review before consent:** the Ollama provider discloses the reviewed
> unauthenticated endpoint to every process running as the container user. It
> does not expose the Ollama daemon socket or the host model store. Approve the
> request only after reading the provider plan displayed by
> `scripts/devcontainer-permissions.sh review`.

## Prerequisites

### Install and start Ollama on the host

Install Ollama on the host following the
[official instructions](https://ollama.com/download). On a supported native
Linux host:

```sh
curl -fsSL https://ollama.com/install.sh | sh
systemctl --user start ollama
```

The default host endpoint is `http://127.0.0.1:11434`. The trusted registry's
default container-visible endpoint is
`http://host.containers.internal:11434`, which resolves to the host loopback
through the rootless Podman network namespace.

### Pull a model

Pull a model before starting the development container so the first request does
not time out:

```sh
ollama pull llama3.1
```

Models are stored under `~/.ollama` on the host. This directory is never mounted
into the container.

## GPU access

Ollama uses the host GPU transparently. The container does not need GPU device
mounts, CUDA toolkits, or container runtime GPU support because the Ollama
daemon runs on the host and the container only makes HTTP requests to it.

If the host has a supported GPU, verify it is detected:

```sh
ollama ps
```

The `ollama` CLI inside the container (installed in the base when `INSTALL_TOOLS`
includes `ollama`, or by a child image)
makes HTTP requests to the host daemon; it does not execute model inference
inside the container.

## CPU-only operation

On hosts without a GPU, Ollama falls back to CPU inference automatically. No
configuration change is needed. Expect slower token generation.

## Request Ollama in a project

Create a `providers.json` in the project root:

```json
{
  "version": 1,
  "providers": {
    "ollama": { "enabled": true, "mode": "host-service" }
  }
}
```

Authorize the request (requires a controlling terminal):

```sh
scripts/devcontainer-permissions.sh review "$PWD" providers.json ollama linux
scripts/devcontainer-permissions.sh authorize "$PWD" providers.json ollama linux
```

Generate and validate the runtime configuration:

```sh
scripts/devcontainer-generate.sh "$PWD" providers.json --dry-run
scripts/devcontainer-validate.sh "$PWD" providers.json
```

The generated local runtime file sets `OLLAMA_HOST` at container startup. The
value is supplied by the host environment; the project request and trusted
registry never contain an endpoint value.

## Verify connectivity inside the container

After starting the development container, verify the endpoint is reachable:

```sh
curl -sSf "$OLLAMA_HOST/api/tags" | jq .
```

If the connection is refused, see
[troubleshooting.md](troubleshooting.md#unavailable-host-services) for
diagnosis steps.

## Security notes

- No credential material is copied into the container.
- The `OLLAMA_HOST` value is a host-selected runtime variable. Cyclestone
  checks that the name is present (`E_ENV_MISSING` when absent) but does not
  parse, allowlist, serialize, or probe that value.
- No Ollama daemon socket or model directory is exposed to the container.
- Revoking the grant stops future sessions; it cannot retract bytes already
  read or stop untracked processes. See
  [provider-credentials.md](provider-credentials.md).

See [providers.md](providers.md) for the trusted registry boundary and
[troubleshooting.md](troubleshooting.md) for common failure modes.
