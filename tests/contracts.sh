#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_file() {
  test -s "$1" || fail "missing or empty file: $1"
}

require_text() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

for area in images scripts providers templates tests examples .github/workflows schemas docs; do
  require_file "$area/README.md"
done

for document in repository-layout image-contract cyclestone-acquisition compatibility versioning threat-model mvp validation-checklist release-reproduction delivery-roadmap; do
  require_file "docs/architecture/$document.md"
done
require_file README.md
require_file .cyclestone/DECISIONS.md
require_file docs/workspace-identity.md
require_file docs/child-images.md
require_file docs/devcontainers.md
require_file docs/provider-authorization.md
require_file docs/provider-credentials.md
require_file docs/ollama.md
require_file docs/selinux.md
require_file docs/upgrades.md
require_file docs/quick-start.md
require_file docs/troubleshooting.md

for implementation in \
  .dockerignore \
  images/base/Containerfile \
  images/base/packages.txt \
  images/base/versions.env \
  images/base/entrypoint.sh \
  scripts/install-tools.sh \
  scripts/build-base.sh \
  scripts/build-child-image.sh \
  scripts/resolve-providers.sh \
  scripts/devcontainer-permissions.sh \
  scripts/provider-credentials.sh \
  examples/child-image/Containerfile \
  examples/child-image/versions.env \
  examples/nodejs/Containerfile \
  examples/nodejs/versions.env \
  examples/nodejs/.devcontainer/devcontainer.json \
  examples/dotnet/Containerfile \
  examples/dotnet/versions.env \
  examples/dotnet/.devcontainer/devcontainer.json \
  examples/codex/providers.json \
  examples/codex/.devcontainer/devcontainer.json \
  examples/ollama/providers.json \
  examples/ollama/.devcontainer/devcontainer.json \
  examples/agy/providers.json \
  examples/agy/.devcontainer/devcontainer.json \
  tests/examples-build.sh \
  scripts/validate-docs.sh \
  tests/child-image-contract.sh \
  tests/child-image-inheritance.sh \
  tests/child-image-static.sh \
  tests/provider-registry.sh \
  tests/provider-authorization.sh \
  tests/provider-credentials.sh \
  tests/install-tools.sh \
  tests/build-base.sh \
  tests/build-base-podman.sh \
  tests/image-inspect-archive.sh \
  tests/image-smoke.sh \
  tests/image-inspect.sh \
  tests/rootless-bind-mount.sh \
  tests/rootless-podman.sh \
  tests/workspace-identity.sh \
  tests/devcontainer.sh \
  tests/devcontainer-podman.sh \
  scripts/build-base-podman.sh \
  scripts/validate-milestone-local.sh \
  templates/project-devcontainer/.devcontainer/Containerfile \
  templates/project-devcontainer/.devcontainer/devcontainer.json \
  templates/project-devcontainer/.devcontainer/lifecycle.sh \
  tests/fixtures/devcontainer/.devcontainer/devcontainer.json \
  tests/fixtures/devcontainer-podman/runtime.sh \
  tests/fixtures/workspace-identity/assertions.sh \
  scripts/validate-base-native.sh \
  .github/workflows/base-image-validation.yml \
  .github/workflows/release-image.yml \
  docs/base-image.md; do
  require_file "$implementation"
done

for executable in scripts/install-tools.sh images/base/entrypoint.sh \
  scripts/build-base.sh tests/contracts.sh tests/install-tools.sh \
  scripts/resolve-providers.sh tests/provider-registry.sh \
  scripts/devcontainer-permissions.sh tests/provider-authorization.sh \
  scripts/provider-credentials.sh tests/provider-credentials.sh \
  scripts/build-child-image.sh tests/child-image-contract.sh \
  tests/child-image-inheritance.sh tests/child-image-static.sh \
  scripts/validate-base-native.sh tests/build-base.sh tests/build-base-podman.sh tests/image-inspect-archive.sh \
  tests/image-smoke.sh tests/image-inspect.sh tests/rootless-bind-mount.sh \
  tests/rootless-podman.sh tests/workspace-identity.sh tests/devcontainer.sh \
  tests/devcontainer-podman.sh \
  scripts/build-base-podman.sh scripts/validate-milestone-local.sh \
  scripts/validate-docs.sh tests/examples-build.sh \
  templates/project-devcontainer/.devcontainer/lifecycle.sh \
  tests/fixtures/devcontainer-podman/runtime.sh \
  tests/fixtures/workspace-identity/assertions.sh; do
  test -x "$executable" || fail "not executable: $executable"
  sh -n "$executable" || fail "shell syntax error: $executable"
