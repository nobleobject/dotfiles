# Dotfiles: Bootstrap Automation + Zellij Install Fix

**Date:** 2026-06-14
**Status:** Approved

## Background

This chezmoi dotfiles repo runs across a personal Mac, a work Mac, a Bazzite
desktop, and active Linux servers/VMs. Two concrete problems surfaced when
researching highly-starred chezmoi repos and reviewing the current setup:

1. **Bootstrap is too manual.** Machine config (`chezmoi.toml`) is created by a
   block of `read` prompts inside `bootstrap.sh` (lines 28–63). Because no
   `.chezmoi.toml.tmpl` exists, the standard chezmoi one-liner
   (`chezmoi init --apply <repo>`) cannot work — a fresh `chezmoi init` would
   render templates against empty `[data]`. Every new server requires the
   `curl | bash bootstrap.sh` path.

2. **Zellij config ships with no binary.** `dot_config/zellij/config.kdl` is
   deployed to every machine, but `zellij` appears in none of the package
   manager install blocks in `run_onchange_install-packages.sh.tmpl`. Result:
   a multiplexer config with nothing to run it, on every box including servers
   (where a persistent multiplexer is most useful).

### Explicitly out of scope

Considered and rejected during brainstorming:

- **`machine_type` (server/desktop) variable + GUI-package gating.** Verified the
  package script installs only CLI tools plus docker. `colima` is already
  macOS-only; docker is *wanted* on servers; Ghostty is host-terminal config
  only and never installed by the script. No GUI packages install on a server
  today, so there is nothing to gate. YAGNI.
- **Atuin shell-history tool.** Its primary value is cross-machine history sync,
  which the user does not want. Without sync it is only marginally better than
  fish's built-in history search. Skipped.
- **`.chezmoiscripts/` directory reorg.** Pure cosmetic; no functional benefit.
- **ARM/aarch64 arch detection** for binary fallbacks. The existing `eza`
  fallback already hardcodes `x86_64`; zellij's fallback matches that existing
  limitation. Fixing arch detection is a separate concern affecting eza too.

## Goals

- Enable the native chezmoi one-liner for fast, prompt-driven setup on any new
  machine (especially servers).
- Keep a cautious, diff-preview bootstrap path available.
- Make `zellij` actually install wherever its config is deployed.

## Non-goals

- No new tools or dependencies (no atuin, mise, age).
- No change to the personal/work profile model.
- No change to secrets handling (1Password agent stays personal-only; no
  templates read secrets today).

---

## Section 1 — Bootstrap via `.chezmoi.toml.tmpl`

### Change: add `.chezmoi.toml.tmpl` at repo root

`chezmoi init` executes this template to generate the machine-local
`~/.config/chezmoi/chezmoi.toml`. `promptStringOnce` prompts only when the value
is not already present in config, so re-running `init` is idempotent.

```
{{- $profile := promptStringOnce . "profile" "Profile (personal/work)" "personal" -}}
{{- $gitName := promptStringOnce . "git_name" "Git name" -}}
{{- $gitEmail := promptStringOnce . "git_email" "Git email" -}}
{{- $signingKey := "" -}}
{{- if eq $profile "personal" -}}
{{-   $signingKey = promptStringOnce . "git_signingkey" "Git signing key (SSH pubkey, blank to skip)" "" -}}
{{- end -}}
[data]
  profile        = {{ $profile | quote }}
  git_name       = {{ $gitName | quote }}
  git_email      = {{ $gitEmail | quote }}
  git_signingkey = {{ $signingKey | quote }}

[onepassword]
  command = "op"
```

Notes:
- `[data]` keys and the `[onepassword]` stanza reproduce exactly what
  `bootstrap.sh` writes today, so existing templates render unchanged.
- On the work profile, `git_signingkey` is never prompted and renders as `""`,
  matching current behavior (no signing config on work).
- `git_signingkey` line always renders (empty on work) so `chezmoi.toml` shape
  is stable across profiles.

### Change: simplify `bootstrap.sh`

