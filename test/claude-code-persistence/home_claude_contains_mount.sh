#!/bin/bash

# ~/.claude is on the root filesystem but contains a separate mount
# (standing in for a host directory bind-mounted at ~/.claude/commands).
# Moving ~/.claude into the volume would copy the mounted files and then
# delete them from their source, so the feature must leave all of it alone.

set -e

source dev-container-features-test-lib

check "~/.claude is still a directory, not a symlink" bash -c 'test -d "${HOME}/.claude" && test ! -L "${HOME}/.claude"'
check "mounted contents are kept" test "$(cat "${HOME}/.claude/commands/sentinel")" = "keep"
check "sibling contents are kept" test "$(cat "${HOME}/.claude/other")" = "keep"

reportResults
