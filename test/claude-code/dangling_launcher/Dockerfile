FROM mcr.microsoft.com/devcontainers/base:ubuntu

# A launcher left behind by a half-finished install: it points into the
# installer's versions directory at a binary that no longer exists.
RUN mkdir -p /home/vscode/.local/bin /home/vscode/.local/share/claude/versions \
    && ln -s /home/vscode/.local/share/claude/versions/0.0.0 /home/vscode/.local/bin/claude \
    && chown -R vscode:vscode /home/vscode/.local