Delete the manual config-creation block (current lines 28–63, the
`# Create chezmoi.toml if missing` section). `chezmoi init` now triggers the
template prompts instead. Retain:

- Step 1: install chezmoi if missing.
- Step 3: `chezmoi init` / pull (now also runs the config template).
- Step 4: diff preview.
- Step 5: apply confirmation.
- Self-delete when run as a downloaded file.

The `/dev/tty` reading concern for the deleted block goes away with it; the
remaining `read` calls (apply confirm) keep their existing `< /dev/tty`.

### Two documented setup paths (README)

- **Fast (native one-liner):**
  ```
  sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply nobleobject
  ```
  Installs chezmoi, clones the repo, runs the config template (prompts inline),
  applies immediately. No diff preview.

- **Cautious (bootstrap script):**
  ```
  curl -fsSL https://raw.githubusercontent.com/nobleobject/dotfiles/master/bootstrap.sh | bash
  ```
  Same prompts, but shows a diff preview and asks before applying.

Update `README.md` and the "Bootstrap a new machine" section of both `CLAUDE.md`
files to document both paths.

---

## Section 2 — Fix zellij install

### Change: add `zellij` to every package block in `run_onchange_install-packages.sh.tmpl`

- **brew** (current line 31): append `zellij` to the install list. Verified
  available: `zellij 0.44.3` (bottled) in homebrew-core.
- **dnf**: append `zellij` to the install list. *Verify at implementation* that
  Fedora repos carry it; if not, apply the binary-fallback pattern below.
- **bazzite**: add `zellij` to the `OSTREE_PKGS` detection loop list. *Verify at
  implementation* it resolves via rpm-ostree (Fedora-based); else binary
  fallback to `~/.local/bin`.
- **apt**: `zellij` is not in Debian/Ubuntu stable repos. Mirror the existing
  `eza` binary-fallback pattern:

  ```sh
  if ! sudo apt-get install -y zellij 2>/dev/null; then
    ZJ_VER=$(curl -fsSL https://api.github.com/repos/zellij-org/zellij/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    curl -fsSL "https://github.com/zellij-org/zellij/releases/download/${ZJ_VER}/zellij-x86_64-unknown-linux-musl.tar.gz" \
      | tar -xz -C /tmp && sudo mv /tmp/zellij /usr/local/bin/
  fi
  ```

Release asset name `zellij-x86_64-unknown-linux-musl.tar.gz` confirmed against
the zellij-org GitHub releases.

### Rerun behavior

Editing `run_onchange_install-packages.sh.tmpl` changes its content hash, so the
script reruns on the next `chezmoi apply` on every machine. Already-provisioned
boxes pick up zellij automatically. All install commands are guarded
(`command -v` checks or idempotent package installs), so reruns are safe.

---

## Testing / verification

- `chezmoi execute-template --init --promptString "Git name=Test" ... < .chezmoi.toml.tmpl`
  renders valid TOML for both `personal` and `work` profiles.
- Confirm `git_signingkey` renders `""` on work, real key on personal.
- `chezmoi diff` on an existing machine shows no spurious changes from the
  config-template addition (data values unchanged).
- After applying the package-script change, `command -v zellij` succeeds on a
  Linux test box (or VM) and on macOS.
- `bootstrap.sh` still completes end-to-end (install → init prompts → diff →
  apply) on a clean machine.

## Files touched

| File | Change |
|------|--------|
| `.chezmoi.toml.tmpl` | New — config template with `promptStringOnce` |
| `bootstrap.sh` | Remove manual config block (lines 28–63) |
| `run_onchange_install-packages.sh.tmpl` | Add `zellij` to brew/dnf/bazzite/apt |
| `README.md` | Document fast + cautious setup paths |
| `CLAUDE.md` (repo) | Update bootstrap section |

Note: `~/CLAUDE.md` (the global, non-repo copy) carries the same bootstrap text.
It lives outside this repo and is not committed here — update it manually/separately
if keeping the two in sync matters.
