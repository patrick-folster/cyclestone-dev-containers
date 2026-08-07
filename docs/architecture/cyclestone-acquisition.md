# Tool Acquisition Contract

Image line `1.x` installs tools via the uniform native installer
`scripts/install-tools.sh`. All tools are opt-in through the `INSTALL_TOOLS`
build arg (comma-separated list). An empty selection produces a valid
empty-toolset base image. Cyclestone is treated uniformly with the other tools
and is not mandatory.

## Install contexts

Tools are installed in one of two contexts:

- **User tools** (cyclestone, codex, agy, opencode) are installed as the
  `developer` user under `$HOME` so the resulting files are owned by
  developer and runtime `cyclestone-tools update` works without root.
  cyclestone, codex, and agy install to `/home/developer/.local/bin/`;
  Codex installs both `codex` and `codex-code-mode-host` there;
  opencode installs to `/home/developer/.opencode/bin/` (hardcoded by its
  installer). PATH in the image puts `~/.local/bin` and `~/.opencode/bin`
  ahead of `/usr/local/bin`, so these resolve at runtime.
- **System tools** (ollama) are installed as root to `/usr/local/bin` and
  require root at build time; runtime updates are unsupported.

agy in particular must run as developer, not root: its installer hardcodes a
staging tree under `$HOME/.cache/antigravity` and leaves the directories
behind on exit. A root install would persist root-owned staging the non-root
developer cannot write into at runtime, breaking `cyclestone-tools update`
with curl exit 23 ("Failure writing output to destination").

## Supported tools

| Tool | Source | Verification | Build install location |
| --- | --- | --- | --- |
| `cyclestone` | GitHub releases latest v-tag | Publisher `checksums.txt` fetched and trusted at build; archive digest verified against it | `/home/developer/.local/bin/cyclestone` |
| `codex` | GitHub releases latest | Publisher-trusted (HTTPS); exact-tag, architecture-matched pair with structural and CLI-version validation | `/home/developer/.local/bin/codex` and `/home/developer/.local/bin/codex-code-mode-host` |
| `agy` | `https://antigravity.google/cli/install.sh` with `--dir` | Publisher installer performs internal SHA-512 manifest verification | `/home/developer/.local/bin/agy` |
| `ollama` | `https://ollama.com/install.sh` | Publisher-trusted (HTTPS); no client-side checksum | `/usr/local/bin/ollama` |
| `opencode` | `https://opencode.ai/install` with `--no-modify-path` | Publisher-trusted (HTTPS); no client-side checksum | `/home/developer/.opencode/bin/opencode` |

Source URLs are documented constants in `images/base/versions.env`, not
immutable pins. Latest releases are resolved at build time via the GitHub
releases API or publisher installers. This makes builds non-reproducible by
design; resolved versions must be recorded in release evidence per build.

## Cyclestone acquisition sequence

1. Resolve the latest v-tag via the GitHub API endpoint
   `https://api.github.com/repos/patrick-folster/cyclestone/releases/latest`
   and parse `tag_name`. Fail closed on API failure or unparseable response.
2. Select the artifact by target architecture:
   - `linux/amd64` → `cyclestone_<version>_linux_amd64.tar.gz`
   - `linux/arm64` → `cyclestone_<version>_linux_arm64.tar.gz`
3. Download `checksums.txt` and the selected archive over HTTPS into a
   temporary directory. Do not send credentials or follow a redirect to a
   non-HTTPS destination.
4. Parse exactly one SHA-256 record for the selected filename from the
   publisher checksum document. Fail closed on missing, duplicate, or
   malformed records.
5. Verify the downloaded archive digest against the publisher checksum record.
6. Inspect archive members; reject absolute paths, `..` traversal, links,
   devices, or unexpected members. Only `cyclestone`, `LICENSE.md`,
   `README.md`, and `CHANGELOG.md` are expected regular files.
7. Install atomically into `/home/developer/.local/bin` (user context, as the
   `developer` user), install the upstream license into
   `/home/developer/.local/share/licenses/cyclestone/`, and verify
   `cyclestone --version` reports the resolved version without executing
   workspace content.

Missing downloads, HTTP failures, absent or malformed checksum documents,
duplicate or missing artifact records, byte mismatches, unsafe archive
members, extraction errors, or version mismatches must fail the build before installation. No previous binary may be retained as a silent fallback.

The publisher `checksums.txt` is trusted at build time; it is not pre-pinned
in `versions.env`. The upstream release does not currently provide a signature
or provenance attestation. Adding signature or provenance verification is a
compatible security improvement.

## Codex acquisition sequence

1. Resolve the latest release tag once through
   `https://api.github.com/repos/openai/codex/releases/latest`. Accept the
   publisher's `rust-v<version>` or `v<version>` tag forms and validate the
   normalized release version.
