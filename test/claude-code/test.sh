#!/usr/bin/env bash

set -e

echo "Checking if Claude Code is installed..."
which claude
test -x /usr/local/bin/claude
claude --version
