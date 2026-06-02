# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

chezmoi dotfiles source directory. Managed via `chezmoi` — do not edit target files directly. Always edit source files here, then apply.

## Key commands

```bash
chezmoi diff                    # preview what would change on apply
chezmoi apply                   # apply source to home dir
chezmoi apply <target-path>     # apply single file
chezmoi update                  # git pull + apply
chezmoi edit ~/.config/fish/config.fish   # open source file for target
chezmoi execute-template < <file>.tmpl    # test-render a template
chezmoi cd                      # cd into this source dir
chezmoi git -- <git-args>       # run git inside source dir
```

## Source naming conventions (chezmoi)

| Prefix | Meaning |
|--------|---------|
| `dot_` | becomes `.` in target (e.g. `dot_config` → `~/.config`) |
| `private_` | applied with mode 600 |
| `.tmpl` suffix | Go template, rendered on apply |
| `run_once_` | shell script run once per machine (tracked by hash) |
| `run_onchange_` | shell script rerun when content changes |

## Template data

Templates use variables from `~/.config/chezmoi/chezmoi.toml` `[data]` section. This file is **machine-local, never committed**.

| Variable | Values |
|----------|--------|
| `.profile` | `"personal"` or `"work"` |
| `.git_name` | display name |
| `.git_email` | email address |
| `.git_signingkey` | SSH public key (empty on work) |

Standard conditionals used throughout:
```
{{ if eq .chezmoi.os "darwin" }}   — macOS only
{{ if eq .chezmoi.os "linux" }}    — Linux only
{{ if eq .profile "personal" }}    — personal profile only
```

## Machines and profiles

| Machine | OS | Profile |
|---------|----|---------|
| Personal Mac | darwin | personal |
| Work Mac | darwin | work |
| Bazzite desktop | linux (bazzite) | personal |
| Linux VMs/servers | linux | personal or work |

## Ghostty config — two target paths

Ghostty uses different paths per OS. Both source files exist; `.chezmoiignore.tmpl` routes correctly:
- macOS: `private_Library/private_Application Support/com.mitchellh.ghostty/config.tmpl`
- Linux: `dot_config/ghostty/config.tmpl`

Work profile excludes ghostty entirely.

## Bootstrap a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/nobleobject/dotfiles/master/bootstrap.sh | bash
```

Script installs chezmoi, prompts to create `~/.config/chezmoi/chezmoi.toml`, inits from repo, shows diff, prompts before applying.

## Package install script

`run_onchange_install-packages.sh.tmpl` detects package manager in order: brew → bazzite (rpm-ostree + binaries) → apt → dnf. Adding a package to the list triggers rerun on next `chezmoi apply`.

Bazzite note: Podman is pre-installed, Docker excluded. Use `ujust setup-virtualization` if Docker needed.
