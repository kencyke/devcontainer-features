#!/usr/bin/env bash

set -euo pipefail

STAGED_DIR="/var/tmp/claude-bind-mount/host-home/.claude"
TARGET_DIR="${HOME}/.claude"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

echo "Checking staged host Claude directory..."
test -d "${STAGED_DIR}"
test -f "${STAGED_DIR}/host-sentinel.txt"
test "$(cat "${STAGED_DIR}/host-sentinel.txt")" = "claude-bind-mount-test"

echo "Checking first-run sync into the container home..."
test -d "${TARGET_DIR}"
test -f "${TARGET_DIR}/host-sentinel.txt"
test "$(cat "${TARGET_DIR}/host-sentinel.txt")" = "claude-bind-mount-test"

echo "Checking skip behavior when the target already contains data..."
SOURCE_OVERRIDE="${TMP_ROOT}/source"
TARGET_OVERRIDE="${TMP_ROOT}/target"
mkdir -p "${SOURCE_OVERRIDE}" "${TARGET_OVERRIDE}"
printf 'from-source\n' > "${SOURCE_OVERRIDE}/source-only.txt"
printf 'keep-me\n' > "${TARGET_OVERRIDE}/existing.txt"

CLAUDE_BIND_MOUNT_SOURCE_DIR="${SOURCE_OVERRIDE}" \
CLAUDE_BIND_MOUNT_TARGET_DIR="${TARGET_OVERRIDE}" \
    /usr/local/share/claude-bind-mount/sync.sh

test -f "${TARGET_OVERRIDE}/existing.txt"
test ! -e "${TARGET_OVERRIDE}/source-only.txt"