#!/bin/bash
set -e

source dev-container-features-test-lib

VOLUME=/mnt/claude-code-persistence

check "claude runs" claude --version
check "~/.claude links to the volume" test "$(readlink "${HOME}/.claude")" = "${VOLUME}"
check "~/.claude.json links into the volume" test "$(readlink "${HOME}/.claude.json")" = "${VOLUME}/.claude.json"

reportResults
