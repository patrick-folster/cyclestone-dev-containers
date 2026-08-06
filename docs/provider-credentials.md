# Provider Credential Handling

Credential preparation emits the value-free plans consumed by the separate
[runtime configuration workflow](runtime-configuration.md); it does not edit a
project Dev Container configuration itself.

The supported Linux host interface is `scripts/provider-credentials.sh`. It
accepts only a freshly re-evaluated persistent authorization, revalidates the
project identity and complete plan at each operation, and emits runtime plans
containing names and paths but no credential values. Projects cannot select an
adapter, path, destination, variable name, endpoint, or mount option.

## Strategy comparison

| Strategy | Host exposure | Refresh and synchronization | Revocation | Corruption and backup risk |
| --- | --- | --- | --- | --- |
| Exact read-only bind | One reviewed current-user `0600` regular file; private SELinux relabel on enforcing Podman hosts | Recreate the session after the host file changes; synchronization is forbidden | Stop the tracked session, then revoke | Container writes fail; private relabeling can change the source label, and the original and external backups remain outside Cyclestone deletion guarantees |
| Runtime environment | Exact reviewed names inherited with Podman's `--env NAME`; values never enter generated arguments or state | Change the host value and recreate the session | Stop the session, revoke, and rotate the provider secret when needed | Every process under the container user can read the value; shell/process retention is external |
| Isolated store | One `0600` `auth.json` in a project/provider `0700` directory, never the live host auth directory writable | Provider refreshes the isolated file; explicit `synchronize` validates shape and atomically replaces only the original file | Active sessions return `E_ACTIVE_SESSION`; after stop, state deletion precedes grant deletion | Malicious writes can corrupt only the isolated directory; unexpected siblings/types block sync. Exclude this store from backups |
| Host service | Exact `OLLAMA_HOST` name plus reviewed unauthenticated HTTP metadata; no socket or model mount | The current host supplies the runtime-local value; change it and recreate | Stop and revoke | Cyclestone does not validate endpoint syntax/reachability; authority and backups remain external |

## Built-in lifecycle

| Provider and mode | Approved source/name → destination | Lifecycle and failures |
| --- | --- | --- |
| Claude `environment` | `ANTHROPIC_API_KEY`; no file | Missing input is `E_ENV_MISSING`. Replace the host key and recreate. Revocation cannot erase a value already read; stop and rotate. |
| Agy `environment` | `GEMINI_API_KEY`; no file | Missing input is `E_ENV_MISSING`. Replace the host key and recreate. Revocation cannot erase a value already read; stop and rotate. |
| Generic `environment` | `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`; no file | Values may include credentials. Missing inputs fail; refresh requires recreation. No wildcard or prefix names are accepted. |
| Ollama `host-service` | Exact name `OLLAMA_HOST`; registry metadata records `http://host.containers.internal:11434` as the reviewed default | The current host selects the runtime value. Project configuration cannot choose it, and plans/state/logs never serialize it. Missing input is `E_ENV_MISSING`; Cyclestone performs no endpoint parsing or reachability check. Stop/recreate after changes. |
| Codex `read-only` | `${HOME}/.codex/auth.json` → `/home/developer/.codex/auth.json` | File-backed auth only. OS-keyring-only state, missing files, unknown JSON, links, wrong owner/mode, and writes fail closed. Host refresh requires recreation; sync is forbidden. |
| Codex `read-write` | Same source; imported to a project-scoped isolated store whose directory is mounted at `/home/developer/.codex` | Only isolated `auth.json` is writable. Refresh there, stop if appropriate, then explicitly synchronize. Configuration, logs, sessions, databases, and caches are excluded. |
| OpenCode `read-write` | `${HOME}/.local/share/opencode/auth.json`; isolated store mounted at `/home/developer/.local/share/opencode` | The reviewed provider-object JSON format is required. Only `auth.json` imports/synchronizes; adjacent state is excluded. |

Codex may use `auth.json` or an OS credential store depending on its external
configuration. This implementation supports only the reviewed file-backed
form. It never scans `.codex`, falls back to another source, or exposes a
keyring. OpenCode format acceptance is similarly narrow. A provider format
change is a registry/validator change requiring fixtures, boundary snapshot,
changelog, security review, and release classification before support.

