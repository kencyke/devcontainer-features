#!/bin/bash

# The image has ~/.claude and ~/.claude.json, and the volume (prefilled by
# initializeCommand) already has a settings.json. Everything else from the
# image is moved into the volume, the image's settings.json is discarded, and
# both paths become symlinks.

set -e

source dev-container-features-test-lib

VOLUME=/mnt/claude-code-persistence

check "~/.claude links to the volume" test "$(readlink "${HOME}/.claude")" = "${VOLUME}"
check "~/.claude.json links into the volume" test "$(readlink "${HOME}/.claude.json")" = "${VOLUME}/.claude.json"
check "entries from the image were moved" test "$(cat "${VOLUME}/history.jsonl")" = "image"
check "~/.claude.json from the image seeded the volume" test "$(cat "${VOLUME}/.claude.json")" = "image"
check "the volume's settings.json wins" test "$(cat "${VOLUME}/settings.json")" = "volume"
check "moved entries are owned by the current user" test "$(stat -c '%u:%g' "${VOLUME}/history.jsonl")" = "$(id -u):$(id -g)"

reportResults
