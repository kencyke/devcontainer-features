#!/bin/bash
set -eo pipefail

get_installed_version() {
    [ -x "${CLAUDE_BIN}" ] || return 0
    # Run as the remote user, as the upstream installer itself runs the
    # downloaded binary: running it as root would grant it more than the
    # installer ever does. Not a login shell, so a broken ~/.profile cannot
    # make a working binary look unusable. The launcher has not been verified
    # yet, so a timeout keeps one that blocks from hanging the build.
    # A binary that exits non-zero counts as not installed, whatever it
    # printed: an error message such as "requires glibc 2.28.0" must not
    # pass for a version.
    giv_output="$(timeout 30 su -s /bin/sh "${REMOTE_USER}" -c '"$0" --version' "${CLAUDE_BIN}" 2>/dev/null)" || return 0
    # A line that starts with a semver wins, wherever it is in the output,
    # so a notice printed first cannot hide the version. Otherwise the
    # first semver anywhere is taken, so that output like
    # "Claude Code 2.2.0" still parses if the format ever changes.
    printf '%s\n' "${giv_output}" | awk '
        match($0, /^[0-9]+\.[0-9]+\.[0-9]+/) { print substr($0, RSTART, RLENGTH); found = 1; exit }
        any == "" && match($0, /[0-9]+\.[0-9]+\.[0-9]+/) { any = substr($0, RSTART, RLENGTH) }
        END { if (!found && any != "") print any }
    '
}

# Remove the claude launcher, the binary it points to if that is inside the
# installer's versions directory, and the /usr/local/bin link if it points to
# the launcher. Anything else they point to is left alone. The home directory
# is cleaned up as the remote user, so a symlink planted there cannot make
# root delete a file the user could not delete anyway. Returns 1 if anything
# in the home directory could not be removed.
remove_claude_bin() {
    rcb_rc=0
    su -s /bin/sh "${REMOTE_USER}" -c '
        rc=0
        target="$(readlink -f "$0" 2>/dev/null)" || target=""
        # Canonicalized like target, so that a trailing slash or a symlink in
        # REMOTE_USER_HOME does not prevent the match
        versions_dir="$(readlink -f "$1" 2>/dev/null)" || versions_dir=""
        if [ -n "${versions_dir}" ]; then
            case "${target}" in
                "${versions_dir}/"?*) rm -f "${target}" || rc=1 ;;
            esac
        fi
        rm -f "$0" || rc=1
        exit "${rc}"
    ' "${CLAUDE_BIN}" "${REMOTE_USER_HOME}/.local/share/claude/versions" || {
        echo "WARNING: Could not remove ${CLAUDE_BIN} or its binary as ${REMOTE_USER}" >&2
        rcb_rc=1
    }
    # Canonicalized on both sides, so a link written with a differently
    # spelled path (a trailing slash in the home directory, say) is still
    # recognized. readlink -f resolves the parent directories even after the
    # launcher itself has been removed.
    rcb_link_target="$(readlink -f /usr/local/bin/claude 2>/dev/null)" || rcb_link_target=""
    rcb_bin_target="$(readlink -f "${CLAUDE_BIN}" 2>/dev/null)" || rcb_bin_target=""
    if [ -L /usr/local/bin/claude ] && [ -n "${rcb_bin_target}" ] && [ "${rcb_link_target}" = "${rcb_bin_target}" ]; then
        rm -f /usr/local/bin/claude
    fi
    return "${rcb_rc}"
}

# Removes the launcher after a failed check and says whether that worked.
# The caller prints the reason first and exits afterwards.
discard_claude_bin() {
    if remove_claude_bin; then
        echo "ERROR: Removed ${CLAUDE_BIN}. Please retry installation." >&2
    else
        echo "ERROR: ${CLAUDE_BIN} could not be fully removed. Do not use it." >&2
    fi
}

