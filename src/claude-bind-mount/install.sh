#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/share/claude-bind-mount"

mkdir -p "${INSTALL_DIR}"
install -m 0755 "${SCRIPT_DIR}/sync.sh" "${INSTALL_DIR}/sync.sh"
