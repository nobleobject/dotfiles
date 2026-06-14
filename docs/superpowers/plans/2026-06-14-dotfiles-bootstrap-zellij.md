# Dotfiles Bootstrap Automation + Zellij Install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the native `chezmoi init --apply` one-liner for fast machine setup, and make `zellij` install on every machine where its config is deployed.

**Architecture:** Add a `.chezmoi.toml.tmpl` config template so `chezmoi init` prompts for machine data (replacing the manual `read` block in `bootstrap.sh`). Add `zellij` to every package-manager block in the install script, using the existing `eza` GitHub-binary fallback pattern for apt where no repo package exists.

**Tech Stack:** chezmoi (Go text/template), POSIX `sh` run scripts, `bash` bootstrap script, Homebrew / apt / dnf / rpm-ostree.

**Verification approach:** There is no unit-test harness in this repo. "Tests" here are concrete verification commands — `chezmoi execute-template --init`, `sh -n` syntax checks, `shellcheck`, and `command -v` — run before and after each change. Each task: verify the gap exists, make the change, verify it's closed, commit.

**Spec:** `docs/superpowers/specs/2026-06-14-dotfiles-bootstrap-zellij-design.md`

**Note on commits:** Per repo convention, every commit message ends with:
```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `.chezmoi.toml.tmpl` | Generate machine-local `chezmoi.toml` on `init` via prompts | Create |
| `bootstrap.sh` | Install chezmoi → init → diff → confirm apply (no longer writes config) | Modify |
| `run_onchange_install-packages.sh.tmpl` | Install CLI tools incl. zellij across pkg managers | Modify |
| `README.md` | Document fast + cautious setup paths | Modify |
| `CLAUDE.md` | Update bootstrap section | Modify |

---

## Task 1: Add `.chezmoi.toml.tmpl` config template

**Files:**
- Create: `.chezmoi.toml.tmpl`

- [ ] **Step 1: Verify the gap — no config template exists**

Run:
```bash
ls -la .chezmoi.toml.tmpl 2>&1
```
Expected: `No such file or directory`. This confirms `chezmoi init` cannot auto-generate config today.

- [ ] **Step 2: Create the config template**

Create `.chezmoi.toml.tmpl` with exactly this content:

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

- [ ] **Step 3: Verify it renders valid TOML for the personal profile**

Run:
```bash
chezmoi execute-template --init \
  --promptString "profile=personal" \
  --promptString "git_name=Test User" \
  --promptString "git_email=test@example.com" \
  --promptString "git_signingkey=ssh-ed25519 AAAATEST" \
  < .chezmoi.toml.tmpl
```
Expected output (exactly):
```
[data]
  profile        = "personal"
  git_name       = "Test User"
  git_email      = "test@example.com"
  git_signingkey = "ssh-ed25519 AAAATEST"

[onepassword]
  command = "op"
```

- [ ] **Step 4: Verify it renders valid TOML for the work profile (no signing key)**

Run:
```bash
chezmoi execute-template --init \
  --promptString "profile=work" \
  --promptString "git_name=Work User" \
  --promptString "git_email=work@example.com" \
  < .chezmoi.toml.tmpl
```
Expected: `git_signingkey = ""` and no prompt error for the missing signing key. Output:
```
[data]
  profile        = "work"
  git_name       = "Work User"
  git_email      = "work@example.com"
  git_signingkey = ""

[onepassword]
  command = "op"
```

- [ ] **Step 5: Confirm no spurious diff on the current machine**

Run:
```bash
chezmoi diff
```
Expected: no changes related to `chezmoi.toml` data (the live machine's existing `~/.config/chezmoi/chezmoi.toml` already holds these values, so `promptStringOnce` reads them rather than prompting). If chezmoi warns the config template changed, that is expected and harmless — note it and continue.

- [ ] **Step 6: Commit**

```bash
git add .chezmoi.toml.tmpl
git commit -m "feat: add .chezmoi.toml.tmpl for prompt-driven init

Enables the native 'chezmoi init --apply nobleobject' one-liner.
promptStringOnce makes re-init idempotent. Reproduces the exact
[data] keys and [onepassword] stanza bootstrap.sh writes today.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Remove manual config block from `bootstrap.sh`

