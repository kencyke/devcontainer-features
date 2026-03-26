#!/bin/sh
set -e

apk_install() {
    package_list=""
    for package_name in "$@"; do
        if ! apk info -e "${package_name}" >/dev/null 2>&1 || [ "${package_name}" = "ca-certificates" ]; then
            package_list="${package_list} ${package_name}"
        fi
    done

    if [ -n "${package_list}" ]; then
        apk update
        apk add --no-cache ${package_list}
    fi
}

apt_install() {
    package_list=""
    for package_name in "$@"; do
        if ! dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | grep -q "install ok installed" \
            || [ "${package_name}" = "ca-certificates" ]; then
            package_list="${package_list} ${package_name}"
        fi
    done

    if [ -n "${package_list}" ]; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${package_list}
    fi
}

get_installed_version() {
    if su - "${REMOTE_USER}" -c 'command -v claude >/dev/null 2>&1'; then
        su - "${REMOTE_USER}" -c 'claude --version' 2>/dev/null | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1
    fi
}

# Verify binary integrity using SHA256 checksum from release manifest.
# See: https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing
verify_binary_integrity() {
    verify_claude_bin="$1"
    verify_version="$2"
    verify_strict="${3:-false}"  # "true" for specific-version installs

    if [ -z "${verify_version}" ] || [ "${verify_version}" = "unknown" ]; then
        echo "WARNING: Unable to determine installed version, skipping integrity check" >&2
        return 0
    fi

    case "$(uname -m)" in
        x86_64)  verify_arch="x64" ;;
        aarch64) verify_arch="arm64" ;;
        *)
            echo "WARNING: Unknown architecture $(uname -m), skipping integrity check" >&2
            return 0
            ;;
    esac

    verify_platform="linux-${verify_arch}"
    if [ "${ALPINE:-}" = "true" ]; then
        verify_platform="${verify_platform}-musl"
    fi

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
REMOTE_USER_HOME="${_REMOTE_USER_HOME:-"/home/${REMOTE_USER}"}"
if [ "${REMOTE_USER}" = "root" ]; then
    REMOTE_USER_HOME="/root"
fi

# Install dependencies required by the Claude installer and CLI.
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="${ID}"
else
    echo "ERROR: Unable to detect Linux distribution." >&2
    exit 1
fi

case "${DISTRO}" in
    alpine)
        apk_install bash ca-certificates curl libgcc libstdc++ ripgrep
        ALPINE=true
        ;;
    debian | ubuntu)
        apt_install bash ca-certificates curl ripgrep
        ;;
    *)
        echo "ERROR: Unsupported distribution '${DISTRO}'." >&2
        exit 1
        ;;
esac

if ! command -v curl > /dev/null 2>&1; then
    echo "ERROR: curl is required but not found after dependency installation." >&2
    exit 1
fi

INSTALLED_VERSION="$(get_installed_version)"
if [ -n "${INSTALLED_VERSION}" ] && [ "${FEATURE_VERSION}" = "${INSTALLED_VERSION}" ]; then
    echo "Claude Code ${INSTALLED_VERSION} is already installed. Skipping installation."
else
# Install Claude Code as the remote user (installer is user-local)
    if [ "${FEATURE_VERSION}" = "latest" ]; then
        su - "${REMOTE_USER}" -c 'curl -fsSL https://claude.ai/install.sh | bash'
    else
        # Safe: FEATURE_VERSION is validated above to only contain [0-9.], 'latest', or 'stable'
        su - "${REMOTE_USER}" -c "curl -fsSL https://claude.ai/install.sh | bash -s -- '${FEATURE_VERSION}'"
    fi
    INSTALLED_VERSION="$(get_installed_version)"
fi

CLAUDE_BIN="${REMOTE_USER_HOME}/.local/bin/claude"
if [ -x "${CLAUDE_BIN}" ]; then
    # Verify binary integrity against release manifest
    # Hard-fail integrity check for pinned versions; soft-fail for channels
    STRICT_INTEGRITY="false"
    if [ "${FEATURE_VERSION}" != "latest" ] && [ "${FEATURE_VERSION}" != "stable" ]; then
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

# Add ~/.local/bin to PATH in profile files
PATH_EXPORT='export PATH="$HOME/.local/bin:$PATH"'
for profile_file in "${REMOTE_USER_HOME}/.profile" "${REMOTE_USER_HOME}/.bashrc" "${REMOTE_USER_HOME}/.zshrc"; do
    if [ -f "${profile_file}" ] && ! grep -qF '.local/bin' "${profile_file}"; then
        echo "${PATH_EXPORT}" >> "${profile_file}"
    fi
done
chown "${REMOTE_USER}" "${REMOTE_USER_HOME}/.profile" "${REMOTE_USER_HOME}/.bashrc" "${REMOTE_USER_HOME}/.zshrc" 2>/dev/null || true

# Alpine: disable built-in ripgrep (musl incompatible)
if [ "${ALPINE:-}" = "true" ]; then
    RG_EXPORT='export USE_BUILTIN_RIPGREP=0'
    for profile_file in "${REMOTE_USER_HOME}/.profile" "${REMOTE_USER_HOME}/.bashrc" "${REMOTE_USER_HOME}/.zshrc"; do
        if [ -f "${profile_file}" ] && ! grep -qF 'USE_BUILTIN_RIPGREP' "${profile_file}"; then
            echo "${RG_EXPORT}" >> "${profile_file}"
        fi
    done
fi

# Verify installation
if command -v claude > /dev/null 2>&1 || su - "${REMOTE_USER}" -c 'command -v claude > /dev/null 2>&1'; then
    echo "Claude Code ${INSTALLED_VERSION} installed successfully"
else
    echo "ERROR: claude command not found after installation" >&2
    exit 1
fi
