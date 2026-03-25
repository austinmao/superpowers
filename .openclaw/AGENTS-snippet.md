<!-- superpowers-openclaw-wrapper -->
This file is retained for compatibility with the original wrapper PR.

Native OpenClaw installation no longer requires pasting anything into `AGENTS.md`.
Use the plugin install flow in `.openclaw/INSTALL.md` instead. The plugin now:

- declares `./skills` directly in `openclaw.plugin.json`
- injects its guidance via `before_prompt_build`
- avoids symlinking skills into `~/.openclaw/skills`
