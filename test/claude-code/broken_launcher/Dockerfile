FROM mcr.microsoft.com/devcontainers/base:ubuntu

# A launcher that points into the installer's versions directory at a binary
# that exists but fails to run. It prints an error that contains a version-like
# number before exiting, so install.sh must look at the exit status rather
# than take any "x.y.z" in the output as the installed version.
RUN mkdir -p /home/vscode/.local/bin /home/vscode/.local/share/claude/versions \
    && printf '#!/bin/sh\necho "Error: requires glibc 2.28.0 or newer"\nexit 1\n' > /home/vscode/.local/share/claude/versions/0.0.0 \
    && chmod 755 /home/vscode/.local/share/claude/versions/0.0.0 \
    && ln -s /home/vscode/.local/share/claude/versions/0.0.0 /home/vscode/.local/bin/claude \
    && chown -R vscode:vscode /home/vscode/.local
