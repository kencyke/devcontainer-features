#!/bin/bash
set -eo pipefail

get_installed_version() {
    giv_claude_bin="${REMOTE_USER_HOME}/.local/bin/claude"
    if [ -x "${giv_claude_bin}" ]; then
        "${giv_claude_bin}" --version 2>/dev/null | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1
    fi
}

# Verify binary integrity using SHA256 checksum from release manifest.
# See: https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing
verify_binary_integrity() {
    verify_claude_bin="$1"
    verify_version="$2"
    verify_strict="${3:-false}"  # "true" for specific-version installs

    if [ -z "${verify_version}" ] || [ "${verify_version}" = "unknown" ]; then
        if [ "${verify_strict}" = "true" ]; then
            echo "ERROR: Unable to determine installed version for integrity check" >&2
            return 1
        fi
        echo "WARNING: Unable to determine installed version, skipping integrity check" >&2
        return 0
    fi

    case "$(uname -m)" in
        x86_64)  verify_arch="x64" ;;
        aarch64) verify_arch="arm64" ;;
        *)
            if [ "${verify_strict}" = "true" ]; then
                echo "ERROR: Unknown architecture $(uname -m), cannot perform integrity check" >&2
                return 1
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
            return 1
        fi
        echo "WARNING: Could not download release manifest for v${verify_version}, skipping integrity check" >&2
        return 0
    }

    verify_expected_checksum="$(printf '%s' "${verify_manifest}" | grep -A2 "\"${verify_platform}\"" | grep '"checksum"' | sed 's/.*"checksum"[[:space:]]*:[[:space:]]*"\([a-f0-9]*\)".*/\1/')"
    if [ -z "${verify_expected_checksum}" ]; then
        if [ "${verify_strict}" = "true" ]; then
            echo "ERROR: No checksum found for platform ${verify_platform} in manifest (JSON format may have changed)" >&2
            return 1
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
    if ! echo "${FEATURE_VERSION}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
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

# Resolve the home directory for the final REMOTE_USER.
# _REMOTE_USER_HOME corresponds to _REMOTE_USER, which may differ from
# REMOTE_USER after the _CONTAINER_USER fallback above. Use _REMOTE_USER_HOME
# only when REMOTE_USER still matches _REMOTE_USER; otherwise resolve it
# from the system so version detection and installation target the correct path.
if [ -n "${_REMOTE_USER_HOME:-}" ] && [ "${REMOTE_USER}" = "${_REMOTE_USER:-}" ]; then
    REMOTE_USER_HOME="${_REMOTE_USER_HOME}"
elif [ "${REMOTE_USER}" = "root" ]; then
    REMOTE_USER_HOME="/root"
else
    REMOTE_USER_HOME="$(getent passwd "${REMOTE_USER}" | cut -d: -f6 2>/dev/null)" || REMOTE_USER_HOME=""
    if [ -z "${REMOTE_USER_HOME}" ]; then
        REMOTE_USER_HOME="/home/${REMOTE_USER}"
    fi
fi

if ! command -v curl > /dev/null 2>&1; then
    echo "ERROR: curl is required but not found. Ensure the base image includes curl." >&2
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
# Install Claude Code as the remote user (installer is user-local)
    if [ "${FEATURE_VERSION}" = "latest" ]; then
        su -s /bin/bash - "${REMOTE_USER}" -c 'set -eo pipefail; curl -fsSL https://claude.ai/install.sh | bash'
    else
        # Safe: FEATURE_VERSION is validated above to only contain [0-9.], 'latest', or 'stable'
        su -s /bin/bash - "${REMOTE_USER}" -c "set -eo pipefail; curl -fsSL https://claude.ai/install.sh | bash -s -- '${FEATURE_VERSION}'"
    fi
    INSTALLED_VERSION="$(get_installed_version)"
fi

CLAUDE_BIN="${REMOTE_USER_HOME}/.local/bin/claude"
if [ -x "${CLAUDE_BIN}" ]; then
    # Verify binary integrity against release manifest
    # Hard-fail integrity check for pinned versions; soft-fail for channels
    # Users can force strict checks for channels via requireIntegrityCheck
    STRICT_INTEGRITY="false"
    if [ "${FEATURE_VERSION}" != "latest" ] && [ "${FEATURE_VERSION}" != "stable" ]; then
        STRICT_INTEGRITY="true"
    elif [ "${REQUIRE_INTEGRITY_CHECK}" = "true" ]; then
        STRICT_INTEGRITY="true"
    fi
    if ! verify_binary_integrity "${CLAUDE_BIN}" "${INSTALLED_VERSION}" "${STRICT_INTEGRITY}"; then
        rm -f "${CLAUDE_BIN}"
        echo "ERROR: Removed untrusted binary. Please retry installation." >&2
        exit 1
    fi
    ln -sf "${CLAUDE_BIN}" /usr/local/bin/claude
else
    echo "ERROR: Claude binary not found at ${CLAUDE_BIN} after installation." >&2
    exit 1
fi

# Verify installation
if [ -x /usr/local/bin/claude ] || [ -x "${REMOTE_USER_HOME}/.local/bin/claude" ]; then
    echo "Claude Code ${INSTALLED_VERSION} installed successfully"
else
    echo "ERROR: claude command not found after installation" >&2
    exit 1
fi
