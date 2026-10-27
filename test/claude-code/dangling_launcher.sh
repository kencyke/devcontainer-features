#!/bin/bash
set -e

source dev-container-features-test-lib

# The Dockerfile leaves ~/.local/bin/claude as a dangling symlink, which
# install.sh has to remove before running the installer.
check "the launcher points to an existing binary" test -e "${HOME}/.local/bin/claude"
check "claude runs" claude --version
check "/usr/local/bin/claude links to the launcher" test "$(readlink /usr/local/bin/claude)" = "${HOME}/.local/bin/claude"

reportResults
