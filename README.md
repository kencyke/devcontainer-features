# Development Container Features

| Feature | Description |
| --- | --- |
| [claude-bind-mount](src/claude-bind-mount/README.md) | Stages the host `~/.claude` directory in the container and copies it into the container user's home only when `~/.claude` does not already contain data. |
| [claude-code](src/claude-code/README.md) | Installs Claude Code CLI via the official native installer (`https://claude.ai/install.sh`). |
