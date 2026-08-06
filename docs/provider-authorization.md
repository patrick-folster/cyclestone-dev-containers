# Local Provider Authorization

Authorization records consent but applies no runtime access. The separate
[runtime configuration workflow](runtime-configuration.md) consumes a fresh
persistent evaluation.

Provider authorization is the host-side consent boundary between an untrusted,
committed logical request and the reviewed, value-free plan emitted by the
trusted registry. Authorization itself does not apply access. The separate
`scripts/provider-credentials.sh` interface consumes only a fresh persistent
authorization and materializes the exact adapter described in
[provider-credentials.md](provider-credentials.md); neither interface generates
Dev Container configuration, contacts a provider API, or installs a provider
CLI.

## Review and evaluate

The supported authorization interface is `scripts/devcontainer-permissions.sh`.
The pinned Cyclestone v0.0.2 binary has no subcommand extension API, and this
repository does not provide a Cyclestone `devcontainer` command namespace,
wrapper, alias, or shadow binary:

```sh
scripts/devcontainer-permissions.sh review PROJECT_ROOT REQUEST_FILE PROVIDER_ID linux
scripts/devcontainer-permissions.sh authorize PROJECT_ROOT REQUEST_FILE PROVIDER_ID linux
scripts/devcontainer-permissions.sh list
scripts/devcontainer-permissions.sh revoke GRANT_ID
scripts/devcontainer-permissions.sh revoke-project PROJECT_ROOT
```

`review` requires a controlling terminal. Before reading a choice it displays
the exact resolved provider, source and destination or explicit `none`, access
mode, sorted environment variable names without values, host endpoint,
transport and authentication, write behavior, project identity, and security
guidance. `deny` stores nothing. `once` returns one authorized plan only from
that approving command and is never persisted; a later `authorize` call and
credential materialization still require approval. The emitted JSON is not a
replay-proof capability and is not accepted by the credential interface.
`always` stores the exact identity-plus-plan approval. The
prompt cannot change the requested mode: read-only and read-write are distinct
fingerprinted plans. Codex read-only exposes only the reviewed regular
`${HOME}/.codex/auth.json` at `/home/developer/.codex/auth.json`; configuration,
logs, sessions, databases, and sibling files are excluded. It still discloses
that file to processes running as the container user. Codex read-write and
OpenCode use separate project/provider isolated stores rather than writable live
host authentication directories.

`authorize` is noninteractive and succeeds only for one exact active persistent
grant. When approval is absent, stale, or narrower, it returns
`E_APPROVAL_REQUIRED` and points to `review`; it never silently prompts or
persists. Both commands resolve through `scripts/resolve-providers.sh`, hash the
complete canonical plan, and re-resolve the plan and identity under the store
lock immediately before emitting authorization. Persistent records are accepted
only when their closed shape, canonical identity and plan bodies, recomputed
fingerprints, and deterministic ID all agree exactly. Any provider, registry,
platform, mode, path, destination, variable-name, service, or prompt-safe
security-metadata change therefore requires fresh approval.
The request path must remain inside the canonical project. In Git projects it
must be a tracked regular file whose content matches `HEAD`; symlinked,
untracked, modified, outside, unknown, disabled, and unresolved requests fail
before consent evaluation.

## Project identity

Identity version 1 always contains the canonical real path and directory device
and inode. A Git worktree additionally binds the canonical per-worktree Git
directory, common Git directory, their device/inode identities, object format,
and a hash of the repository root-commit set. A symlink to the same root resolves
to the same identity, but symlinked Git metadata is rejected.

The conservative outcomes are intentional: moving a checkout invalidates its
grant; observing the moved filesystem identity during authorization retires the
prior path-scoped grant, so moving it back cannot revive that approval. Replacing
content at the same path invalidates it; a clone is separate;
and every linked worktree is separate even though worktrees share a common
object database. A directory without Git metadata receives a separately scoped
non-Git identity. Ambiguous metadata fails closed. Paths, inode data, and Git
history are each insufficient alone; inode reuse and a filesystem race after
authorization remain residual limitations. A move away and back that is never
observed cannot be distinguished when the same path and inode return. The
credential interface canonicalizes and revalidates the reviewed source and full
persistent authorization at each prepare, start, and synchronization operation;
a canonicalization-to-use filesystem race still remains.

## Local state and revocation

State is stored under `CYCLESTONE_DATA_DIR/provider-permissions-v1`, or under
`${XDG_DATA_HOME}/cyclestone` / `${HOME}/.local/share/cyclestone` when the
explicit directory is absent. The location must be absolute and outside the
project. Directories are `0700`; the locked JSON store and lock are `0600` and
owned by the invoking user. Updates use an exclusive lock, a same-filesystem
temporary file, fsync, and atomic rename. Symlinks, wrong owners, wrong types,
unsafe pre-existing modes, invalid schemas, inconsistent fingerprints, and
non-deterministic IDs are rejected rather than repaired. A failed replacement
before atomic rename leaves the prior valid store in place.

The store contains canonical identities, complete value-free plans,
fingerprints, decisions, and timestamps. It never reads or stores environment
values, tokens, or credential contents. `list` emits only audit-safe project and
request scope. Exact and project-wide revocation coordinate with the credential
state store. A tracked running session returns `E_ACTIVE_SESSION` without
deleting the grant or claiming completion. After every tracked session is
stopped, revocation deletes matching isolated and synchronization state before
deleting the grant; the next matching `authorize`, `prepare`, or `start`
evaluation returns `E_APPROVAL_REQUIRED`. This does not retract bytes already
read by a running or untracked process and cannot erase external backups. Stop
sessions and rotate provider credentials after suspected disclosure or restore.

Repositories and their lifecycle code remain untrusted after approval. A
writable isolated file contains malicious container output until synchronization
revalidates it; environment values are visible to the container user; and an
unauthenticated host service can confer authority beyond its URL. The current
host, not project configuration, supplies `OLLAMA_HOST`; its value is inherited
only at runtime and missing input fails with `E_ENV_MISSING`, without endpoint
validation or fallback. Review changes before consent, revoke grants no longer
needed, and treat authorization as one part of the runtime boundary rather than
runtime isolation by itself.