**Files:**
- Modify: `bootstrap.sh` (delete the config-creation section, currently lines 28–63)

- [ ] **Step 1: Verify current behavior — bootstrap writes config itself**

Run:
```bash
grep -n "Create chezmoi.toml if missing" bootstrap.sh
```
Expected: matches around line 28. This block is now redundant — `chezmoi init` (Task 1) handles config generation.

- [ ] **Step 2: Delete the config-creation block**

Remove the entire section from the comment header
`# ── 2. Create chezmoi.toml if missing ...` through the closing `fi` and blank line, up to (but not including) the `# ── 3. Init or update ...` header.

The deleted block is exactly:

```bash
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

```

After deletion, the `# ── 3. Init or update ...` section follows directly after the `# ── 1. Install chezmoi ...` section's closing `fi`.

- [ ] **Step 3: Add a note that init now handles config**

Immediately above the `# ── 3. Init or update ...` header, add this brief comment so the flow reads clearly:

```bash
# chezmoi init (below) runs .chezmoi.toml.tmpl, which prompts for profile,
# git name/email, and signing key, then writes ~/.config/chezmoi/chezmoi.toml.
```

- [ ] **Step 4: Remove the now-unused CHEZMOI_CONFIG variable**

The `CHEZMOI_CONFIG` variable (declared near the top) is no longer referenced. Verify and remove its declaration line:

```bash
grep -n 'CHEZMOI_CONFIG' bootstrap.sh
```
If the only remaining match is the declaration `CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"`, delete that line. If any other references remain, leave it and note them.

- [ ] **Step 5: Syntax-check the script**

Run:
```bash
bash -n bootstrap.sh && echo "SYNTAX OK"
```
Expected: `SYNTAX OK`.

- [ ] **Step 6: Lint (if shellcheck available)**

Run:
```bash
command -v shellcheck >/dev/null 2>&1 && shellcheck bootstrap.sh || echo "shellcheck not installed — skipping"
```
Expected: no errors, or the skip message. Fix any new warnings introduced by the edit (unused-variable warnings for `CHEZMOI_CONFIG` mean Step 4 was missed).

- [ ] **Step 7: Commit**

```bash
git add bootstrap.sh
git commit -m "refactor: drop manual config block from bootstrap.sh

chezmoi init now runs .chezmoi.toml.tmpl to generate config via
prompts, so the hand-rolled read/printf block is redundant. Script
keeps install -> init -> diff -> confirm-apply flow.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Add `zellij` to brew, dnf, and bazzite blocks

**Files:**
- Modify: `run_onchange_install-packages.sh.tmpl`

- [ ] **Step 1: Verify the gap — zellij config ships but binary is never installed**

Run:
```bash
ls dot_config/zellij/config.kdl && grep -c zellij run_onchange_install-packages.sh.tmpl
```
Expected: config file exists, and grep count is `0`. Confirms the deployed-config-no-binary bug.

- [ ] **Step 2: Add zellij to the brew install list**

Find this line:
```
    brew install fish starship micro croc fzf ripgrep eza btop tree jq gh wget neovim ranger
```
Replace with (append `zellij` at the end):
```
    brew install fish starship micro croc fzf ripgrep eza btop tree jq gh wget neovim ranger zellij
```

- [ ] **Step 3: Add zellij to the bazzite OSTREE_PKGS loop**

Find this line:
```
    for pkg in fish fzf ripgrep eza btop tree jq wget neovim ranger; do
```
Replace with (append `zellij`):
```
    for pkg in fish fzf ripgrep eza btop tree jq wget neovim ranger zellij; do
```

- [ ] **Step 4: Add zellij to the dnf install list**

Find this line:
```
    sudo dnf install -y fish fzf ripgrep eza btop tree jq wget neovim croc ranger
```
Replace with (append `zellij`):
```
    sudo dnf install -y fish fzf ripgrep eza btop tree jq wget neovim croc ranger zellij
