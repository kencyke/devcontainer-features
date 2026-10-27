#!/bin/bash
# Runs as the remote user once per container creation (onCreateCommand).
# Problems are reported as warnings instead of failing, so that the
# user-provided lifecycle commands that follow still run.
set -uo pipefail
shopt -s dotglob nullglob

VOLUME_DIR="/mnt/claude-code-persistence"

warn() {
    echo "claude-code-persistence: WARNING: $*" >&2
}

# Awk prelude for reading /proc/self/mountinfo: sets p to the path in
# MOUNT_PATH and m to each line's mount point, decoding the octal escapes the
# kernel writes for space, tab, newline and backslash. The path is passed
# through the environment because awk -v would interpret its backslashes.
MOUNTINFO_AWK='
    function unescape(s,   out, i) {
        out = ""
        while ((i = index(s, "\\")) > 0) {
            out = out substr(s, 1, i - 1) sprintf("%c", substr(s, i + 1, 1) * 64 + substr(s, i + 2, 1) * 8 + substr(s, i + 3, 1))
            s = substr(s, i + 4)
        }
        return out s
    }
    BEGIN { p = ENVIRON["MOUNT_PATH"] }
    { m = unescape($5) }
'

# Prints the mount point that contains the given path.
covering_mount() {
    MOUNT_PATH="$1" awk "${MOUNTINFO_AWK}"'
        m == "/" || p == m || index(p, m "/") == 1 { if (length(m) > length(best)) best = m }
        END { print best }
    ' /proc/self/mountinfo
}

# Prints the mount points strictly below the given path, one per line.
nested_mounts() {
    MOUNT_PATH="$1" awk "${MOUNTINFO_AWK}"'
        index(m, p "/") == 1 { print m }
    ' /proc/self/mountinfo
}

# The home directory normally lives on the container's root filesystem. If the
# path is on any other mount (e.g. the host's ~/.claude or the whole home
# directory bind-mounted from the host), it must not be moved or replaced.
on_root_filesystem() {
    [ "$(covering_mount "$1")" = "/" ]
}

if [ "${CLAUDE_CONFIG_DIR:-}" != "${VOLUME_DIR}" ]; then
    warn "CLAUDE_CONFIG_DIR is '${CLAUDE_CONFIG_DIR:-}', not '${VOLUME_DIR}'. Skipping setup."
    exit 0
fi

# Without the mount, nothing would persist. With a mount below it, the chown
# and the move further down could reach files outside the volume (e.g. a host
# directory the user bind-mounted there).
if [ ! -d "${VOLUME_DIR}" ] || [ "$(covering_mount "${VOLUME_DIR}")" != "${VOLUME_DIR}" ] || [ -n "$(nested_mounts "${VOLUME_DIR}")" ]; then
    warn "${VOLUME_DIR} is not a mount point, or contains other mounts. Skipping setup."
    exit 0
fi

# --- Volume ownership --------------------------------------------------------
# New volumes inherit the ownership set at build time. Fix it up when the
# remote user's UID changed after the build (updateRemoteUserUID) or the
# shared volume was created by a container running as a different UID.
TARGET_UID="$(id -u)"
TARGET_GID="$(id -g)"
if [ "$(stat -c '%u:%g' "${VOLUME_DIR}")" != "${TARGET_UID}:${TARGET_GID}" ]; then
    AS_ROOT="sudo -n"
    [ "${TARGET_UID}" -eq 0 ] && AS_ROOT=""
    # -h: change symlinks in the volume themselves, never the files they point
    # to, regardless of the chown implementation (GNU or uutils)
    if ! ${AS_ROOT} chown -R -h "${TARGET_UID}:${TARGET_GID}" "${VOLUME_DIR}"; then
        warn "Could not take over ${VOLUME_DIR}. Claude Code will not be able to read or write its state until you run as root: chown -R -h ${TARGET_UID}:${TARGET_GID} ${VOLUME_DIR}"
        exit 0
    fi
fi
chmod 700 "${VOLUME_DIR}" 2>/dev/null || true

# Paths are compared against /proc/self/mountinfo, which lists canonical
# paths, so resolve symlinks and drop duplicate or trailing slashes first.
HOME="$(realpath -m "${HOME}")"

