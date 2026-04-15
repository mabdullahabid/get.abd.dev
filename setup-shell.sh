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

# ───────────────────────────────────────────── detect OS + install zsh

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

install_zsh() {
  case "$OS" in
    macos)
      err "zsh should be preinstalled on macOS but isn't. Install Xcode Command Line Tools or run 'brew install zsh' manually."
      return 1
      ;;
    ubuntu)
      sudo apt-get update -qq && sudo apt-get install -y zsh
      ;;
    *)
      err "Automatic zsh install not supported on '$OS'. Install zsh manually and re-run."
      return 1
      ;;
  esac
}

if ! need zsh; then
  warn "zsh is not installed on this $OS system."
  reply=""
  if [ -e /dev/tty ]; then
    printf "Install zsh now? [Y/n] "
    read -r reply </dev/tty || reply=""
  fi
  case "${reply:-Y}" in
    [nN]|[nN][oO])
      err "Aborted. zsh is required to continue."
      exit 1
      ;;
  esac
  info "Installing zsh"
  install_zsh || exit 1
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
summarize_padded "compose"  "docker compose" "version"
summarize_padded "node"     node   "--version"
summarize_padded "npm"      npm    "--version"
summarize_padded "python3"  python3 "--version"
summarize_padded "pip"      pip3   "--version"
summarize_padded "go"       go     "version"
summarize_padded "rustc"    rustc  "--version"
summarize_padded "cargo"    cargo  "--version"
summarize_padded "gh"       gh     "--version | head -1"
summarize_padded "jq"       jq     "--version"

printf "\n%sDone.%s\n" "$c_green$c_bold" "$c_reset"
printf "If you have secrets/API keys, put them in %s~/.zshrc.local%s (sourced automatically, never committed).\n" \
  "$c_bold" "$c_reset"

# ───────────────────────────────────────────── hand off to zsh
#
# When this script runs under 'curl ... | bash', stdin is the pipe, so
# simply exec'ing zsh would see EOF and exit immediately. Re-attach stdin
# to the controlling terminal via /dev/tty so the new zsh is interactive.
if [ -e /dev/tty ] && [ -t 1 ]; then
  printf "\n%sLaunching zsh...%s\n" "$c_blue$c_bold" "$c_reset"
  exec </dev/tty "$(command -v zsh)" -l
else
  printf "Start a new shell or run: %sexec zsh%s\n" "$c_bold" "$c_reset"
fi
