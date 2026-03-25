#!/usr/bin/env bash
set -euo pipefail

# Configurable inputs (override via env vars)
SUPERPOWERS_REPO_URL="${SUPERPOWERS_REPO_URL:-https://github.com/obra/superpowers.git}"
SUPERPOWERS_REPO_REF="${SUPERPOWERS_REPO_REF:-main}"
SUPERPOWERS_DIR="${SUPERPOWERS_DIR:-$HOME/.openclaw/vendor/superpowers}"
PLUGIN_ID="superpowers-openclaw"

# Preflight checks
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required but not found in PATH."
  exit 1
fi
if ! command -v openclaw >/dev/null 2>&1; then
  echo "ERROR: openclaw is required but not found in PATH."
  exit 1
fi

echo "Superpowers OpenClaw plugin config:"
echo "  SUPERPOWERS_REPO_URL=$SUPERPOWERS_REPO_URL"
echo "  SUPERPOWERS_REPO_REF=$SUPERPOWERS_REPO_REF"
echo "  SUPERPOWERS_DIR=$SUPERPOWERS_DIR"

# 1) Clone or update superpowers
if [ ! -d "$SUPERPOWERS_DIR/.git" ]; then
  echo "Cloning Superpowers repo..."
  git clone --depth 1 --branch "$SUPERPOWERS_REPO_REF" "$SUPERPOWERS_REPO_URL" "$SUPERPOWERS_DIR"
else
  echo "Superpowers already present at $SUPERPOWERS_DIR. Updating..."
  git -C "$SUPERPOWERS_DIR" remote set-url origin "$SUPERPOWERS_REPO_URL"

  # If shallow, unshallow so switching refs remains reliable.
  if [ "$(git -C "$SUPERPOWERS_DIR" rev-parse --is-shallow-repository)" = "true" ]; then
    git -C "$SUPERPOWERS_DIR" fetch --unshallow origin
  fi

  git -C "$SUPERPOWERS_DIR" fetch origin "$SUPERPOWERS_REPO_REF"
  git -C "$SUPERPOWERS_DIR" checkout -B "$SUPERPOWERS_REPO_REF" FETCH_HEAD
fi

# 2) Verify plugin files exist
if [ ! -f "$SUPERPOWERS_DIR/openclaw.plugin.json" ]; then
  echo "ERROR: openclaw.plugin.json not found at $SUPERPOWERS_DIR/openclaw.plugin.json"
  exit 1
fi
if [ ! -f "$SUPERPOWERS_DIR/package.json" ]; then
  echo "ERROR: package.json not found at $SUPERPOWERS_DIR/package.json"
  exit 1
fi

# 3) Install the linked plugin once, then just re-enable on updates
if openclaw plugins info "$PLUGIN_ID" --json >/dev/null 2>&1; then
  echo "OpenClaw plugin already registered. Reusing existing link."
else
  echo "Installing linked OpenClaw plugin..."
  openclaw plugins install --link "$SUPERPOWERS_DIR"
fi
openclaw plugins enable "$PLUGIN_ID"

# 4) Restart the gateway so long-lived sessions pick up the plugin
echo "Restarting OpenClaw gateway..."
if ! openclaw gateway restart; then
  echo "WARNING: gateway restart failed. Run 'openclaw gateway restart' manually."
fi

# 5) Verify installation
echo "Verifying installation..."
openclaw plugins info "$PLUGIN_ID" --json || echo "Plugin info check failed."
openclaw skills info using-superpowers || echo "Skill check failed, check openclaw configuration."

echo "Superpowers OpenClaw plugin installation complete!"
