#!/usr/bin/env bash
#
# abd.dev — zsh + oh-my-zsh + powerlevel10k bootstrap
# One-liner:
#   curl -fsSL https://get.abd.dev/setup-shell.sh | bash
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

# ───────────────────────────────────────────── detect OS

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}${ID_LIKE:-}" in
          *ubuntu*|*debian*) echo "ubuntu" ;;
          *) echo "linux-other" ;;
        esac
      else
        echo "linux-other"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

OS="$(detect_os)"
info "Detected system: $OS"

# ───────────────────────────────────────────── prerequisites (curl, git, zsh)
#
# Any of these may be missing on a fresh ubuntu container. Prompt once
# (default Yes) and install via the platform package manager.

APT_UPDATED=0
pkg_install() {
  local pkg="$1"
  case "$OS" in
    ubuntu)
      if [ "$APT_UPDATED" -eq 0 ]; then
        sudo apt-get update -qq
        APT_UPDATED=1
      fi
      sudo apt-get install -y "$pkg"
      ;;
    macos)
      err "'$pkg' is missing on macOS. Install Xcode Command Line Tools: xcode-select --install"
      return 1
      ;;
    *)
      err "Automatic install of '$pkg' not supported on '$OS'. Install it manually and re-run."
      return 1
      ;;
  esac
}

ensure_bin() {
  local bin="$1" pkg="${2:-$1}"
  if need "$bin"; then
    ok "$bin present"
    return 0
  fi
  warn "$bin is not installed on this $OS system."
  local reply=""
  if [ -e /dev/tty ]; then
    printf "Install %s now? [Y/n] " "$pkg"
    read -r reply </dev/tty || reply=""
  fi
  case "${reply:-Y}" in
    [nN]|[nN][oO])
      err "Aborted. '$bin' is required to continue."
      exit 1
      ;;
  esac
  info "Installing $pkg"
  pkg_install "$pkg" || exit 1
  if ! need "$bin"; then
    err "Install of '$pkg' appeared to succeed but '$bin' is still not on PATH."
    exit 1
  fi
  ok "$bin installed"
}

info "Checking prerequisites"
ensure_bin curl
ensure_bin git
ensure_bin zsh
ok "zsh version: $(zsh --version | awk '{print $2}')"

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

# Source nvm into this script so we can install node. nvm is a shell
# function, not a binary — set NVM_DIR and source nvm.sh.
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1

info "Installing latest LTS node via nvm"
if command -v nvm >/dev/null 2>&1; then
  if nvm install --lts >/dev/null 2>&1; then
    nvm use --lts >/dev/null 2>&1 || true
    nvm alias default 'lts/*' >/dev/null 2>&1 || true
    ok "node $(node --version 2>/dev/null) + npm $(npm --version 2>/dev/null)"
  else
    warn "nvm install --lts failed"
  fi
else
  warn "nvm not loaded in this shell — run 'nvm install --lts' manually after opening a new terminal"
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
  # Download to a tempfile first so we can verify the fetch actually
  # succeeded (piping curl | sh masks a 404 because sh happily runs empty
  # input and returns 0).
  entire_tmp="$(mktemp)"
  if curl -fsSL https://entire.io/install.sh -o "$entire_tmp" && [ -s "$entire_tmp" ]; then
    if bash "$entire_tmp" >/dev/null 2>&1; then
      ok "entire installed"
    else
      warn "entire install script ran but exited non-zero"
    fi
  else
    warn "entire install script not reachable at https://entire.io/install.sh"
  fi
  rm -f "$entire_tmp"
fi

# Make uv / entire / anything else in ~/.local/bin visible to the rest
# of this script (including the summary below) without requiring a new
# shell. Both installers drop binaries there.
if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi
# shellcheck disable=SC1091
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env" >/dev/null 2>&1 || true

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

check_dir() {
  local name="$1" path="$2" note="$3"
  if [ -d "$path" ]; then
    printf "  %s✓%s %-22s %s\n" "$c_green" "$c_reset" "$name" "$note"
  else
    printf "  %s✗%s %-22s %s(missing)%s\n" "$c_red" "$c_reset" "$name" "$c_yellow" "$c_reset"
  fi
}

printf "%s-- installed by this script --%s\n" "$c_bold" "$c_reset"
summarize_padded() {
  local name="$1" cmd="$2" ver_args="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    local v
    v="$(eval "$cmd $ver_args" 2>/dev/null | head -1)"
    printf "  %s✓%s %-22s %s\n" "$c_green" "$c_reset" "$name" "$v"
  else
    printf "  %s✗%s %-22s %s(not installed)%s\n" "$c_red" "$c_reset" "$name" "$c_yellow" "$c_reset"
  fi
}
summarize_padded "zsh"                  zsh    "--version"
check_dir        "oh-my-zsh"            "$HOME/.oh-my-zsh" "(framework)"
check_dir        "powerlevel10k"        "$ZSH_CUSTOM_DIR/themes/powerlevel10k" "(theme)"
check_dir        "zsh-autosuggestions"  "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" "(plugin)"
check_dir        "zsh-syntax-highlight" "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" "(plugin)"
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  printf "  %s✓%s %-22s %s\n" "$c_green" "$c_reset" "nvm" "(sourced from ~/.nvm/nvm.sh)"
else
  printf "  %s✗%s %-22s %s(not installed)%s\n" "$c_red" "$c_reset" "nvm" "$c_yellow" "$c_reset"
fi
summarize_padded "uv"       uv     "--version"
summarize_padded "entire"   entire "--version"

printf "\n%s-- other common tools --%s\n" "$c_bold" "$c_reset"
summarize_padded "git"      git    "--version"
summarize_padded "curl"     curl   "--version | head -1"
summarize_padded "docker"   docker "--version"

# Docker Compose is a subcommand, not a standalone binary — check
# separately by actually running `docker compose version`.
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  cv="$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null | head -1)"
  printf "  %s✓%s %-22s Docker Compose v%s\n" "$c_green" "$c_reset" "compose" "$cv"
else
  printf "  %s✗%s %-22s %s(not installed)%s\n" "$c_red" "$c_reset" "compose" "$c_yellow" "$c_reset"
fi

summarize_padded "node"     node   "--version"
summarize_padded "npm"      npm    "--version"
summarize_padded "python3"  python3 "--version"
summarize_padded "pip"      pip3   "--version"
summarize_padded "go"       go     "version"
summarize_padded "rustc"    rustc  "--version"
summarize_padded "cargo"    cargo  "--version"
summarize_padded "gh"       gh     "--version | head -1"
summarize_padded "jq"       jq     "--version"

printf "\n%sDone.%s\n\n" "$c_green$c_bold" "$c_reset"
printf "%sNext step:%s close this terminal and open a new one.\n" "$c_bold" "$c_reset"
printf "Your new shell will be zsh with powerlevel10k, and all PATH changes will be active.\n\n"
printf "If you have secrets/API keys, put them in %s~/.zshrc.local%s — sourced automatically, never committed.\n" \
  "$c_bold" "$c_reset"
