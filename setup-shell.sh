#!/usr/bin/env bash
#
# abd.dev — zsh + oh-my-zsh + powerlevel10k bootstrap
# One-liner: curl -fsSL https://get.abd.dev/setup-shell.sh | bash
#
# Platform-agnostic (macOS + Linux). Does not install Homebrew or system pkgs
# beyond what's strictly required. Safe to re-run (idempotent).

set -e

REPO_BASE="${ABD_SETUP_BASE:-https://get.abd.dev}"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

c_reset=$'\033[0m'; c_bold=$'\033[1m'
c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'
info()  { printf "%s==>%s %s\n" "$c_blue$c_bold" "$c_reset" "$*"; }
ok()    { printf "%s  ✓%s %s\n" "$c_green" "$c_reset" "$*"; }
warn()  { printf "%s  !%s %s\n" "$c_yellow" "$c_reset" "$*"; }
err()   { printf "%s  ✗%s %s\n" "$c_red" "$c_reset" "$*"; }

need() { command -v "$1" >/dev/null 2>&1; }

backup_file() {
  local f="$1"
  [ -e "$f" ] || return 0
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  cp "$f" "$f.backup-$ts"
  warn "Backed up existing $f → $f.backup-$ts"
}

# ───────────────────────────────────────────── prerequisites

info "Checking prerequisites"
for bin in curl git; do
  if ! need "$bin"; then
    err "'$bin' is required but not installed. Install it and re-run."
    exit 1
  fi
done
ok "curl, git present"

if ! need zsh; then
  err "zsh is not installed. Install it first (macOS ships with zsh; on Linux: 'sudo apt install zsh' or equivalent)."
  exit 1
fi
ok "zsh present ($(zsh --version | awk '{print $2}'))"

# ───────────────────────────────────────────── oh-my-zsh

info "Installing oh-my-zsh"
if [ -d "$HOME/.oh-my-zsh" ]; then
  ok "oh-my-zsh already installed"
else
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ok "oh-my-zsh installed"
fi

# ───────────────────────────────────────────── theme + plugins

clone_or_update() {
  local url="$1" dest="$2" name="$3"
  if [ -d "$dest" ]; then
    ok "$name already present"
  else
    git clone --depth=1 "$url" "$dest" >/dev/null 2>&1
    ok "$name installed"
  fi
}

info "Installing powerlevel10k"
clone_or_update \
  https://github.com/romkatv/powerlevel10k.git \
  "$ZSH_CUSTOM_DIR/themes/powerlevel10k" \
  "powerlevel10k"

info "Installing zsh plugins"
clone_or_update \
  https://github.com/zsh-users/zsh-autosuggestions \
  "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" \
  "zsh-autosuggestions"
clone_or_update \
  https://github.com/zsh-users/zsh-syntax-highlighting \
  "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" \
  "zsh-syntax-highlighting"

# ───────────────────────────────────────────── dotfiles

info "Writing ~/.zshrc"
backup_file "$HOME/.zshrc"
curl -fsSL "$REPO_BASE/zshrc.template" -o "$HOME/.zshrc"
ok "~/.zshrc written"

info "Writing ~/.p10k.zsh"
backup_file "$HOME/.p10k.zsh"
curl -fsSL "$REPO_BASE/p10k.zsh" -o "$HOME/.p10k.zsh"
ok "~/.p10k.zsh written"

# ───────────────────────────────────────────── optional tools

info "Installing nvm (node version manager)"
if [ -d "$HOME/.nvm" ]; then
  ok "nvm already installed"
else
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | PROFILE=/dev/null bash >/dev/null
  ok "nvm installed"
fi

info "Installing uv (python package manager)"
if need uv; then
  ok "uv already installed"
else
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null
  ok "uv installed"
fi

info "Installing entire CLI"
if need entire; then
  ok "entire already installed"
else
  if curl -fsSL https://entire.dev/install.sh 2>/dev/null | sh >/dev/null 2>&1; then
    ok "entire installed"
  else
    warn "entire install script not reachable — install manually if needed"
  fi
fi

# ───────────────────────────────────────────── default shell