# Verify binary integrity using SHA256 checksum from release manifest.
# See: https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing
# Returns: 0 = verified (or skipped when not strict), 1 = checksum mismatch
# (untrusted), 2 = verification impossible
# The version is never empty: callers exit before this when the binary
# could not report one.
verify_binary_integrity() {
    verify_claude_bin="$1"
    verify_version="$2"
    verify_strict="${3:-false}"  # "true" for specific-version installs

    case "$(uname -m)" in
        x86_64)  verify_arch="x64" ;;
        aarch64) verify_arch="arm64" ;;
        *)
            if [ "${verify_strict}" = "true" ]; then
                echo "ERROR: Unknown architecture $(uname -m), cannot perform integrity check" >&2
                return 2
            fi
            echo "WARNING: Unknown architecture $(uname -m), skipping integrity check" >&2
            return 0
            ;;
    esac

    verify_platform="linux-${verify_arch}"

    verify_manifest_url="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${verify_version}/manifest.json"
    verify_manifest="$(curl -fsSL "${verify_manifest_url}" 2>/dev/null)" || {
        if [ "${verify_strict}" = "true" ]; then
            echo "ERROR: Could not download release manifest for v${verify_version}" >&2
            return 2
        fi
        echo "WARNING: Could not download release manifest for v${verify_version}, skipping integrity check" >&2
        return 0
    }

    verify_expected_checksum="$(printf '%s' "${verify_manifest}" | grep -A2 "\"${verify_platform}\"" | grep '"checksum"' | sed 's/.*"checksum"[[:space:]]*:[[:space:]]*"\([a-f0-9]*\)".*/\1/')" || true
    if [ -z "${verify_expected_checksum}" ]; then
        if [ "${verify_strict}" = "true" ]; then
            echo "ERROR: No checksum found for platform ${verify_platform} in manifest (JSON format may have changed)" >&2
            return 2
        fi
        echo "WARNING: No checksum found for platform ${verify_platform} in manifest (JSON format may have changed), skipping integrity check" >&2
        return 0
    fi

    verify_actual_checksum="$(sha256sum "${verify_claude_bin}" | awk '{print $1}')"

    if [ "${verify_actual_checksum}" != "${verify_expected_checksum}" ]; then
        echo "ERROR: Binary integrity check failed for ${verify_claude_bin}" >&2
        echo "  Expected SHA256: ${verify_expected_checksum}" >&2
        echo "  Actual SHA256:   ${verify_actual_checksum}" >&2
        return 1
    fi

    echo "Binary integrity verified (SHA256: ${verify_actual_checksum})"
}

echo "Installing Claude Code..."

FEATURE_VERSION="${VERSION:-"latest"}"
REQUIRE_INTEGRITY_CHECK="${REQUIREINTEGRITYCHECK:-"false"}"
FORCE_REINSTALL="${FORCEREINSTALL:-"false"}"

