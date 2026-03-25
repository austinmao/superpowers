# Superpowers for OpenClaw

This integration installs Superpowers as a native OpenClaw plugin. The plugin declares
its `./skills` directory directly in `openclaw.plugin.json`, so OpenClaw can discover
the skill pack without symlinking anything into `~/.openclaw/skills`.

## Section 1 — Prerequisites

- **OpenClaw** is installed and configured.
- `git` is available in your shell.

## Section 2 — Automated Setup (Recommended)

Run the included setup script:

```bash
./setup.sh
```

By default, it uses:

- Repo: `https://github.com/obra/superpowers.git`
- Ref: `main`
- Clone dir: `~/.openclaw/vendor/superpowers`
- Plugin id: `superpowers-openclaw`

### Optional overrides

You can override defaults with environment variables:

```bash
SUPERPOWERS_REPO_URL="https://github.com/caasols/superpowers.git" \
SUPERPOWERS_REPO_REF="feat/openclaw-wrapper" \
SUPERPOWERS_DIR="$HOME/.openclaw/vendor/superpowers-dev" \
./setup.sh
```

Useful variables:

- `SUPERPOWERS_REPO_URL`
- `SUPERPOWERS_REPO_REF`
- `SUPERPOWERS_DIR`

## Section 3 — Manual Setup

```bash
# Clone superpowers to a stable location
git clone https://github.com/obra/superpowers.git ~/.openclaw/vendor/superpowers

# Register the repo as a linked OpenClaw plugin
openclaw plugins install --link ~/.openclaw/vendor/superpowers
openclaw plugins enable superpowers-openclaw

# Restart the gateway so long-lived sessions pick up the plugin
openclaw gateway restart
```

No `AGENTS.md` snippet is required. The plugin injects its guidance through the
OpenClaw `before_prompt_build` hook and exposes the skills through the plugin manifest.

## Section 4 — Verify Installation

```bash
openclaw plugins info superpowers-openclaw --json
openclaw skills info using-superpowers
```

You should see the plugin loaded and the `using-superpowers` skill resolved from the
linked repo.

## Section 5 — Keeping Skills Updated

Recommended: re-run `./setup.sh`, which updates the configured repo/ref, refreshes the
linked plugin, and restarts the gateway.

If updating manually, pull an explicit ref:

```bash
cd ~/.openclaw/vendor/superpowers && git pull origin <branch-or-ref>
openclaw gateway restart
```

No relinking or symlink maintenance required.
