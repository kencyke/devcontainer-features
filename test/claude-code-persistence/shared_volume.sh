#!/bin/bash

# devcontainer.json mounts the shared volume at the feature's mount target.
# The later mount for the same target wins, so it replaces the per-container
# volume instead of being mounted next to it.

set -e

source dev-container-features-test-lib

VOLUME=/mnt/claude-code-persistence

check "the shared volume is mounted" awk -v p="${VOLUME}" '$5 == p && $4 ~ /\/volumes\/claude-code-persistence-test-shared\/_data$/ { found = 1 } END { exit !found }' /proc/self/mountinfo
check "no other volume is mounted at or below it" test "$(awk -v p="${VOLUME}" '$5 == p || index($5, p "/") == 1' /proc/self/mountinfo | wc -l)" -eq 1
check "~/.claude links to the volume" test "$(readlink "${HOME}/.claude")" = "${VOLUME}"
check "volume is owned by the current user" test "$(stat -c '%u:%g' "${VOLUME}")" = "$(id -u):$(id -g)"

reportResults