info "Setting zsh as default login shell"
zsh_path="$(command -v zsh)"
current_shell="$(dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}')"
[ -z "$current_shell" ] && current_shell="${SHELL:-}"

if [ "$current_shell" = "$zsh_path" ]; then
  ok "zsh is already the default shell ($zsh_path)"
else
  # Ensure zsh is listed in /etc/shells (required by chsh)
  if [ -w /etc/shells ] && ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    echo "$zsh_path" >> /etc/shells
  elif ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    warn "Adding $zsh_path to /etc/shells (may prompt for sudo)"
    echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null || \
      warn "Could not update /etc/shells — you may need to add '$zsh_path' manually"
  fi

  # chsh strategy:
  #   1. try passwordless sudo (works on orbstack, ci, cloud VMs, etc.)
  #   2. try plain chsh (works on macOS with user password)
  #   3. try interactive sudo chsh (works on linux distros needing root)
  # stdin from /dev/tty so interactive prompts work under curl|bash;
  # stderr stays visible so password prompts aren't hidden.
  change_shell() {
    # Probe for passwordless sudo. If it works, use sudo chsh (not -n, so
    # we still inherit any cached creds and avoid edge cases where -n
    # rejects commands that would otherwise run fine).
    if sudo -n true >/dev/null 2>&1; then
      if sudo chsh -s "$zsh_path" "$USER"; then
        return 0
      fi
      warn "Passwordless sudo worked but 'sudo chsh' failed."
    fi

    if [ ! -e /dev/tty ]; then
      warn "No TTY available and passwordless sudo not configured."
      warn "Run manually:  sudo chsh -s \"$zsh_path\" \"$USER\""
      return 1
    fi

    warn "chsh will prompt for your password:"
    if chsh -s "$zsh_path" </dev/tty; then
      return 0
    fi
    warn "Plain chsh failed. Retrying with sudo:"
    if sudo chsh -s "$zsh_path" "$USER" </dev/tty; then
      return 0
    fi
    warn "chsh failed. Run manually:  sudo chsh -s \"$zsh_path\" \"$USER\""
    return 1
  }

  if change_shell; then
    ok "Default shell changed to zsh — open a new terminal to see it"
  fi
fi

# ───────────────────────────────────────────── tool summary

printf "\n%s=== Installed tools summary ===%s\n" "$c_bold" "$c_reset"

summarize() {
  local name="$1" cmd="$2" ver_args="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    local v
    v="$(eval "$cmd $ver_args" 2>/dev/null | head -1)"
    printf "  %s✓%s %-14s %s\n" "$c_green" "$c_reset" "$name" "$v"
  else
    printf "  %s✗%s %-14s %s(not installed)%s\n" "$c_red" "$c_reset" "$name" "$c_yellow" "$c_reset"
  fi
}

summarize "zsh"      zsh    "--version"
summarize "git"      git    "--version"
summarize "curl"     curl   "--version | head -1"
summarize "docker"   docker "--version"
summarize "compose"  "docker compose" "version"
summarize "node"     node   "--version"
summarize "npm"      npm    "--version"
summarize "uv"       uv     "--version"
summarize "python3"  python3 "--version"
summarize "pip"      pip3   "--version"
summarize "go"       go     "version"
summarize "rustc"    rustc  "--version"
summarize "cargo"    cargo  "--version"
summarize "entire"   entire "--version"
summarize "gh"       gh     "--version | head -1"
summarize "jq"       jq     "--version"

# nvm is a shell function, not an executable — check for the file
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  printf "  %s✓%s %-14s (sourced from ~/.nvm/nvm.sh)\n" "$c_green" "$c_reset" "nvm"
else
  printf "  %s✗%s %-14s %s(not installed)%s\n" "$c_red" "$c_reset" "nvm" "$c_yellow" "$c_reset"
fi

printf "\n%sDone.%s Start a new shell or run: %sexec zsh%s\n" \
  "$c_green$c_bold" "$c_reset" "$c_bold" "$c_reset"
printf "If you have secrets/API keys, put them in %s~/.zshrc.local%s (sourced automatically, never committed).\n" \
  "$c_bold" "$c_reset"