```

- [ ] **Step 5: Verify zellij now appears in three blocks**

Run:
```bash
grep -n zellij run_onchange_install-packages.sh.tmpl
```
Expected: three matches — one each in the brew, bazzite-loop, and dnf lines. (apt is handled in Task 4.)

- [ ] **Step 6: Template-render check**

Run:
```bash
chezmoi execute-template < run_onchange_install-packages.sh.tmpl > /tmp/install-rendered.sh && bash -n /tmp/install-rendered.sh && echo "RENDER + SYNTAX OK"
```
Expected: `RENDER + SYNTAX OK` (renders against the current machine's profile/OS and is valid shell).

- [ ] **Step 7: Commit**

```bash
git add run_onchange_install-packages.sh.tmpl
git commit -m "fix: install zellij via brew, dnf, and bazzite

zellij config (dot_config/zellij/config.kdl) was deployed everywhere
but the binary was never installed. Add it to the package lists.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Add zellij to apt with GitHub-binary fallback

**Files:**
- Modify: `run_onchange_install-packages.sh.tmpl` (apt block)

zellij is not in Debian/Ubuntu stable repos, so mirror the existing `eza` fallback: try the apt package, fall back to the GitHub release tarball.

- [ ] **Step 1: Locate the eza fallback in the apt block for reference**

Run:
```bash
grep -n "eza not in apt repos" run_onchange_install-packages.sh.tmpl
```
Expected: one match inside the `apt)` case. The new zellij block goes immediately after the eza fallback's closing `fi`.

- [ ] **Step 2: Insert the zellij fallback after the eza fallback block**

The eza fallback currently ends with:
```sh
      curl -fsSL "https://github.com/eza-community/eza/releases/download/${EZA_VER}/eza_x86_64-unknown-linux-gnu.tar.gz" \
        | tar -xz -C /tmp && sudo mv /tmp/eza /usr/local/bin/
    fi
```

Immediately after that `fi`, add:
```sh

    # zellij not in Debian/Ubuntu stable repos — fall back to GitHub release
    if ! sudo apt-get install -y zellij 2>/dev/null; then
      ZJ_VER=$(curl -fsSL https://api.github.com/repos/zellij-org/zellij/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
      curl -fsSL "https://github.com/zellij-org/zellij/releases/download/${ZJ_VER}/zellij-x86_64-unknown-linux-musl.tar.gz" \
        | tar -xz -C /tmp && sudo mv /tmp/zellij /usr/local/bin/
    fi
```

- [ ] **Step 3: Verify the apt fallback was added**

Run:
```bash
grep -c zellij run_onchange_install-packages.sh.tmpl
```
Expected: `8` — three from Task 3 (brew, bazzite loop, dnf) plus five new lines in the apt block (comment, `apt-get install` line, `ZJ_VER` curl, download-URL curl, and the `mv /tmp/zellij` line). Confirm the apt block specifically:
```bash
grep -n "apt-get install -y zellij" run_onchange_install-packages.sh.tmpl
```
Expected: one match, inside the `apt)` case after the eza fallback.

- [ ] **Step 4: Render + syntax check**

Run:
```bash
chezmoi execute-template < run_onchange_install-packages.sh.tmpl > /tmp/install-rendered.sh && bash -n /tmp/install-rendered.sh && echo "RENDER + SYNTAX OK"
```
Expected: `RENDER + SYNTAX OK`.

- [ ] **Step 5: shellcheck the rendered script (if available)**

Run:
```bash
command -v shellcheck >/dev/null 2>&1 && shellcheck -S warning /tmp/install-rendered.sh || echo "shellcheck not installed — skipping"
```
Expected: no new errors versus the eza pattern (SC2086 etc. already present in the file are acceptable if they match existing style), or the skip message.

- [ ] **Step 6: Commit**

```bash
git add run_onchange_install-packages.sh.tmpl
git commit -m "fix: install zellij on apt via GitHub-binary fallback

zellij is absent from Debian/Ubuntu stable repos; mirror the eza
fallback to pull the musl release tarball into /usr/local/bin.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Document both setup paths in README.md

**Files:**
- Modify: `README.md:5-15`

- [ ] **Step 1: Replace the Setup section**

Find the current Setup section:
```markdown
## Setup

