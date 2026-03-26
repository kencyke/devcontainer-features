
# Claude Code (claude-code)

Installs Claude Code CLI via the official native installer (`https://claude.ai/install.sh`).

This feature uses the native installer recommended in the Claude Code setup docs. The older npm installation path is deprecated upstream.

## Options

| Option | Description | Type | Default |
|--------|-------------|------|---------|
| `version` | Version to install. `latest`, `stable`, or a specific version number (e.g. `1.0.58`). | `string` | `latest` |

## Usage

```json
"features": {
    "ghcr.io/kencyke/devcontainer-features/claude-code:1": {}
}
```

## Notes

- Claude Code requires a supported Claude account. Start `claude` after install and complete the browser login flow.
- The channel you choose at install time (`latest` or `stable`) becomes the default for auto-updates. `stable` follows a delayed release schedule (typically about one week behind `latest`).
- To disable background auto-updates inside the container, set `DISABLE_AUTOUPDATER` to `"1"` in your Claude Code `settings.json` under the `env` key.
- On Alpine, this feature installs `libgcc`, `libstdc++`, and `ripgrep`, and exports `USE_BUILTIN_RIPGREP=0` for musl compatibility.

## Verify Installation

After installation, verify Claude Code with `claude --version`.

For a more complete environment check, run `claude doctor`.
