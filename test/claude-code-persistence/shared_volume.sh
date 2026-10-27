#!/bin/bash

# devcontainer.json mounts the shared volume at the feature's mount target.
# The later mount for the same target wins, so it replaces the per-container
# volume instead of being mounted next to it.

set -e

source dev-container-features-test-lib

VOLUME=/mnt/claude-code-persistence

check "running as UID 1000" test "$(id -u)" -eq 1000
check "CLAUDE_CONFIG_DIR points to the volume" test "${CLAUDE_CONFIG_DIR}" = "${VOLUME}"
check "the shared volume is mounted" awk -v p="${VOLUME}" '$5 == p && $4 ~ /\/volumes\/claude-code-persistence-test-shared\/_data$/ { found = 1 } END { exit !found }' /proc/self/mountinfo
check "no other volume is mounted at or below it" test "$(awk -v p="${VOLUME}" '$5 == p || index($5, p "/") == 1' /proc/self/mountinfo | wc -l)" -eq 1
check "~/.claude links to the volume" test "$(readlink "${HOME}/.claude")" = "${VOLUME}"
check "~/.claude.json links into the volume" test "$(readlink "${HOME}/.claude.json")" = "${VOLUME}/.claude.json"
check "volume is owned by the current user" test "$(stat -c '%u:%g' "${VOLUME}")" = "$(id -u):$(id -g)"
check "volume is private to the current user" test "$(stat -c '%a' "${VOLUME}")" = "700"
check "writes through ~/.claude land in the volume" bash -c '
    echo ok > "${HOME}/.claude/.persistence-test" &&
    test -f /mnt/claude-code-persistence/.persistence-test &&
    rm -f "${HOME}/.claude/.persistence-test"
'

reportResults
