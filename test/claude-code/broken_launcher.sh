#!/bin/bash
set -e

source dev-container-features-test-lib

# The Dockerfile leaves ~/.local/bin/claude pointing at versions/0.0.0, which
# exits with an error. install.sh has to remove both before running the
# installer.
check "the broken binary is gone" test ! -e "${HOME}/.local/share/claude/versions/0.0.0"
check "the launcher points to an existing binary" test -e "${HOME}/.local/bin/claude"
check "claude runs" claude --version
check "/usr/local/bin/claude links to the launcher" test "$(readlink /usr/local/bin/claude)" = "${HOME}/.local/bin/claude"

reportResults
