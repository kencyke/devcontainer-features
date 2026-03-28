# Claude Bind Mount (claude-bind-mount)

- The host `~/.claude` is bind mounted **read-only** to `/var/tmp/claude-bind-mount/host-home/.claude`.
- On container creation, the feature copies that staged content into the container user's `~/.claude` if the target is missing or empty. Copied files are owned by the container user regardless of host-side ownership.
- If the container user's `~/.claude` already contains files, the feature skips the copy and leaves existing data unchanged.

## Usage

This feature pairs well with [claude-code](../claude-code). Both can be listed in any order since `claude-bind-mount` runs its sync during `onCreateCommand`, which executes after all features are installed.

```json
"features": {
	"ghcr.io/kencyke/devcontainer-features/claude-code:1": {},
	"ghcr.io/kencyke/devcontainer-features/claude-bind-mount:1": {}
}
```

## Notes

- The host `~/.claude` directory must already exist before the container is created. The bind mount will fail if the source directory is missing.
- This feature is intentionally conservative: it does not merge, overwrite, or back up existing container-side `~/.claude` data.

## Environment Variables

The sync script accepts the following environment variables for testing and advanced usage:

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_BIND_MOUNT_SOURCE_DIR` | `/var/tmp/claude-bind-mount/host-home/.claude` | Override the staged source directory |
| `CLAUDE_BIND_MOUNT_TARGET_DIR` | `${HOME}/.claude` | Override the target directory |
