#!/bin/bash
set -e

source dev-container-features-test-lib

# Pins the stable release current when this test was written, to cover the
# pinned-version path (exact version match and strict integrity check).
# If the release or its manifest is ever withdrawn, move it to the current
# stable version.

check "claude reports the pinned version" bash -c 'claude --version | grep -q "^2\.1\.308\b"'
check "/usr/local/bin/claude links to the launcher" test "$(readlink /usr/local/bin/claude)" = "${HOME}/.local/bin/claude"

reportResults