2. Map the target architecture once and select both official artifacts from
   that exact tag:
   - `linux/amd64` → `codex-x86_64-unknown-linux-musl.tar.gz` and
     `codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz`
   - `linux/arm64` → `codex-aarch64-unknown-linux-musl.tar.gz` and
     `codex-code-mode-host-aarch64-unknown-linux-musl.tar.gz`
   Unsupported targets fail with an explicit error before downloading.
3. Download both archives over HTTPS into one temporary staging directory.
   A failure or empty response for either artifact aborts without changing an
   installed pair.
4. Inspect each archive before publication. Each must contain exactly one
   regular member whose name matches the selected target; links, devices,
   traversal, extra members, and wrong-architecture member names fail closed.
5. Extract both executables with mode `0755`, verify both staged regular files
   are executable, and verify staged `codex --version` matches the single
   resolved release. The host does not expose a reliable version command.
6. Record the normalized version, target, and SHA-256 of both extracted files
   in `/home/developer/.local/bin/.codex-install-metadata`. This trusted,
   user-owned metadata proves which pair the installer published without
   modifying `~/.codex/config.toml`.
7. Only after every check passes, publish `codex`, `codex-code-mode-host`, and
   their metadata through same-filesystem renames. Existing files are retained
   inside the transaction until all three replacements succeed and are restored
   if publication fails partway through.

The separately distributed Codex executable archives do not use a shared
`checksums.txt` document in this installer, so the publisher remains trusted
over HTTPS as before. Exact-tag pairing, strict member validation, version
validation, and installed-file hashes strengthen consistency but do not replace
a publisher-signed artifact digest. This reduced authenticity verification is
documented in the threat model.

## Agy acquisition sequence

1. Download the installer script from
   `https://antigravity.google/cli/install.sh` over HTTPS.
2. Verify the installer is a shell script (shebang check).
3. Execute the installer with `--dir <prefix>` as the `developer` user to
   override the install location. The installer queries its release manifest,
   downloads the binary into a staging tree under
   `$HOME/.cache/antigravity/staging`, and verifies it against the manifest's
   SHA-512 checksum internally.
4. Verify `agy` is executable at the target prefix.

The agy installer performs its own publisher-manifest SHA-512 verification.

agy is installed in the user context (as `developer`) rather than the system
context (as root) because the installer hardcodes its staging tree under
`$HOME/.cache/antigravity`. Installing as root would leave a root-owned
staging tree behind that the non-root developer cannot write into at
runtime, breaking `cyclestone-tools update` with curl exit 23.

## Ollama acquisition sequence

1. Download the installer script from `https://ollama.com/install.sh` over
   HTTPS.
2. Verify the installer is a shell script (shebang check).
3. Execute the installer as root. The installer writes `/usr/local/bin/ollama`.
4. Verify `ollama` is executable at `/usr/local/bin/ollama`.

Ollama installs as a system binary and requires root at build time. Runtime
updates are not supported; rebuild the image to update ollama.

## OpenCode acquisition sequence

1. Download the installer script from `https://opencode.ai/install` over HTTPS.
2. Verify the installer is a shell script (shebang check).
3. Execute the installer with `--no-modify-path` as the `developer` user. The
   installer writes `$HOME/.opencode/bin/opencode`.
4. Verify `opencode` is executable at `$HOME/.opencode/bin/opencode`.

The opencode installer hardcodes `$HOME/.opencode/bin` and does not support a
`--dir` override. PATH in the image includes this directory.

## Runtime updates

The installer is shipped into the image at `/usr/local/bin/cyclestone-tools`.
At runtime as the `developer` user:

- `cyclestone-tools status` lists installed tools and versions.
- `cyclestone-tools update` updates all user-installable tools (cyclestone,
  codex, agy, opencode) to their latest versions in the user's home. The
  `INSTALL_TOOLS` build arg is a build-time selection record and is ignored
  by `update`; the runtime default is the full user-installable set. Ollama
  is excluded (system install requires root and image rebuild).
- `cyclestone-tools update --tool <name>` updates a single tool.
- `cyclestone-tools install --tool <name>` installs a tool not selected at
  build time into the user's home (system tools like ollama require rebuild).

Codex install and update always operate on `codex` and
`codex-code-mode-host` together. Update deliberately stages and republishes the
complete latest pair even when `codex --version` is already current, repairing a
missing, non-executable, corrupt, stale, or unprovable host and mismatched
installation metadata.

## Verification evidence

The automated repository tests validate the installer with mocked fixtures:
valid cyclestone install with publisher checksum verification, hostile
archive rejection (tampered archive, checksum mismatch, symlink member,
missing or duplicate publisher records), paired Codex install/update/repair
and failure rollback with mocked exact-tag releases, agy install targeting the
user prefix, empty-selection no-op, and selection parsing (env, `--tool` args,
dedupe, unknown tool rejection, comma-list). Native installed-version checks
remain required before publication.
