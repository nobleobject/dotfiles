#!/bin/bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
REPO="https://github.com/nobleobject/dotfiles.git"
LOCAL_BIN="$HOME/.local/bin"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}==>${NC} $*"; }
error() { echo -e "${RED}==>${NC} $*" >&2; exit 1; }

# ── 1. Install chezmoi ────────────────────────────────────────────────────────
if command -v chezmoi &>/dev/null; then
  info "chezmoi $(chezmoi --version | awk '{print $3}') already installed"
else
  info "Installing chezmoi..."
  if command -v brew &>/dev/null; then
    brew install chezmoi
  else
    mkdir -p "$LOCAL_BIN"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$LOCAL_BIN"
    export PATH="$LOCAL_BIN:$PATH"
  fi
fi

# chezmoi init (below) runs .chezmoi.toml.tmpl, which prompts for profile,
# git name/email, and signing key, then writes ~/.config/chezmoi/chezmoi.toml.

# ── 3. Init or update ─────────────────────────────────────────────────────────
if [[ -d "$HOME/.local/share/chezmoi/.git" ]]; then
  info "Already initialised — pulling latest from remote..."
  chezmoi git pull
else
  info "Initialising chezmoi from $REPO..."
  chezmoi init "$REPO"
fi

# ── 4. Dry run ────────────────────────────────────────────────────────────────
echo ""
info "Diff preview (nothing applied yet):"
echo "────────────────────────────────────"
chezmoi diff || true
echo "────────────────────────────────────"
echo ""

# ── 5. Prompt to apply ────────────────────────────────────────────────────────
read -rp "Apply changes? [y/N] " CONFIRM < /dev/tty
if [[ "${CONFIRM,,}" == "y" ]]; then
  chezmoi apply
  info "Done."
else
  warn "Skipped. Run 'chezmoi apply' when ready."
fi

# Self-delete if run as a downloaded file (not piped via curl | bash)
if [[ -f "$SCRIPT_PATH" ]]; then
  rm -f "$SCRIPT_PATH"
fi
