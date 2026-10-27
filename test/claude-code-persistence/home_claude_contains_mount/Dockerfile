FROM mcr.microsoft.com/devcontainers/base:ubuntu

# ~/.claude itself is on the root filesystem, but the scenario mounts a volume
# at ~/.claude/commands (standing in for a host directory the user bind-mounted
# there). Docker copies commands/ into that empty volume.
RUN mkdir -p /home/vscode/.claude/commands \
    && echo keep > /home/vscode/.claude/commands/sentinel \
    && echo keep > /home/vscode/.claude/other \
    && chown -R vscode:vscode /home/vscode/.claude
