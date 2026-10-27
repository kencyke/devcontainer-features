#!/bin/bash
set -eo pipefail

VOLUME_DIR="/mnt/claude-code-persistence"
INSTALL_DIR="/usr/local/share/claude-code-persistence"

echo "Configuring Claude Code persistence..."

# Determine remote user
REMOTE_USER="${_REMOTE_USER:-"automatic"}"
if [ "${REMOTE_USER}" = "auto" ] || [ "${REMOTE_USER}" = "automatic" ]; then
    REMOTE_USER="$(id -un 1000 2>/dev/null || echo "vscode")"
fi

# Validate that the resolved user actually exists on the system.
if ! id "${REMOTE_USER}" >/dev/null 2>&1; then
    echo "WARNING: User '${REMOTE_USER}' does not exist." >&2
    if [ -n "${_CONTAINER_USER:-}" ] && id "${_CONTAINER_USER}" >/dev/null 2>&1; then
        echo "WARNING: Falling back to _CONTAINER_USER '${_CONTAINER_USER}'." >&2
        REMOTE_USER="${_CONTAINER_USER}"
    else
        echo "ERROR: No valid user found. Tried '${REMOTE_USER}'${_CONTAINER_USER:+ and '${_CONTAINER_USER}'}." >&2
        echo "ERROR: Ensure the base image has a non-root user, or set remoteUser in devcontainer.json." >&2
        exit 1
    fi
fi

# Create the mount point owned by the remote user. Docker copies the
# ownership and mode of an image directory into a named volume the first time
# that (empty) volume is mounted there, so new volumes start out writable by
# the remote user without needing sudo at runtime. This applies equally to the
# per-container volume and to a shared volume that devcontainer.json mounts
# at the same target.
# The group is spelled out because uutils chown (default on newer Ubuntu)
# does not expand "user:" to the login group like GNU chown does.
mkdir -p "${VOLUME_DIR}"
chown "${REMOTE_USER}:$(id -gn "${REMOTE_USER}")" "${VOLUME_DIR}"
chmod 700 "${VOLUME_DIR}"

mkdir -p "${INSTALL_DIR}"
cp "$(dirname "$0")/oncreate.sh" "${INSTALL_DIR}/oncreate.sh"
chmod 755 "${INSTALL_DIR}/oncreate.sh"

echo "Claude Code persistence configured (user: ${REMOTE_USER})"
