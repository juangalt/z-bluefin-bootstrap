#!/usr/bin/env bash
# z-bluefin-bootstrap.sh — Bluefin laptop bootstrap
#
# Usage: z-bluefin-bootstrap.sh <command> [options]
# Run:   z-bluefin-bootstrap.sh help

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; DIM=''; RESET=''
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
ok()     { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()   { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()    { echo -e "  ${RED}✘${RESET}  $*" >&2; }
info()   { echo -e "  ${BLUE}ℹ${RESET}  $*"; }
header() { echo -e "\n${BOLD}$*${RESET}"; }
die()    { err "$*"; exit 1; }

have() { command -v "$1" &>/dev/null; }
require() {
  have "$1" || die "Required tool not found: $1"
}

# ── Configuration ─────────────────────────────────────────────────────────────
DOTFILES_REPO="git@github.com:juangalt/z-bluefin-dotfiles.git"
DOTFILES_DIR="$HOME/z-bluefin-dotfiles"

# ── Domain functions ──────────────────────────────────────────────────────────

require_bw_session() {
  [[ -n "${BW_SESSION:-}" ]] || die "BW_SESSION not set — run the login sequence first"
}

bw_login_or_unlock() {
  header "Bitwarden Login"
  require bw
  require jq

  local bw_st
  bw_st=$(bw status 2>/dev/null | jq -r '.status // "unknown"' || echo "error")

  if [[ -n "${BW_SESSION:-}" && ( "$bw_st" == "authenticated" || "$bw_st" == "unlocked" ) ]]; then
    ok "Vault already unlocked (BW_SESSION set)"
  else
    local session
    case "$bw_st" in
      unauthenticated)
        info "Logging in to Bitwarden..."
        session=$(bw login --raw) || die "bw login failed"
        ;;
      locked)
        info "Unlocking Bitwarden vault..."
        session=$(bw unlock --raw) || die "bw unlock failed"
        ;;
      unlocked|authenticated)
        info "Vault already unlocked — refreshing BW_SESSION"
        session=$(bw unlock --raw) || die "bw unlock failed"
        ;;
      *)
        die "Unexpected bw status: ${bw_st}"
        ;;
    esac

    export BW_SESSION="$session"
    ok "BW_SESSION exported"
  fi
}

save_github_key() {
  require bw
  require jq
  require_bw_session

  info "Fetching GitHub SSH key from Bitwarden..."
  local key
  key=$(bw get item "ssh-access service key: github" --session "$BW_SESSION" | jq -r '.sshKey.privateKey') \
    || die "Failed to fetch 'ssh-access service key: github' from Bitwarden"

  [[ -n "$key" ]] || die "GitHub SSH key is empty — check the Bitwarden item"

  mkdir -p "$HOME/.ssh"
  (umask 077; printf '%s\n' "$key" > "$HOME/.ssh/github")
  ok "GitHub SSH key saved to ~/.ssh/github"

  # Ensure SSH uses this key for github.com without needing ssh-agent
  local ssh_config="$HOME/.ssh/config"
  if ! grep -q "Host github.com" "$ssh_config" 2>/dev/null; then
    (umask 077; printf '\nHost github.com\n  IdentityFile ~/.ssh/github\n' >> "$ssh_config")
    ok "SSH config updated for github.com"
  fi
}

load_recovery_key() {
  require bw
  require jq
  require ssh-add
  require ssh-agent
  require_bw_session

  info "Fetching recovery SSH key from Bitwarden..."
  local key
  key=$(bw get item "SSH Key - id_ed25519 - PRIMARY/RECOVERY" --session "$BW_SESSION" | jq -r '.sshKey.privateKey') \
    || die "Failed to fetch 'SSH Key - id_ed25519 - PRIMARY/RECOVERY' from Bitwarden"

  [[ -n "$key" ]] || die "Recovery SSH key is empty — check the Bitwarden item"

  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    eval "$(ssh-agent -s)" > /dev/null
    ok "ssh-agent started"
  fi

  echo "$key" | ssh-add - 2>/dev/null \
    || die "Failed to load recovery SSH key into ssh-agent"
  ok "Recovery SSH key loaded into ssh-agent"
}