done

LC_ALL=C sort -c images/base/packages.txt || fail 'package manifest is not sorted'
if grep -Eq '^(sudo|golang|nodejs|npm|dotnet|python|openjdk|default-jre|default-jdk|ruby|php|rustc|cargo)$' images/base/packages.txt; then
  fail 'forbidden runtime, SDK, or sudo in package manifest'
fi
require_text images/base/Containerfile 'COPY images/base/packages.txt /tmp/base-packages.txt'
require_text images/base/Containerfile '--mount=type=bind,from=acquisition,source=/tmp/base-packages.txt,target=/tmp/base-packages.txt,readonly'
require_text tests/devcontainer-podman.sh 'podman exec "$container_id"'
require_text docs/devcontainers.md 'container_id=$(printf'
require_text tests/devcontainer-podman.sh 'export CYCLESTONE_BASE_IMAGE_REF="$base_id"'
require_text tests/devcontainer-podman.sh '.build.options = ["--pull=never"]'
require_text tests/devcontainer-podman.sh "authorization:[[:space:]]+null"
require_text tests/devcontainer-podman.sh 'prohibited-credential-matches.txt'
if grep -Eq 'devcontainer .*exec' tests/devcontainer.sh tests/devcontainer-podman.sh docs/devcontainers.md; then
  fail 'Dev Container CLI 0.86.0 exec forwards its subcommand token in the qualified toolchain'
fi

require_text docs/architecture/repository-layout.md 'ghcr.io/patrick-folster/cyclestone-dev-container-base'
require_text docs/architecture/repository-layout.md 'git@github.com:patrick-folster/cyclestone-dev-containers.git'

