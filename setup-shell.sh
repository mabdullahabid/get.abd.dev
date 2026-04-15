#!/usr/bin/env bash
#
# abd.dev — thin bootstrap for my chezmoi dotfiles
# One-liner:
#   curl -fsSL get.abd.dev/setup-shell.sh | bash
#
# Installs chezmoi, then runs `chezmoi init --apply mabdullahabid` which
# clones github.com/mabdullahabid/dotfiles and runs the run_once_ scripts
# that set up zsh, oh-my-zsh, powerlevel10k, nvm+node, uv, entire, and
# flip your login shell to zsh.

set -euo pipefail
IFS=$'\n\t'

# --- colors (respect NO_COLOR / non-tty) -----------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'
  GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""; RST=""
fi
log()  { printf '%s==>%s %s\n' "$BLU" "$RST" "$*"; }
ok()   { printf '%s✓%s  %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s!%s  %s\n' "$YEL" "$RST" "$*" >&2; }
die()  { printf '%s✗%s  %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

trap 'die "failed at line $LINENO"' ERR

# --- detect OS -------------------------------------------------------------
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *)      die "unsupported OS: $(uname -s)" ;;
esac
log "detected $OS"

# --- ensure prerequisites (curl, git) --------------------------------------
APT_UPDATED=0
pkg_install() {
  local pkg="$1"
  if [ "$OS" = macos ]; then
    die "$pkg missing — install Xcode Command Line Tools: xcode-select --install"
  fi
  if command -v apt-get >/dev/null 2>&1; then
    if [ "$APT_UPDATED" = 0 ]; then sudo apt-get update -y; APT_UPDATED=1; fi
    sudo apt-get install -y "$pkg"
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "$pkg"
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm "$pkg"
  else
    die "no supported package manager found; please install $pkg manually"
  fi
}

for bin in curl git zsh nano; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    log "installing $bin"
    pkg_install "$bin"
  fi
done
ok "curl + git + zsh + nano present"

# --- install chezmoi -------------------------------------------------------
CHEZMOI_BIN="${HOME}/.local/bin/chezmoi"
if ! command -v chezmoi >/dev/null 2>&1 && [ ! -x "$CHEZMOI_BIN" ]; then
  log "installing chezmoi into ~/.local/bin"
  mkdir -p "${HOME}/.local/bin"
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "${HOME}/.local/bin"
else
  ok "chezmoi already installed"
fi

# Make sure we can call it in this script
if command -v chezmoi >/dev/null 2>&1; then
  CZ=chezmoi
else
  CZ="$CHEZMOI_BIN"
fi

# --- apply dotfiles --------------------------------------------------------
log "applying dotfiles from github.com/mabdullahabid/dotfiles"
# When piped through bash, stdin is the pipe — chezmoi's config prompts
# need an actual tty. Redirect from /dev/tty if it's available.
if [ -e /dev/tty ]; then
  "$CZ" init --apply mabdullahabid </dev/tty
else
  "$CZ" init --apply mabdullahabid
fi

# --- done ------------------------------------------------------------------
printf '\n%s%sAll set.%s Close and reopen your terminal to start your new zsh.\n' "$BOLD" "$GRN" "$RST"
printf '%sTo update later:%s %schezmoi update%s\n' "$DIM" "$RST" "$BOLD" "$RST"
