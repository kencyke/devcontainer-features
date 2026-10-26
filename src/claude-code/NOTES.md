## Notes

- This feature uses the native installer recommended in the Claude Code setup docs. The older npm installation path is deprecated upstream.
- Claude Code requires a supported Claude account. Start `claude` after install and complete the browser login flow.
- The channel you choose at install time (`latest` or `stable`) becomes the default for auto-updates. `stable` follows a delayed release schedule (typically about one week behind `latest`).
- To disable background auto-updates inside the container, set `DISABLE_AUTOUPDATER` to `"1"` in your Claude Code `settings.json` under the `env` key.
- **Alpine Linux is not supported.** This feature targets Debian/Ubuntu-based images. For Alpine, see the [official manual setup](https://code.claude.com/docs/en/setup#alpine-linux-and-musl-based-distributions).

## Verify Installation

After installation, verify Claude Code with `claude --version`.

For a more complete environment check, run `claude doctor`.
