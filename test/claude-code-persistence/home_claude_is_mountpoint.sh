#!/bin/bash

# ~/.claude is a separate mount (standing in for the host's ~/.claude
# bind-mounted by the user). The feature must leave it and its contents alone.

set -e

source dev-container-features-test-lib

check "~/.claude is still a directory, not a symlink" bash -c 'test -d "${HOME}/.claude" && test ! -L "${HOME}/.claude"'
check "~/.claude is still a mount point" awk -v p="${HOME}/.claude" '$5 == p { found = 1 } END { exit !found }' /proc/self/mountinfo
check "contents of ~/.claude are kept" test "$(cat "${HOME}/.claude/sentinel")" = "keep"
check "contents of ~/.claude are not moved into the volume" test ! -e /mnt/claude-code-persistence/sentinel
check "CLAUDE_CONFIG_DIR still points to the volume" test "${CLAUDE_CONFIG_DIR}" = /mnt/claude-code-persistence

reportResults