clone_and_apply_dotfiles() {
  require git

  if ! have chezmoi; then
    require brew
    info "Installing chezmoi..."
    brew install chezmoi || die "Failed to install chezmoi"
    ok "chezmoi installed"
  fi

  if [[ -d "$DOTFILES_DIR" ]]; then
    info "Dotfiles repo already cloned at $DOTFILES_DIR — pulling latest..."
    git -C "$DOTFILES_DIR" pull || die "git pull failed in $DOTFILES_DIR"
    ok "Dotfiles repo updated"
  else
    info "Cloning dotfiles repo..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR" || die "git clone failed for $DOTFILES_REPO"
    ok "Dotfiles repo cloned to $DOTFILES_DIR"
  fi

  info "Applying dotfiles with chezmoi..."
  chezmoi init --source "$DOTFILES_DIR" --apply || die "chezmoi init --apply failed"
  ok "Dotfiles applied"
}

# ── Command functions ─────────────────────────────────────────────────────────

cmd_help() {
  echo -e "${BOLD}z-bluefin-bootstrap.sh${RESET} — Bluefin laptop bootstrap"
  echo
  echo -e "${BOLD}Usage:${RESET} z-bluefin-bootstrap.sh <command>"
  echo
  echo -e "${BOLD}Commands${RESET} ${DIM}(in typical setup order)${RESET}"
  echo -e "  ${BOLD}status${RESET}              Show current state (SSH, dotfiles, chezmoi drift, brew)"
  echo -e "  ${BOLD}set-hostname${RESET} <name> Set the system hostname via hostnamectl"
  echo -e "  ${BOLD}github${RESET}              Save GitHub SSH key to ~/.ssh/github"
  echo -e "  ${BOLD}dotfiles${RESET}            Clone z-bluefin-dotfiles and apply with chezmoi"
  echo -e "  ${BOLD}all${RESET}                 Run github + dotfiles in one shot"
  echo -e "  ${BOLD}recovery-key${RESET}        Load recovery SSH key into ssh-agent ${DIM}(optional, needs eval)${RESET}"
  echo -e "  ${BOLD}help${RESET}                Show this help"
  echo
  echo -e "Each command handles Bitwarden login/unlock automatically."
  echo
  echo -e "${BOLD}Quick start${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh status"
  echo -e "  ./z-bluefin-bootstrap.sh set-hostname my-laptop"
  echo -e "  ./z-bluefin-bootstrap.sh github"
  echo -e "  ./z-bluefin-bootstrap.sh dotfiles"
  echo
  echo -e "  ${DIM}# Or all at once:${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh all"
  echo
  echo -e "  ${DIM}# Optional — load recovery SSH key into agent:${RESET}"
  echo -e "  eval \"\$(./z-bluefin-bootstrap.sh recovery-key)\""
  echo
  echo -e "${BOLD}Digging deeper${RESET}"
  echo -e "  ${DIM}# See which dotfiles differ from chezmoi source:${RESET}"
  echo -e "  chezmoi status"
  echo -e "  ${DIM}# Show the actual diff for a drifted file:${RESET}"
  echo -e "  chezmoi diff"
  echo -e "  ${DIM}# List missing brew packages:${RESET}"
  echo -e "  brew bundle check --file=$DOTFILES_DIR/Brewfile --no-upgrade --verbose"
  echo -e "  ${DIM}# Re-apply dotfiles without re-cloning:${RESET}"
  echo -e "  chezmoi apply"
}