# --- ~/.claude ---------------------------------------------------------------
# Claude Code itself follows CLAUDE_CONFIG_DIR; the symlink is for tools that
# hard-code ~/.claude. Anything created there during the image build (e.g. by
# an installer) is moved into the volume unless the volume already has an
# entry with the same name.
HOME_CLAUDE="${HOME}/.claude"
NESTED="$(nested_mounts "${HOME_CLAUDE}")"
if ! on_root_filesystem "${HOME_CLAUDE}"; then
    warn "${HOME_CLAUDE} is on a separate mount ($(covering_mount "${HOME_CLAUDE}")). Leaving it untouched; Claude Code uses ${VOLUME_DIR}."
elif [ -n "${NESTED}" ]; then
    # Moving a directory that contains a mount point would copy the mounted
    # files and then delete them from their source (e.g. the host).
    warn "${HOME_CLAUDE} contains other mounts ($(echo "${NESTED}" | tr '\n' ' ' | sed 's/ $//')). Leaving it untouched; Claude Code uses ${VOLUME_DIR}."
elif [ -d "${HOME_CLAUDE}" ] && [ ! -L "${HOME_CLAUDE}" ]; then
    migrated="true"
    moved=""
    skipped=""
    for entry in "${HOME_CLAUDE}"/*; do
        name="${entry##*/}"
        if [ -e "${VOLUME_DIR}/${name}" ] || [ -L "${VOLUME_DIR}/${name}" ]; then
            skipped="${skipped} $(printf '%q' "${name}")"
            continue
        fi
        if mv "${entry}" "${VOLUME_DIR}/${name}"; then
            moved="${moved} $(printf '%q' "${name}")"
        else
            migrated="false"
        fi
    done
    # Listed so that settings or hooks an image brings into a shared volume
    # do not go unnoticed
    if [ -n "${moved}" ]; then
        echo "claude-code-persistence: Moved from ${HOME_CLAUDE} into ${VOLUME_DIR}:${moved}"
    fi
    if [ "${migrated}" = "true" ]; then
        if [ -n "${skipped}" ]; then
            warn "Discarding from ${HOME_CLAUDE} because ${VOLUME_DIR} already has entries with the same name:${skipped}"
        fi
        rm -rf "${HOME_CLAUDE}"
    fi
    if [ -e "${HOME_CLAUDE}" ]; then
        warn "Failed to move ${HOME_CLAUDE} into ${VOLUME_DIR}. Leaving it in place."
    else
        ln -sfn "${VOLUME_DIR}" "${HOME_CLAUDE}"
    fi
elif [ -e "${HOME_CLAUDE}" ] && [ ! -L "${HOME_CLAUDE}" ]; then
    warn "${HOME_CLAUDE} exists but is not a directory. Leaving it untouched."
else
    ln -sfn "${VOLUME_DIR}" "${HOME_CLAUDE}"
fi

# --- ~/.claude.json ----------------------------------------------------------
# With CLAUDE_CONFIG_DIR set, Claude Code reads $CLAUDE_CONFIG_DIR/.claude.json.
# A file written during the image build (e.g. installMethod from
# `claude install`) seeds a volume that does not have one yet.
HOME_JSON="${HOME}/.claude.json"
if ! on_root_filesystem "${HOME_JSON}"; then
    warn "${HOME_JSON} is on a separate mount ($(covering_mount "${HOME_JSON}")). Leaving it untouched; Claude Code uses ${VOLUME_DIR}/.claude.json."
elif [ -f "${HOME_JSON}" ] && [ ! -L "${HOME_JSON}" ]; then
    if [ -e "${VOLUME_DIR}/.claude.json" ] || [ -L "${VOLUME_DIR}/.claude.json" ]; then
        warn "Discarding ${HOME_JSON} because ${VOLUME_DIR}/.claude.json already exists."
        rm -f "${HOME_JSON}"
    elif mv "${HOME_JSON}" "${VOLUME_DIR}/.claude.json"; then
        echo "claude-code-persistence: Moved ${HOME_JSON} to ${VOLUME_DIR}/.claude.json"
    else
        warn "Failed to move ${HOME_JSON} into ${VOLUME_DIR}. Leaving it in place."
    fi
    [ -e "${HOME_JSON}" ] || ln -sfn "${VOLUME_DIR}/.claude.json" "${HOME_JSON}"
elif [ -e "${HOME_JSON}" ] && [ ! -L "${HOME_JSON}" ]; then
    warn "${HOME_JSON} exists but is not a regular file. Leaving it untouched."
else
    ln -sfn "${VOLUME_DIR}/.claude.json" "${HOME_JSON}"
fi

echo "claude-code-persistence: Claude Code state is stored in ${VOLUME_DIR}"
