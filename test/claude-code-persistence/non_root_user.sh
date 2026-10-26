#!/bin/bash
set -e

source dev-container-features-test-lib

VOLUME=/mnt/claude-code-persistence

check "running as octocat" test "$(id -un)" = "octocat"
check "~/.claude is in octocat's home" test "$(readlink /home/octocat/.claude)" = "${VOLUME}"
check "~/.claude.json is in octocat's home" test "$(readlink /home/octocat/.claude.json)" = "${VOLUME}/.claude.json"
check "volume is owned by octocat" test "$(stat -c '%U:%G' "${VOLUME}")" = "octocat:$(id -gn)"
check "octocat can write to the volume" bash -c '
    echo ok > /home/octocat/.claude/.persistence-test &&
    rm -f /home/octocat/.claude/.persistence-test
'

reportResults
