#!/usr/bin/env bash

set -e

echo "Checking if Claude Code is installed..."
command -v claude
test -x /usr/local/bin/claude
claude --version
