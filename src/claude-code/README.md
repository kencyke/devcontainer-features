
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
| requireIntegrityCheck | When true, fail the installation if the binary integrity check cannot be performed (e.g. manifest download failure). By default, latest/stable installs only warn on verification failure. | boolean | false |
| forceReinstall | When true, always re-download and install Claude Code even if it is already present. Useful for ensuring the latest version when using channel installs (latest/stable). | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/kencyke/devcontainer-features/blob/main/src/claude-code/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
