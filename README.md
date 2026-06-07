# dotfiles

chezmoi-managed dotfiles. Supports macOS (personal + work) and Linux (Bazzite, VMs/servers).

## Setup

```bash
curl -fsSL https://raw.githubusercontent.com/nobleobject/dotfiles/master/bootstrap.sh | bash
```

The script will:
1. Install chezmoi (via Homebrew on macOS, or directly to `~/.local/bin` on Linux)
2. Prompt for profile (`personal` / `work`), git name, email, and optional SSH signing key
3. Show a diff preview
4. Ask before applying anything

## Profiles

| Profile | Machines |
|---------|----------|
| `personal` | Personal Mac, Bazzite desktop, personal Linux VMs |
| `work` | Work Mac, work Linux VMs |

## Day-to-day

```bash
chezmoi diff          # preview pending changes
chezmoi apply         # apply to home dir
chezmoi update        # pull latest + apply
chezmoi edit ~/.config/fish/config.fish   # edit a managed file
```

## Adding packages

Edit `run_onchange_install-packages.sh.tmpl`. Adding a package triggers reinstall on next `chezmoi apply`.
