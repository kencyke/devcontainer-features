#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="${CLAUDE_BIND_MOUNT_SOURCE_DIR:-/var/tmp/claude-bind-mount/host-home/.claude}"
TARGET_DIR="${CLAUDE_BIND_MOUNT_TARGET_DIR:-${HOME}/.claude}"

has_entries() {
    local dir_path="$1"
    [[ -d "${dir_path}" ]] && find "${dir_path}" -mindepth 1 -print -quit | grep -q .
}

if ! has_entries "${SOURCE_DIR}"; then
    echo "claude-bind-mount: host ~/.claude is unavailable or empty; skipping sync"
    exit 0
fi

if [[ -e "${TARGET_DIR}" ]] && ! [[ -d "${TARGET_DIR}" ]]; then
    echo "claude-bind-mount: ${TARGET_DIR} exists and is not a directory; skipping sync"
    exit 0
fi

if has_entries "${TARGET_DIR}"; then
    echo "claude-bind-mount: ${TARGET_DIR} already contains data; skipping sync"
    exit 0
fi

mkdir -p "${TARGET_DIR}"
cp -r --no-preserve=ownership "${SOURCE_DIR}/." "${TARGET_DIR}/"
echo "claude-bind-mount: copied host ~/.claude into ${TARGET_DIR}"