for path in \
  /home/developer \
  /workspace \
  /home/developer/.config \
  /home/developer/.cache \
  /home/developer/.local/share \
  /home/developer/.config/cyclestone \
  /home/developer/.local/share/cyclestone; do
  case "$path" in /*) ;; *) fail "contract path is not absolute: $path" ;; esac
  require_text docs/architecture/image-contract.md "$path"
  require_text docs/architecture/validation-checklist.md "$path"
done

for variable in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME CYCLESTONE_CONFIG_DIR CYCLESTONE_DATA_DIR INSTALL_TOOLS; do
  require_text docs/architecture/image-contract.md "\`$variable\`"
done

for label in \
  org.opencontainers.image.title \
  org.opencontainers.image.description \
  org.opencontainers.image.source \
  org.opencontainers.image.url \
  org.opencontainers.image.documentation \
  org.opencontainers.image.licenses \
  org.opencontainers.image.version \
  org.opencontainers.image.revision \
  org.opencontainers.image.created \
  org.opencontainers.image.base.digest \
  io.cyclestone.image.version \
  io.cyclestone.tools; do
  require_text docs/architecture/image-contract.md "$label"
done

require_text images/base/versions.env 'BASE_IMAGE=ubuntu:24.04@sha256:'
require_text images/base/versions.env 'BASE_AMD64_MANIFEST=sha256:'
require_text images/base/versions.env 'BASE_ARM64_MANIFEST=sha256:'
require_text images/base/versions.env 'INSTALL_TOOLS_DEFAULT='
require_text images/base/versions.env 'CYCLESTONE_RELEASES_URL=https://github.com/patrick-folster/cyclestone/releases/latest'
require_text images/base/versions.env 'CODEX_RELEASES_URL=https://github.com/openai/codex/releases/latest'
require_text images/base/versions.env 'AGY_INSTALLER_URL=https://antigravity.google/cli/install.sh'
require_text images/base/versions.env 'OLLAMA_INSTALLER_URL=https://ollama.com/install.sh'
require_text images/base/versions.env 'OPENCODE_INSTALLER_URL=https://opencode.ai/install'
require_text images/base/Containerfile 'ARG INSTALL_TOOLS'
require_text images/base/Containerfile 'INSTALL_TOOLS=${INSTALL_TOOLS:-}'
require_text images/base/Containerfile 'io.cyclestone.tools'
require_text images/base/Containerfile 'USER developer'
require_text images/base/Containerfile 'WORKDIR /workspace'
require_text images/base/Containerfile 'ENTRYPOINT ["/usr/local/bin/cyclestone-entrypoint"]'
require_text images/base/entrypoint.sh 'exec "$@"'
require_text scripts/build-base.sh 'linux/amd64,linux/arm64'
require_text scripts/build-base.sh 'type=oci,dest='
require_text scripts/build-base.sh 'INSTALL_TOOLS'
require_text scripts/install-tools.sh 'install_cyclestone'
require_text scripts/install-tools.sh 'install_codex'
require_text scripts/install-tools.sh 'install_agy'
require_text scripts/install-tools.sh 'install_ollama'
require_text scripts/install-tools.sh 'install_opencode'
require_text scripts/install-tools.sh 'releases/latest'
require_text .dockerignore '**'

./tests/install-tools.sh
./tests/build-base.sh
./tests/build-base-podman.sh
./tests/image-inspect-archive.sh
./tests/child-image-static.sh
./tests/provider-registry.sh
./tests/provider-authorization.sh
PROVIDER_CREDENTIALS_STATIC_ONLY=1 timeout 90 ./tests/provider-credentials.sh

for provider_contract in \
  schemas/project-providers-v1.schema.json \
  schemas/trusted-provider-registry-v2.schema.json \
  schemas/local-provider-grants-v1.schema.json \
  schemas/provider-credential-state-v1.schema.json \
  providers/registry.json \
  providers/CHANGELOG.md \
  docs/providers.md; do
  require_file "$provider_contract"
done
jq -e . schemas/project-providers-v1.schema.json schemas/trusted-provider-registry-v2.schema.json schemas/local-provider-grants-v1.schema.json schemas/provider-credential-state-v1.schema.json providers/registry.json >/dev/null \
  || fail 'provider schema or registry JSON is invalid'
require_text docs/provider-authorization.md 'replay-proof capability'
require_text docs/provider-authorization.md 'moving it back cannot revive that approval'
require_text docs/provider-authorization.md 'The supported authorization interface is `scripts/devcontainer-permissions.sh`.'
require_text docs/provider-authorization.md 'the next matching'
require_text docs/provider-authorization.md '`E_APPROVAL_REQUIRED`'
require_text docs/provider-authorization.md 'scripts/devcontainer-permissions.sh list'
unsupported_cli='cyclestone devcontainer'' permissions'
if grep -R -F "$unsupported_cli" README.md docs scripts >/dev/null; then
  fail 'current authorization contracts require an unsupported Cyclestone command namespace'
fi
require_text scripts/devcontainer-permissions.sh 'computed_id=$(sha256_text'
require_text scripts/devcontainer-permissions.sh 'and .identity==$identity and .plan==$plan'
require_text scripts/provider-credentials.sh 'relabel=private'
require_text scripts/provider-credentials.sh 'E_ACTIVE_SESSION'
require_text scripts/provider-credentials.sh 'validate_metadata_context'
require_text docs/provider-credentials.md 'scripts/provider-credentials.sh'
require_text docs/provider-credentials.md 'external backups'
require_text docs/provider-credentials.md 'device/inode'
require_text providers/CHANGELOG.md 'plan version 2'
require_text .cyclestone/DECISIONS.md 'D-030 Provider credential adapters and isolated synchronization'
require_text README.md './scripts/validate-milestone-local.sh ms-pf-0008'
require_text scripts/validate-milestone-local.sh 'ms-pf-0014|ms-pf-0014-templates-examples-documentation'
require_text scripts/validate-milestone-local.sh 'templates_examples_milestone'
require_text scripts/validate-docs.sh 'validate-docs.sh'
require_text .dockerignore '**'

require_text examples/child-image/Containerfile 'USER root'
require_text examples/child-image/Containerfile 'USER developer'
require_text examples/child-image/Containerfile 'WORKDIR /workspace'
require_text examples/child-image/Containerfile "curl --proto '=https'"
require_text examples/child-image/Containerfile 'sha256sum --check --strict'
if grep -Eq '^[[:space:]]*(COPY|ADD)[[:space:]]' examples/child-image/Containerfile; then
  fail 'child image example copies build-context content'
fi
# --- Node.js example contract ---
require_text examples/nodejs/Containerfile 'USER root'
require_text examples/nodejs/Containerfile 'USER developer'
require_text examples/nodejs/Containerfile 'WORKDIR /workspace'
require_text examples/nodejs/Containerfile "curl --proto '=https'"
require_text examples/nodejs/Containerfile 'sha256sum --check --strict'
require_text examples/nodejs/Containerfile 'ENTRYPOINT ["/usr/local/bin/cyclestone-entrypoint"]'
require_text examples/nodejs/Containerfile 'CMD ["/bin/bash", "-l"]'
if grep -Eq '^[[:space:]]*(COPY|ADD)[[:space:]]' examples/nodejs/Containerfile; then
  fail 'Node.js example copies build-context content'
fi
require_text examples/nodejs/versions.env 'NODE_VERSION=22.11.0'
require_text examples/nodejs/versions.env 'NODE_AMD64_SHA256='
require_text examples/nodejs/versions.env 'NODE_ARM64_SHA256='

# --- .NET example contract ---
require_text examples/dotnet/Containerfile 'USER root'
require_text examples/dotnet/Containerfile 'USER developer'
require_text examples/dotnet/Containerfile 'WORKDIR /workspace'
require_text examples/dotnet/Containerfile "curl --proto '=https'"
require_text examples/dotnet/Containerfile 'sha512sum --check --strict'
require_text examples/dotnet/Containerfile 'ENTRYPOINT ["/usr/local/bin/cyclestone-entrypoint"]'
require_text examples/dotnet/Containerfile 'CMD ["/bin/bash", "-l"]'
require_text examples/dotnet/Containerfile 'DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1'
if grep -Eq '^[[:space:]]*(COPY|ADD)[[:space:]]' examples/dotnet/Containerfile; then
  fail '.NET example copies build-context content'
fi
require_text examples/dotnet/versions.env 'DOTNET_VERSION=8.0.423'
require_text examples/dotnet/versions.env 'DOTNET_AMD64_SHA512='
require_text examples/dotnet/versions.env 'DOTNET_ARM64_SHA512='

# --- Codex provider example contract ---
jq -e '.version==1 and .providers.codex.enabled==true and .providers.codex.mode=="read-write"'   examples/codex/providers.json >/dev/null || fail 'Codex example provider request is invalid'
require_text examples/codex/.devcontainer/devcontainer.json '"remoteUser": "developer"'
require_text examples/codex/.devcontainer/devcontainer.json '"updateRemoteUserUID": false'
require_text examples/codex/.devcontainer/devcontainer.json 'keep-id:uid=1000,gid=1000'
require_text examples/codex/.devcontainer/devcontainer.json 'no-new-privileges'

# --- Ollama provider example contract ---
jq -e '.version==1 and .providers.ollama.enabled==true and .providers.ollama.mode=="host-service"'   examples/ollama/providers.json >/dev/null || fail 'Ollama example provider request is invalid'
require_text examples/ollama/.devcontainer/devcontainer.json '"remoteUser": "developer"'
require_text examples/ollama/.devcontainer/devcontainer.json '"updateRemoteUserUID": false'
require_text examples/ollama/.devcontainer/devcontainer.json 'keep-id:uid=1000,gid=1000'
require_text examples/ollama/.devcontainer/devcontainer.json 'no-new-privileges'

# --- Agy provider example contract ---
jq -e '.version==1 and .providers.agy.enabled==true and .providers.agy.mode=="environment"'   examples/agy/providers.json >/dev/null || fail 'Agy example provider request is invalid'
require_text examples/agy/.devcontainer/devcontainer.json '"remoteUser": "developer"'
require_text examples/agy/.devcontainer/devcontainer.json '"updateRemoteUserUID": false'
require_text examples/agy/.devcontainer/devcontainer.json 'keep-id:uid=1000,gid=1000'
require_text examples/agy/.devcontainer/devcontainer.json 'no-new-privileges'

# --- Provider examples must not contain credential values ---
if grep -R -n -E '(api[_-]?key|token|secret|password|auth\.json|BEGIN.*PRIVATE KEY)'   examples/codex/providers.json examples/ollama/providers.json examples/agy/providers.json   examples/codex/.devcontainer/devcontainer.json examples/ollama/.devcontainer/devcontainer.json examples/agy/.devcontainer/devcontainer.json; then
  fail 'provider example contains a credential or secret pattern'
fi

require_text scripts/build-child-image.sh 'ghcr.io/patrick-folster/cyclestone-dev-container-base@sha256:'
require_text scripts/validate-base-native.sh 'tests/child-image-inheritance.sh'
require_text docs/child-images.md '/workspace'
require_text docs/child-images.md 'ENTRYPOINT'
require_text docs/child-images.md 'SHA-256'

template_config=templates/project-devcontainer/.devcontainer/devcontainer.json
template_containerfile=templates/project-devcontainer/.devcontainer/Containerfile
template_hook=templates/project-devcontainer/.devcontainer/lifecycle.sh
jq -e '
  .build.dockerfile == "Containerfile"
  and .build.context == ".."
  and .build.args.BASE_IMAGE_REF == "${localEnv:CYCLESTONE_BASE_IMAGE_REF}"
  and .remoteUser == "developer"
  and .containerUser == "developer"
  and .updateRemoteUserUID == false
  and .workspaceMount == "source=${localWorkspaceFolder},target=/workspace,type=bind"
  and .workspaceFolder == "/workspace"
  and .postCreateCommand == "/workspace/.devcontainer/lifecycle.sh postCreate"
  and .privileged == false
  and .overrideCommand == true
  and .mounts == ["source=cyclestone-project-go-cache,target=/home/developer/.cache/go-build,type=volume"]
  and (.runArgs | index("--userns=keep-id:uid=1000,gid=1000") != null)
  and (.runArgs | index("--security-opt=no-new-privileges") != null)
  and .customizations == {}
' "$template_config" >/dev/null || fail 'project Dev Container template contract is invalid'
require_text "$template_containerfile" 'sha256sum --check --strict'
require_text "$template_containerfile" 'USER developer'
require_text "$template_containerfile" 'WORKDIR /workspace'
require_text "$template_containerfile" 'ENTRYPOINT ["/usr/local/bin/cyclestone-entrypoint"]'
require_text "$template_hook" 'test "$(id -un)" = developer'
require_text "$template_hook" 'phase=postCreate user=developer workspace=/workspace cache=ready'
if grep -Eq '^[[:space:]]*(COPY|ADD)[[:space:]]' "$template_containerfile"; then
  fail 'project child image copies repository content into an image layer'
fi
if grep -R -n -E '(docker\.sock|podman\.sock|/\.aws|/\.azure|\.config/gcloud|\.kube|\.ssh|provider[_-](mount|cli)|generated[_-]integration)' \
  templates/project-devcontainer docs/devcontainers.md; then
  fail 'project Dev Container includes a provider, credential, socket, or generated-integration path'
fi
if grep -Eq '(env([[:space:]]|$)|printenv|set([[:space:]]+-x|[[:space:]]*$)|sudo|apt(-get)?|chown|chmod|\.aws|\.ssh|token|secret|credential)' "$template_hook"; then
  fail 'project lifecycle hook may enumerate or consume credentials, install packages, escalate, or repair ownership'
fi
require_text docs/devcontainers.md 'Review before consent'
require_text docs/devcontainers.md 'devcontainer --docker-path podman up'
require_text docs/devcontainers.md 'podman volume rm cyclestone-project-go-cache'
require_text docs/devcontainers.md 'reserved for the later deterministic'
require_text tests/devcontainer-podman.sh 'updateRemoteUserUID=true up_status='
require_text tests/devcontainer-podman.sh '--remove-existing-container --build-no-cache'
require_text tests/fixtures/devcontainer-podman/runtime.sh 'git -C /workspace ls-files --error-unmatch'
require_text scripts/build-base-podman.sh '--iidfile'
require_text scripts/validate-milestone-local.sh 'both local rootless-Podman identity cases qualify the milestone cycle'
require_text scripts/validate-milestone-local.sh 'source_digest=$source_digest'
if grep -F '| tee' scripts/validate-milestone-local.sh >/dev/null; then
  fail 'local milestone gate may not mask a failed command behind tee'
fi

require_text docs/architecture/cyclestone-acquisition.md 'latest v-tag'
require_text docs/architecture/cyclestone-acquisition.md 'checksums.txt'
require_text docs/architecture/cyclestone-acquisition.md 'Publisher-trusted'
require_text docs/architecture/cyclestone-acquisition.md 'INSTALL_TOOLS'
require_text docs/architecture/cyclestone-acquisition.md 'must fail the build before installation'
require_text docs/base-image.md "\`load\` defaults to \`linux/amd64\`"
require_text .github/workflows/base-image-validation.yml 'ubuntu-24.04-arm'
require_text .github/workflows/base-image-validation.yml 'dockerd-rootless-setuptool.sh install --force'
require_text .github/workflows/base-image-validation.yml "@devcontainers/cli@\$DEVCONTAINER_VERSION"
require_text tests/rootless-bind-mount.sh 'setfacl -m'
require_text tests/fixtures/devcontainer/.devcontainer/devcontainer.json '"remoteUser": "developer"'
require_text tests/fixtures/devcontainer/.devcontainer/devcontainer.json '"containerUser": "developer"'
require_text tests/fixtures/devcontainer/.devcontainer/devcontainer.json '"updateRemoteUserUID": true'
require_text tests/fixtures/devcontainer/.devcontainer/devcontainer.json '"privileged": false'
require_text tests/devcontainer.sh 'updateRemoteUserUID cannot be combined with Podman keep-id'
require_text tests/rootless-podman.sh '--userns=keep-id:uid=1000,gid=1000'
require_text tests/rootless-podman.sh '--group-add keep-groups'
require_text tests/fixtures/workspace-identity/assertions.sh "safe.directory"
require_text .github/workflows/base-image-validation.yml 'fixture_uid=2001'
require_text .github/workflows/base-image-validation.yml 'fixture_gid=2002'
require_text .github/workflows/release-image.yml "github.repository == 'patrick-folster/cyclestone-dev-containers'"
require_text .github/workflows/release-image.yml 'aquasecurity/trivy-action@57a97c7e7821a5776cebc9bb87c984fa69cba8f1'
require_text .github/workflows/release-image.yml 'actions/attest-build-provenance@1c608d11d69870c2092266b3f9a6f3abbf17002c'
require_text .github/workflows/release-image.yml 'contents: read'
require_text .github/workflows/release-image.yml 'packages: write'
require_text .github/workflows/release-image.yml 'id-token: write'

if grep -R -n -E '(chown|chmod)[[:space:]]+(-[[:alpha:]]*R|--recursive)' \
  images/base/entrypoint.sh tests/devcontainer.sh tests/rootless-podman.sh; then
  fail 'supported startup or identity workflow contains recursive ownership repair'
fi

for method in V1 V2 V3 V4 V5 V6 V7 V8; do
  require_text docs/architecture/compatibility.md "| $method |"
done

supported_rows=$(grep -c '| Supported | V' docs/architecture/compatibility.md || true)
test "$supported_rows" -eq 6 || fail "expected 6 supported rows with validation; found $supported_rows"
require_text docs/architecture/compatibility.md 'omitted combinations are **unsupported**'
require_text docs/architecture/compatibility.md 'Empty toolset (default)'

for actor in 'Host user' 'Untrusted repository' 'Cyclestone' 'This repository' 'Built image' 'Running container' 'Provider CLIs' 'Local services' 'Registries/download sources' 'CI' 'Future teams/users'; do
  require_text docs/architecture/threat-model.md "$actor"
done

for category in 'Operating system' 'Tool updates' 'Cyclestone updates' 'Provider definitions' 'Dev Container behavior' 'Public contracts' 'Security fixes'; do
  require_text docs/architecture/versioning.md "$category"
done

require_text docs/architecture/validation-checklist.md '**PASS — static architecture and implementation checks pass.**'
if grep -R -n -E '\b(TBD|TO[ -]?DO|FIXME)\b' README.md images scripts providers templates tests/README.md examples .github/workflows schemas docs .cyclestone/DECISIONS.md; then
  fail 'unresolved placeholder found in contract files'
fi

echo 'PASS: repository and image contracts are internally consistent'

# --- MVP qualification: delivery roadmap and deferred evidence ---
require_text docs/architecture/delivery-roadmap.md 'ms-pf-0001'
require_text docs/architecture/delivery-roadmap.md 'ms-pf-0015'
require_text docs/architecture/delivery-roadmap.md 'Out of scope'
require_text docs/architecture/delivery-roadmap.md 'Follow-up release candidates'
require_text docs/architecture/delivery-roadmap.md '| C1 |'
require_text docs/architecture/delivery-roadmap.md '| C10 |'
require_text docs/architecture/delivery-roadmap.md 'c65f1f91eb356c1dc9ef0377db50cc6080be7567'
require_text docs/architecture/compatibility.md 'Deferred native evidence'
require_text docs/architecture/compatibility.md '2026-09-30'
require_text docs/architecture/compatibility.md '@patrick-folster'
require_text docs/architecture/validation-checklist.md 'DEFERRED'
