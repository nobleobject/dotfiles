#!/bin/bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
REPO="https://github.com/nobleobject/dotfiles.git"
CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"
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

# ── 2. Create chezmoi.toml if missing ────────────────────────────────────────
if [[ -f "$CHEZMOI_CONFIG" ]]; then
  info "chezmoi.toml already exists — skipping"
else
  warn "No chezmoi.toml found. Answer a few questions to create one."
  echo ""

  [[ -e /dev/tty ]] || error "Cannot open /dev/tty. Run the script directly instead of curl | bash."

  # Read from /dev/tty explicitly — exec < /dev/tty would cut bash off from the
  # piped script source in a curl | bash context.
  read -rp "  Profile (personal/work) [personal]: " PROFILE < /dev/tty
  PROFILE="${PROFILE:-personal}"

  read -rp "  Git name: " GIT_NAME < /dev/tty
  read -rp "  Git email: " GIT_EMAIL < /dev/tty

  SIGNING_KEY=""
  if [[ "$PROFILE" == "personal" ]]; then
    read -rp "  Git signing key (SSH public key, blank to skip): " SIGNING_KEY < /dev/tty
  fi

  mkdir -p "$(dirname "$CHEZMOI_CONFIG")"
  # Use printf to avoid heredoc + shell expansion issues in curl | bash context
  {
    printf '[data]\n'
    printf '  profile        = "%s"\n' "$PROFILE"
    printf '  git_name       = "%s"\n' "$GIT_NAME"
    printf '  git_email      = "%s"\n' "$GIT_EMAIL"
    printf '  git_signingkey = "%s"\n' "$SIGNING_KEY"
    printf '\n[onepassword]\n'
    printf '  command = "op"\n'
  } > "$CHEZMOI_CONFIG"

  info "Created $CHEZMOI_CONFIG"
fi

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
