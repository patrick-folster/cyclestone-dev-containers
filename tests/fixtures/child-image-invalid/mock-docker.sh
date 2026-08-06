#!/bin/sh
set -eu

case "$1:$2" in
  image:inspect)
    case "$4" in
      '{{.Id}}')
        test -n "${MOCK_IMAGE_ID:-}" || exit 1
        echo "$MOCK_IMAGE_ID"
        ;;
      '{{.Config.User}}') test "${MOCK_CASE:-}" = root && echo root || echo developer ;;
      '{{.Config.WorkingDir}}') test "${MOCK_CASE:-}" = workdir && echo /tmp || echo /workspace ;;
      '{{json .Config.Entrypoint}}') echo '["/usr/local/bin/cyclestone-entrypoint"]' ;;
      '{{json .Config.Cmd}}') echo '["/bin/bash","-l"]' ;;
      '{{ index .Config.Labels "io.cyclestone.tools" }}')
        test "${MOCK_CASE:-}" = cyclestone && echo cyclestone || echo ''
        ;;
      *) exit 2 ;;
    esac
    ;;
  buildx:build)
    test -n "${MOCK_DOCKER_LOG:-}" || exit 2
    printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"
    ;;
  run:*)
    command_text=$*
    # The case pattern intentionally matches a literal command passed to mocked Docker.
    # shellcheck disable=SC2016
    case "${MOCK_CASE:-}:$command_text" in
      home:*'test "$HOME" = /home/developer'*) exit 1 ;;
      cyclestone:*'command -v cyclestone'*) exit 1 ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 2 ;;
esac