cmd_status() {
  header "System Status"

  # Hostname
  info "Hostname: $(hostname 2>/dev/null || echo 'unknown')"

  # Tailscale
  if have tailscale; then
    local ts_json
    if ts_json=$(tailscale status --json 2>/dev/null); then
      local ts_host
      ts_host=$(printf '%s' "$ts_json" | jq -r '.Self.HostName // "unknown"')
      ok "Tailscale running — hostname: ${ts_host}"
    else
      warn "Tailscale installed but not running"
    fi
  else
    warn "Tailscale not installed"
  fi

  # GitHub SSH key
  if [[ -f "$HOME/.ssh/github" ]]; then
    local perms
    perms=$(stat -c '%a' "$HOME/.ssh/github" 2>/dev/null || echo "???")
    if [[ "$perms" == "600" ]]; then
      ok "GitHub SSH key installed (~/.ssh/github, mode 600)"
    else
      warn "GitHub SSH key exists but permissions are ${perms} (expected 600)"
    fi
  else
    warn "GitHub SSH key not installed"
  fi

  # SSH config
  if grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
    ok "SSH config has github.com entry"
  else
    warn "No github.com entry in ~/.ssh/config"
  fi

  # Dotfiles
  if [[ -d "$DOTFILES_DIR" ]]; then
    ok "Dotfiles repo present ($DOTFILES_DIR)"
  else
    warn "Dotfiles repo not cloned"
  fi
  if have chezmoi; then
    ok "chezmoi installed"
    local drift
    drift=$(chezmoi status 2>/dev/null | grep -c '.' || true)
    if [[ "$drift" -eq 0 ]]; then
      ok "chezmoi: all managed files in sync"
    else
      warn "chezmoi: ${drift} file(s) out of sync — run 'dotfiles' to re-apply"
    fi
  else
    warn "chezmoi not installed"
  fi

  # Brew packages
  if have brew; then
    local brewfile="$DOTFILES_DIR/Brewfile"
    if [[ -f "$brewfile" ]]; then
      local brew_output
      if brew_output=$(brew bundle check --file="$brewfile" --no-upgrade --verbose 2>/dev/null); then
        ok "Brewfile: all packages installed"
      else
        local missing
        missing=$(printf '%s\n' "$brew_output" | grep -c '^→' || true)
        warn "Brewfile: ${missing} package(s) missing — run 'brew bundle install'"
      fi
    fi
  else
    warn "Homebrew not installed"
  fi
}

cmd_set_hostname() {
  local new_hostname="${1:-}"
  [[ -n "$new_hostname" ]] || die "Usage: z-bluefin-bootstrap.sh set-hostname <name>"
  require hostnamectl
  header "Set Hostname"
  info "Setting hostname to '${new_hostname}'..."
  hostnamectl set-hostname "$new_hostname" \
    || die "hostnamectl set-hostname failed"
  ok "Hostname set to '${new_hostname}'"
}

cmd_github() {
  bw_login_or_unlock
  header "GitHub SSH Key"
  save_github_key
}

cmd_dotfiles() {
  if [[ ! -f "$HOME/.ssh/github" ]]; then
    warn "GitHub SSH key not found — clone may fail. Run 'github' command first."
  fi
  header "Dotfiles"
  clone_and_apply_dotfiles
}

_run_recovery_key_steps() {
  bw_login_or_unlock
  header "Recovery SSH Key"
  load_recovery_key
}

_run_all_steps() {
  bw_login_or_unlock
  header "GitHub SSH Key"
  save_github_key
  header "Dotfiles"
  clone_and_apply_dotfiles
}

# Stdout lines for eval — parent shell sources these to inherit the agent.
_emit_agent_exports() {
  [[ -n "${SSH_AUTH_SOCK:-}" ]] && printf 'export SSH_AUTH_SOCK=%q\n' "$SSH_AUTH_SOCK"
  [[ -n "${SSH_AGENT_PID:-}" ]] && printf 'export SSH_AGENT_PID=%q\n' "$SSH_AGENT_PID"
  echo 'hash -r'
}

# ssh-agent vars live in the subprocess; without eval they're lost on exit.
_warn_agent_subprocess() {
  local cmd="$1" had_agent="$2"
  if [[ -z "$had_agent" ]]; then
    echo
    warn "ssh-agent was started in a subprocess — its variables won't persist."
    info "To keep them in your current shell, run:"
    echo -e "  ${BOLD}eval \"\$(./z-bluefin-bootstrap.sh ${cmd})\"${RESET}"
  fi
}

cmd_recovery_key() {
  local had_agent=$([[ -n "${SSH_AUTH_SOCK:-}" ]] && echo yes || true)

  if [[ ! -t 1 ]]; then
    _run_recovery_key_steps >&2
    _emit_agent_exports
  else
    _run_recovery_key_steps
    _warn_agent_subprocess recovery-key "$had_agent"
  fi
}

cmd_all() {
  _run_all_steps
  echo
  ok "Bootstrap complete."
}

# ── Main dispatcher ───────────────────────────────────────────────────────────

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    status)         cmd_status "$@" ;;
    set-hostname)   cmd_set_hostname "$@" ;;
    github)         cmd_github "$@" ;;
    dotfiles)       cmd_dotfiles "$@" ;;
    all)            cmd_all "$@" ;;
    recovery-key)   cmd_recovery_key "$@" ;;
    help|--help|-h) cmd_help ;;
    *)              err "Unknown command: ${cmd}"; echo; cmd_help; exit 1 ;;
  esac
}

main "$@"
