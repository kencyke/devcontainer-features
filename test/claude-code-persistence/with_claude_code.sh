#!/bin/bash
set -e

source dev-container-features-test-lib

check "claude runs" claude --version
check "~/.claude links to the volume" test "$(readlink "${HOME}/.claude")" = /mnt/claude-code-persistence

reportResults
