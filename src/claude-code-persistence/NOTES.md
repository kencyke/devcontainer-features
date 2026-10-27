## How it works

Claude Code keeps its credentials, settings, session transcripts, prompt history and plugins in `~/.claude`, and its account details, onboarding state and per-project trust in `~/.claude.json`. Both live in the container's home directory and are discarded on rebuild.

This feature stores them in a Docker named volume instead, following the approach in the [official dev container guide](https://code.claude.com/docs/en/devcontainer#persist-authentication-and-settings-across-rebuilds):

```
volume claude-code-persistence-${devcontainerId} -> /mnt/claude-code-persistence
CLAUDE_CONFIG_DIR=/mnt/claude-code-persistence
~/.claude      -> /mnt/claude-code-persistence
~/.claude.json -> /mnt/claude-code-persistence/.claude.json
```

- `CLAUDE_CONFIG_DIR` makes Claude Code keep `.claude.json` inside the volume as well. The `~/.claude` and `~/.claude.json` symlinks are only for tools that hard-code those paths.
- When the container is created, anything already in `~/.claude` or `~/.claude.json` (for example written by an installer during the image build) is moved into the volume, and the moved entries are listed in the creation log. An entry whose name already exists in the volume is not moved; it is discarded with a warning, and the copy in the volume wins. This includes `settings.json`, so settings that must always apply belong in managed settings, not in the image's `~/.claude`.
- Nothing on the host is mounted or modified, and nothing is written to the workspace. If `~/.claude` or `~/.claude.json` is on a separate mount (for example the host's directory, or your whole home directory, bind-mounted by your own configuration), or `~/.claude` contains a mount, the feature leaves it untouched and prints a warning.
- Do not set `CLAUDE_CONFIG_DIR` yourself in `devcontainer.json`, and do not mount anything below `/mnt/claude-code-persistence`. If either is done, or the volume is not mounted, the feature skips its setup with a warning.

## Sharing one volume across projects

By default each dev container gets its own volume, `claude-code-persistence-${devcontainerId}`, and you log in once per project. To log in once for several projects, mount a shared volume at the same target in each project's `devcontainer.json`:

```json
"mounts": [
    {
        "source": "claude-code-persistence",
        "target": "/mnt/claude-code-persistence",
        "type": "volume"
    }
]
```

When a Feature and `devcontainer.json` mount to the same target, the mount from `devcontainer.json` wins, so the shared volume replaces the per-container volume instead of being mounted next to it. Each container mounts exactly one volume, and a container that does not add this mount never sees the shared one. The name is up to you; you can use a separate shared volume for each group of projects that you trust equally. Use a named volume, not a directory from the host: the feature changes the ownership of the mounted directory and moves files into it.

All dev containers that mount the same volume share everything in it:

- They form a single trust boundary. Code running in any of them (the project's dependencies, its image, or Claude Code acting on a prompt injection) can read every project's transcripts and credentials, and can change the settings, hooks, MCP servers and plugins that the other containers then run. Anything a project's image puts in `~/.claude` is also moved into the shared volume. Share a volume only among projects you trust equally.
- Per-project state (`projects/` transcripts and auto-memory, and the trust decisions in `.claude.json`) is keyed by the path inside the container, not by the repository. Two projects that use the same `workspaceFolder` see each other's sessions, and a repository you have never opened inherits the trust you granted to another one at the same path, so its hooks and project settings run without the trust prompt. The default `workspaceFolder` is `/workspaces/` followed by the name of the project folder on the host, so this applies to any two repositories cloned into folders with the same name, not only to projects that both set something like `/workspace`. Distinct `workspaceFolder`s avoid this, but they do not hide the files from the other containers.
- Dev containers running at the same time also share per-process state such as `sessions/` and `ide/`. If that causes problems, do not share the volume.
- If the containers run as different UIDs, each one takes ownership of the shared volume when it is created, which locks out containers that are still running as the previous UID.

## Security

The volume holds your OAuth credentials, plaintext session transcripts, and any tokens you put in settings or MCP server configuration. **Docker named volumes have no access control**: any container on the same Docker host can mount a volume by name, and nothing in this feature can prevent that.

The boundary that protects the volume is therefore not Docker but your decision to open a repository in a dev container at all. A `devcontainer.json` from a repository you do not trust can mount `claude-code-persistence` by name, but it can just as well bind-mount `/var/run/docker.sock` or your whole home directory, which gives it everything on the host. **Treat opening a dev container like running the repository's code on your host**, and keep VS Code's Workspace Trust prompt enabled.

Within that boundary:

- The per-container volume is named after the `devcontainerId`, which is a hash of the host paths of the project folder and its `devcontainer.json`. **It is not a secret:** anyone who knows those paths can compute it, and anything with access to the Docker daemon can list it. A different repository that you later open from the same paths gets the same volume, including your credentials and the trust decisions you made for the previous one. **Remove the volume when you replace a project at the same location.**
- A shared volume with a fixed name such as `claude-code-persistence` (the name the [official guide](https://code.claude.com/docs/en/devcontainer#persist-authentication-and-settings-across-rebuilds) uses) can be mounted by any `devcontainer.json` on the host without computing anything. **Share a volume only on a host where you open dev containers from repositories you trust.**

The volume also keeps settings, hooks, MCP servers, plugins and memory files, so a change that malicious code makes to them inside a container survives a rebuild. **If you suspect a container was compromised, remove its volume, not just the container. Removing the volume does not invalidate credentials that were already copied out of it.**

## Ownership and sudo

New volumes start out owned by the remote user. If the owner does not match (for example after `updateRemoteUserUID` changed the user's UID), the feature fixes it with `sudo -n` when the container is created. On images without passwordless sudo it prints a warning with the `chown` command to run; until you run it, Claude Code cannot read or write its state.

## Removing the stored data

To delete the data, remove the containers that use it, then remove the volume. Per-container volumes are not removed when you delete a project. List them with:

```sh
docker volume ls --filter name=claude-code-persistence-
```

Remove a shared volume by the name you gave it, for example `docker volume rm claude-code-persistence`.

## Running the tests locally

`devcontainer features test` leaves behind `claude-code-persistence-*` test volumes that you need to remove yourself. The `shared_volume` and `shared_volume_other_uid` scenarios use their own `claude-code-persistence-test-shared` volume. Before its container is created, `shared_volume_other_uid` fills that volume from the host with files owned by UID 1000, so that it always has their ownership to take over. Neither touches a shared volume you use yourself.
