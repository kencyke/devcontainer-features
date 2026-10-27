FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Docker copies this into the empty volume mounted at ~/.claude by the scenario.
RUN mkdir -p /home/vscode/.claude \
    && echo keep > /home/vscode/.claude/sentinel \
    && chown -R vscode:vscode /home/vscode/.claude
