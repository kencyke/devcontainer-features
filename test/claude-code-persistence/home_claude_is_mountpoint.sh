#!/bin/bash

# ~/.claude is a separate mount (standing in for the host's ~/.claude
# bind-mounted by the user). The feature must leave it and its contents alone.

set -e

source dev-container-features-test-lib

check "~/.claude is still a directory, not a symlink" bash -c 'test -d "${HOME}/.claude" && test ! -L "${HOME}/.claude"'
check "contents of ~/.claude are kept" test "$(cat "${HOME}/.claude/sentinel")" = "keep"

reportResults
