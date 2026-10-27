
# Claude Code (claude-code)

Installs Claude Code CLI via the official native installer (https://claude.ai/install.sh)

## Example Usage

```json
"features": {
    "ghcr.io/kencyke/devcontainer-features/claude-code:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Version to install. 'latest', 'stable', or a specific version number (e.g. '1.0.58'). | string | latest |
| requireIntegrityCheck | When true, fail the installation if the binary integrity check cannot be performed (e.g. manifest download failure). By default, latest/stable installs only warn when the integrity check cannot be performed. | boolean | false |
| forceReinstall | When true, always re-download and install Claude Code even if it is already present. Useful for ensuring the latest version when using channel installs (latest/stable). | boolean | false |

## Notes

- This feature uses the native installer recommended in the Claude Code setup docs. The older npm installation path is deprecated upstream.
- Claude Code requires a supported Claude account. Start `claude` after install and complete the browser login flow.
- The channel you choose at install time (`latest` or `stable`) becomes the default for auto-updates. `stable` follows a delayed release schedule (typically about one week behind `latest`).
- When `version` is set to a specific version, the build fails if the installer leaves a binary that reports a different version, instead of silently accepting whatever was installed.
- To disable background auto-updates inside the container, set `DISABLE_AUTOUPDATER` to `"1"` in your Claude Code `settings.json` under the `env` key.
- **Alpine Linux is not supported.** This feature targets Debian/Ubuntu-based images. For Alpine, see the [official manual setup](https://code.claude.com/docs/en/setup#alpine-linux-and-musl-based-distributions).

## Verify Installation

After installation, verify Claude Code with `claude --version`.

For a more complete environment check, run `claude doctor`.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/kencyke/devcontainer-features/blob/main/src/claude-code/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