# Validate version format: 'latest', 'stable', or semver (e.g. 1.0.58)
if [ "${FEATURE_VERSION}" != "latest" ] && [ "${FEATURE_VERSION}" != "stable" ]; then
    # [[ =~ ]] matches the whole value; grep would accept a multi-line value
    # if any one of its lines matched
    if [[ ! "${FEATURE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: Invalid version '${FEATURE_VERSION}'. Must be 'latest', 'stable', or a semver (e.g. '1.0.58')." >&2
        exit 1
    fi
fi

# Determine remote user
REMOTE_USER="${_REMOTE_USER:-"automatic"}"
if [ "${REMOTE_USER}" = "auto" ] || [ "${REMOTE_USER}" = "automatic" ]; then
    REMOTE_USER="$(id -un 1000 2>/dev/null || echo "vscode")"
fi

# Validate that the resolved user actually exists on the system.
# On base images without a UID 1000 or "vscode" user, su would fail otherwise.
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

REMOTE_USER_HOME="$(getent passwd "${REMOTE_USER}" | cut -d: -f6)"
CLAUDE_BIN="${REMOTE_USER_HOME}/.local/bin/claude"

if ! command -v curl > /dev/null 2>&1; then
    echo "ERROR: curl is required but not found. Ensure the base image includes curl." >&2
    exit 1
fi

# Everything below runs commands as the remote user through su. If that does
# not work at all (/etc/nologin, an expired account, a PAM problem), a working
# launcher would look broken and be removed, and the installer would fail
# right after. Fail here instead, before anything is touched.
if ! su -s /bin/sh "${REMOTE_USER}" -c 'true' >/dev/null 2>&1; then
    echo "ERROR: Cannot run commands as '${REMOTE_USER}' with su. Nothing was changed." >&2
    exit 1
fi

INSTALLED_VERSION="$(get_installed_version)"
SKIP_INSTALL="false"
if [ "${FORCE_REINSTALL}" != "true" ] && [ -n "${INSTALLED_VERSION}" ]; then
    if [ "${FEATURE_VERSION}" = "latest" ] || [ "${FEATURE_VERSION}" = "stable" ]; then
        echo "Claude Code ${INSTALLED_VERSION} is already installed. Set forceReinstall to true to update. Skipping."
        SKIP_INSTALL="true"
    elif [ "${FEATURE_VERSION}" = "${INSTALLED_VERSION}" ]; then
        echo "Claude Code ${INSTALLED_VERSION} is already installed. Skipping installation."
        SKIP_INSTALL="true"
    fi
fi

if [ "${SKIP_INSTALL}" = "false" ]; then
    # A launcher that exists but cannot report a version is broken. The
    # installer leaves such a file in place, so remove it first.
    if { [ -e "${CLAUDE_BIN}" ] || [ -L "${CLAUDE_BIN}" ]; } && [ -z "${INSTALLED_VERSION}" ]; then
        echo "WARNING: Removing unusable ${CLAUDE_BIN} before installing" >&2
        # On failure the installer may still replace it; the checks after
        # the installation catch a launcher that is still broken
        remove_claude_bin || true
    fi
    # Install Claude Code as the remote user (installer is user-local)
    if [ "${FEATURE_VERSION}" = "latest" ]; then
        su -s /bin/bash - "${REMOTE_USER}" -c 'set -eo pipefail; curl -fsSL https://claude.ai/install.sh | bash'
    else
        # Safe: FEATURE_VERSION is validated above to be exactly 'stable' or a
        # single-line semver, so it cannot contain quotes or newlines
        su -s /bin/bash - "${REMOTE_USER}" -c "set -eo pipefail; curl -fsSL https://claude.ai/install.sh | bash -s -- '${FEATURE_VERSION}'"
    fi
    INSTALLED_VERSION="$(get_installed_version)"
    # A freshly installed launcher that cannot report a version does not
    # work, whether it is a binary that fails, a dangling link or a file that
    # is not executable, and it cannot be checked against a release manifest
    # either. Remove it so the next build does not start from a broken one.
    if { [ -e "${CLAUDE_BIN}" ] || [ -L "${CLAUDE_BIN}" ]; } && [ -z "${INSTALLED_VERSION}" ]; then
        echo "ERROR: The installed Claude Code launcher at ${CLAUDE_BIN} could not report its version. Check that Claude Code runs on this platform ($(uname -m))." >&2
        discard_claude_bin
        exit 1
    fi
fi

if [ -x "${CLAUDE_BIN}" ]; then
    # Verify binary integrity against release manifest
    # A checksum mismatch always fails. When the check cannot be performed,
    # pinned versions and requireIntegrityCheck fail; channels only warn.
    STRICT_INTEGRITY="false"
    if [ "${FEATURE_VERSION}" != "latest" ] && [ "${FEATURE_VERSION}" != "stable" ]; then
        STRICT_INTEGRITY="true"
        # A pinned install must yield exactly the requested version; the
        # checksum below only proves the binary matches what it claims to be
        if [ "${FEATURE_VERSION}" != "${INSTALLED_VERSION}" ]; then
            echo "ERROR: Requested Claude Code ${FEATURE_VERSION}, but the installed binary reports ${INSTALLED_VERSION}." >&2
            echo "ERROR: Check that version ${FEATURE_VERSION} exists, or choose another version." >&2
            discard_claude_bin
            exit 1
        fi
    elif [ "${REQUIRE_INTEGRITY_CHECK}" = "true" ]; then
        STRICT_INTEGRITY="true"
    fi
    verify_binary_integrity "${CLAUDE_BIN}" "${INSTALLED_VERSION}" "${STRICT_INTEGRITY}" && verify_rc=0 || verify_rc=$?
    if [ "${verify_rc}" -eq 1 ]; then
        # Checksum mismatch — binary is untrusted, always remove
        echo "ERROR: The binary is untrusted." >&2
        discard_claude_bin
        exit 1
    elif [ "${verify_rc}" -eq 2 ]; then
        # Verification could not be performed (network issue, unknown arch, etc.)
        if [ "${SKIP_INSTALL}" = "false" ]; then
            # Freshly installed binary — remove since we cannot verify it
            echo "ERROR: The freshly installed binary could not be verified." >&2
            discard_claude_bin
        else
            # Pre-existing binary — leave in place to avoid breaking a working install
            echo "ERROR: Integrity verification failed but existing binary was preserved." >&2
            echo "ERROR: Re-run with forceReinstall to re-download, or check network connectivity." >&2
        fi
        exit 1
    fi
    ln -sfn "${CLAUDE_BIN}" /usr/local/bin/claude
else
    echo "ERROR: Claude binary not found at ${CLAUDE_BIN} after installation." >&2
    exit 1
fi

echo "Claude Code ${INSTALLED_VERSION} installed successfully"
