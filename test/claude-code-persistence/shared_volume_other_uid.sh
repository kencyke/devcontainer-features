#!/bin/bash
set -e

source dev-container-features-test-lib

VOLUME=/mnt/claude-code-persistence

# initializeCommand fills the volume from the host with entries owned by
# UID 1000 before the container is created, so every run has to take them
# over. updateRemoteUserUID is false, because otherwise features test maps
# octocat to the host UID, which may be 1000.
check "octocat is not UID 1000" test "$(id -u)" -ne 1000
check "volume ownership was taken over by octocat" test "$(stat -c '%u:%g' "${VOLUME}")" = "$(id -u):$(id -g)"
check "entries from initializeCommand are present" test -f "${VOLUME}/.persistence-test-dir/marker"
check "nested entries were taken over" test "$(stat -c '%u:%g' "${VOLUME}/.persistence-test-dir/marker")" = "$(id -u):$(id -g)"
# These two catch a chown that follows symlinks. Current GNU coreutils and
# uutils 0.10.0 do not follow them under -R even without -h, so they do not
# show that -h itself is needed.
check "symlinks were taken over" test "$(stat -c '%u:%g' "${VOLUME}/.persistence-test-link")" = "$(id -u):$(id -g)"
check "symlink targets were not changed" test "$(stat -c '%u:%g' /etc/debian_version)" = "0:0"
check "~/.claude is in octocat's home" test "$(readlink /home/octocat/.claude)" = "${VOLUME}"

reportResults
