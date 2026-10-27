# Development Container Features

| Feature | Description |
| --- | --- |
| [claude-code](src/claude-code/README.md) | Installs Claude Code CLI via the official native installer (`https://claude.ai/install.sh`). |
| [claude-code-persistence](src/claude-code-persistence/README.md) | Persists Claude Code state (`~/.claude` and `.claude.json`) across container rebuilds using a Docker named volume. |

## Testing

Run the feature tests with the [devcontainer CLI](https://github.com/devcontainers/cli):

```bash
devcontainer features test -f claude-code-persistence .
```

Each run builds throwaway `vsc-*` images and leaves them behind along with the build cache, and the `claude-code-persistence` scenarios leave behind their volumes. Clean them up with:

```bash
# Remove test images and the build cache
docker images -q --filter 'reference=vsc-*' | xargs -r docker image rm
docker builder prune -af

# Remove volumes created by the claude-code-persistence tests
docker volume ls -q --filter 'name=^claude-code-persistence' | xargs -r docker volume rm
```