```bash
curl -fsSL https://raw.githubusercontent.com/nobleobject/dotfiles/master/bootstrap.sh | bash
```

The script will:
1. Install chezmoi (via Homebrew on macOS, or directly to `~/.local/bin` on Linux)
2. Prompt for profile (`personal` / `work`), git name, email, and optional SSH signing key
3. Show a diff preview
4. Ask before applying anything
```

Replace with:
```markdown
## Setup

**Fast (native one-liner)** — installs chezmoi, clones, prompts, and applies:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply nobleobject
```

`.chezmoi.toml.tmpl` prompts for profile (`personal` / `work`), git name,
email, and optional SSH signing key, then applies immediately.

**Cautious (bootstrap script)** — same prompts, but shows a diff preview and
asks before applying:

```bash
curl -fsSL https://raw.githubusercontent.com/nobleobject/dotfiles/master/bootstrap.sh | bash
```

The script will:
1. Install chezmoi (via Homebrew on macOS, or directly to `~/.local/bin` on Linux)
2. Run `chezmoi init`, which prompts for profile, git name, email, and optional SSH signing key
3. Show a diff preview
4. Ask before applying anything
```

- [ ] **Step 2: Verify the edit rendered correctly**

Run:
```bash
sed -n '1,30p' README.md
```
Expected: both "Fast" and "Cautious" subsections present, native one-liner shown first.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document fast one-liner and cautious bootstrap paths

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Update CLAUDE.md bootstrap section

**Files:**
- Modify: `CLAUDE.md:67-73`

- [ ] **Step 1: Replace the bootstrap section**

Find:
```markdown
## Bootstrap a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/nobleobject/dotfiles/master/bootstrap.sh | bash
```

Script installs chezmoi, prompts to create `~/.config/chezmoi/chezmoi.toml`, inits from repo, shows diff, prompts before applying.
```

Replace with:
```markdown
## Bootstrap a new machine

**Fast (native one-liner):**
```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply nobleobject
```

**Cautious (diff preview before apply):**
```bash
curl -fsSL https://raw.githubusercontent.com/nobleobject/dotfiles/master/bootstrap.sh | bash
```

Config (`~/.config/chezmoi/chezmoi.toml`) is generated by `.chezmoi.toml.tmpl`
on `chezmoi init` — it prompts (via `promptStringOnce`) for profile, git
name/email, and signing key. `bootstrap.sh` no longer writes config itself; it
installs chezmoi, inits (triggering the prompts), shows a diff, and confirms
before applying.
```

- [ ] **Step 2: Verify**

Run:
```bash
sed -n '67,82p' CLAUDE.md
```
Expected: both paths documented, mention of `.chezmoi.toml.tmpl` and `promptStringOnce`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md bootstrap section for .chezmoi.toml.tmpl

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] **Step 1: Full template render across the whole source tree**

Run:
```bash
chezmoi diff
```
Expected: changes limited to the files this plan touches. No unexpected modifications to managed home-dir files.

- [ ] **Step 2: Confirm zellij coverage**

Run:
```bash
grep -n zellij run_onchange_install-packages.sh.tmpl
```
Expected: 8 matching lines — brew, bazzite loop, dnf, and the five-line apt fallback block.

- [ ] **Step 3: Confirm git tree is clean and all work committed**

Run:
```bash
git status --short
```
Expected: empty output.

---

## Notes for the implementer

- **dnf/bazzite verification:** The plan assumes Fedora repos carry `zellij`. If a real dnf/bazzite machine reports "no package zellij available," add the same GitHub-binary fallback used for apt (Task 4) to that block. This cannot be verified from macOS — flag it if it surfaces during a real Linux apply.
- **ARM servers:** The apt/eza/zellij fallbacks hardcode `x86_64`. aarch64 boxes need the `aarch64`/`arm` tarball variants. Out of scope here (the existing eza fallback has the same limitation); note it if you hit an ARM server.
- **`onepassword` stanza on servers:** `command = "op"` only declares which command chezmoi would call if a template read a secret. No template does today, so it is inert on machines without 1Password. Leave it.
