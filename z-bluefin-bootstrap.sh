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
}

configure_git_identity() {
  require bw
  require jq
  require git
  require_bw_session

  info "Fetching git identity from Bitwarden..."
  local item
  item=$(bw get item "git-identity" --session "$BW_SESSION") \
    || die "Failed to fetch 'git-identity' from Bitwarden"

  local name email
  name=$(printf '%s' "$item" | jq -r '.login.username')
  email=$(printf '%s' "$item" | jq -r '.login.password')

  [[ -n "$name" ]] || die "Git user.name is empty — check the 'git-identity' Bitwarden item"
  [[ -n "$email" ]] || die "Git user.email is empty — check the 'git-identity' Bitwarden item"

  git config --global user.name "$name"
  git config --global user.email "$email"
  ok "Git identity configured: $name <$email>"
}

load_primary_key() {
  require bw
  require jq
  require ssh-add
  require ssh-agent
  require_bw_session

  info "Fetching primary SSH key from Bitwarden..."
  local key
  key=$(bw get item "SSH Key - id_ed25519 - PRIMARY/RECOVERY" --session "$BW_SESSION" | jq -r '.sshKey.privateKey') \
    || die "Failed to fetch 'SSH Key - id_ed25519 - PRIMARY/RECOVERY' from Bitwarden"

  [[ -n "$key" ]] || die "Primary SSH key is empty — check the Bitwarden item"

  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    eval "$(ssh-agent -s)" > /dev/null
    ok "ssh-agent started"
  fi

  echo "$key" | ssh-add - 2>/dev/null \
    || die "Failed to load primary SSH key into ssh-agent"
  ok "Primary SSH key loaded into ssh-agent"
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
  cat <<EOF
z-bluefin-bootstrap.sh — Bluefin laptop bootstrap

Usage: z-bluefin-bootstrap.sh <command>

Commands:
  github            Log in + save GitHub SSH key + configure git identity
  primary           Log in + load primary SSH key into ssh-agent (never on disk)
  dotfiles          Clone z-bluefin-dotfiles and apply with chezmoi
  all               Run github + primary + dotfiles in sequence
  status            Show system status (hostname, tailscale, SSH keys, dotfiles)
  set-hostname NAME Set the system hostname via hostnamectl
  help              Show this help

If run inside eval, primary and all auto-export ssh-agent variables.

Examples:
  ./z-bluefin-bootstrap.sh github
  ./z-bluefin-bootstrap.sh primary
  eval "\$(./z-bluefin-bootstrap.sh primary)"
  eval "\$(./z-bluefin-bootstrap.sh all)"
EOF
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

  # Git identity
  local git_name git_email
  git_name=$(git config --global user.name 2>/dev/null || true)
  git_email=$(git config --global user.email 2>/dev/null || true)
  if [[ -n "$git_name" && -n "$git_email" ]]; then
    ok "Git identity: ${git_name} <${git_email}>"
  elif [[ -z "$git_name" && -z "$git_email" ]]; then
    warn "Git identity not configured"
  else
    warn "Git identity partially configured (name=${git_name:-unset}, email=${git_email:-unset})"
  fi

  # Dotfiles
  if [[ -d "$DOTFILES_DIR" ]]; then
    ok "Dotfiles repo present ($DOTFILES_DIR)"
  else
    warn "Dotfiles repo not cloned"
  fi
  if have chezmoi; then
    ok "chezmoi installed"
  else
    warn "chezmoi not installed"
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
  header "Git Identity"
  configure_git_identity
}

cmd_dotfiles() {
  if [[ ! -f "$HOME/.ssh/github" ]]; then
    warn "GitHub SSH key not found — clone may fail. Run 'github' command first."
  fi
  header "Dotfiles"
  clone_and_apply_dotfiles
}

_run_primary_steps() {
  bw_login_or_unlock
  header "Primary SSH Key"
  load_primary_key
}

_run_all_steps() {
  bw_login_or_unlock
  header "GitHub SSH Key"
  save_github_key
  header "Git Identity"
  configure_git_identity
  header "Primary SSH Key"
  load_primary_key
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

cmd_primary() {
  local had_agent=$([[ -n "${SSH_AUTH_SOCK:-}" ]] && echo yes || true)

  if [[ ! -t 1 ]]; then
    _run_primary_steps >&2
    _emit_agent_exports
  else
    _run_primary_steps
    _warn_agent_subprocess primary "$had_agent"
  fi
}

cmd_all() {
  local had_agent=$([[ -n "${SSH_AUTH_SOCK:-}" ]] && echo yes || true)

  if [[ ! -t 1 ]]; then
    _run_all_steps >&2
    printf 'export BW_SESSION=%q\n' "$BW_SESSION"
    _emit_agent_exports
  else
    _run_all_steps
    echo
    ok "Bootstrap complete."
    _warn_agent_subprocess all "$had_agent"
  fi
}

# ── Main dispatcher ───────────────────────────────────────────────────────────

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    help|--help|-h) cmd_help ;;
    github)         cmd_github "$@" ;;
    primary)        cmd_primary "$@" ;;
    dotfiles)       cmd_dotfiles "$@" ;;
    all)            cmd_all "$@" ;;
    status)         cmd_status "$@" ;;
    set-hostname)   cmd_set_hostname "$@" ;;
    *)              err "Unknown command: ${cmd}"; echo; cmd_help; exit 1 ;;
  esac
}

main "$@"
