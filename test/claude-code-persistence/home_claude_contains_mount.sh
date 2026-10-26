#!/bin/bash

# ~/.claude is on the root filesystem but contains a separate mount
# (standing in for a host directory bind-mounted at ~/.claude/commands).
# Moving ~/.claude into the volume would copy the mounted files and then
# delete them from their source, so the feature must leave all of it alone.

set -e

source dev-container-features-test-lib

check "~/.claude is still a directory, not a symlink" bash -c 'test -d "${HOME}/.claude" && test ! -L "${HOME}/.claude"'
check "~/.claude/commands is still a mount point" awk -v p="${HOME}/.claude/commands" '$5 == p { found = 1 } END { exit !found }' /proc/self/mountinfo
check "mounted contents are kept" test "$(cat "${HOME}/.claude/commands/sentinel")" = "keep"
check "sibling contents are kept" test "$(cat "${HOME}/.claude/other")" = "keep"
check "nothing is moved into the volume" bash -c 'test ! -e /mnt/claude-code-persistence/commands && test ! -e /mnt/claude-code-persistence/other'
check "CLAUDE_CONFIG_DIR still points to the volume" test "${CLAUDE_CONFIG_DIR}" = /mnt/claude-code-persistence

reportResults
