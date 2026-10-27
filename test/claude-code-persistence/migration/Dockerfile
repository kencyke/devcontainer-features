FROM mcr.microsoft.com/devcontainers/base:ubuntu

# State left behind by an installer during the image build. The scenario
# prefills the volume with its own settings.json, which must win.
RUN mkdir -p /home/vscode/.claude \
    && echo image > /home/vscode/.claude/settings.json \
    && echo image > /home/vscode/.claude/history.jsonl \
    && echo image > /home/vscode/.claude.json \
    && chown -R vscode:vscode /home/vscode/.claude /home/vscode/.claude.json