## Operations

After `scripts/devcontainer-permissions.sh review` records explicit consent:

```sh
scripts/provider-credentials.sh prepare PROJECT REQUEST PROVIDER linux
scripts/provider-credentials.sh start PROJECT REQUEST PROVIDER linux IMAGE
scripts/provider-credentials.sh exec SESSION_ID COMMAND [ARG...]
scripts/provider-credentials.sh stop SESSION_ID
scripts/provider-credentials.sh synchronize PROJECT REQUEST PROVIDER linux
scripts/provider-credentials.sh list
```

`prepare` re-evaluates the complete persistent authorization, canonicalizes the
reviewed source at that operation, imports isolated state when needed, and emits
the value-free runtime plan. Source and isolated files must be regular, non-link,
invoking-user-owned `0600` files; managed state directories are invoking-user-owned
`0700`. `start` repeats those checks and uses rootless
Podman, `keep-id`, no new privileges, exact name-only environment inheritance,
and the one reviewed private-relabel bind.
Writable scope and synchronization risk appear in the authorization prompt.
`synchronize` is a separate explicit action: it rechecks authorization, source
device/inode, regular-file ownership/mode, provider JSON shape, and isolated
directory contents, then fsyncs and renames a same-filesystem temporary file.
The prior host file survives validation or pre-rename interruption. Writable
data is still untrusted; shape validation does not prove token semantics. State
metadata is also untrusted input: every load binds it back to the fresh grant,
project identity, complete plan, exact source/store paths, and recorded source
device/inode before access or synchronization.

Grant and project revocation call the credential layer while both stores are
locked. A running tracked session prevents a completed-revocation claim. Stop
or recreate it, revoke again, and rotate provider credentials after suspected
disclosure. Revocation prevents future supported starts and deletes isolated
state, but cannot retract bytes already read by a process, stop untracked
containers, erase filesystem remnants, or remove external backups. Exclude
`provider-credentials-v1` from host backups where possible; retention is
infrastructure-specific. After any restore, revoke restored state and rotate
at the provider.

Errors identify the missing name or failure class, never a value. Expired tokens
remain a provider-visible authentication failure and do not trigger alternate
source discovery. Missing input reports `E_ENV_MISSING` or
`E_CREDENTIAL_MISSING`; unsafe links/types report `E_IMPORT_UNSAFE`; ownership or
mode failures report `E_CREDENTIAL_PERMISSIONS`; provider-format drift reports
`E_CREDENTIAL_FORMAT`; interrupted writes report `E_STATE_WRITE` or
`E_SYNC_WRITE`; and source replacement reports `E_SOURCE_CHANGED`. There is no
fallback on any of these failures. Recovery is to stop sessions,
repair or replace the one host `auth.json` with invoking-user ownership and
`0600`, revoke stale state, approve the exact plan again, and rotate externally
when validity or disclosure is uncertain.

For Ollama, `E_ENV_MISSING` is the only Cyclestone endpoint-input failure: set
`OLLAMA_HOST` in the invoking host environment and recreate. Connection, HTTP,
or provider errors remain runtime/service failures and never trigger another
environment name, socket, model path, default substitution, or broader access.

Pathnames can still race after canonicalization, a process may retain bytes
after access, and filesystem/device semantics can weaken durability guarantees.
The implementation narrows these windows with locks, exact path and inode
checks, same-filesystem temporary files, fsync, and atomic rename; it does not
claim complete race elimination or live secret retraction.

Run `scripts/validate-milestone-local.sh ms-pf-0008` as one non-root Linux
account. It checks the shell/jq/GNU-file authorization dependencies and
rootless Podman/crun, builds a verified local image when none is supplied, then
exercises all five adapters without real accounts or network APIs. It retains
commit, source-digest, image identity, and value-free logs under
`dist/evidence/ms-pf-0008/local` (a local-only qualification output, not
committed to the repository). Expected read-only writes and hostile sync or
revocation attempts are asserted internally as nonzero; the aggregate command
has no expected intermediate nonzero status.
