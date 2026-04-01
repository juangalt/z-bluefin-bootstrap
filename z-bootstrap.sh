#!/usr/bin/env bash
# z-bootstrap.sh — SSH key provisioning via Bitwarden
#
# Usage: z-bootstrap.sh <command> [options]
# Run:   z-bootstrap.sh help

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

# ── Command functions ─────────────────────────────────────────────────────────

cmd_help() {
  cat <<EOF
z-bootstrap.sh — SSH key provisioning via Bitwarden

Usage: z-bootstrap.sh <command>

Commands:
  github            Log in + save GitHub SSH key + configure git identity
  primary           Log in + load primary SSH key into ssh-agent (never on disk)
  all               Run github + primary in sequence
  help              Show this help

If run inside eval, primary and all auto-export ssh-agent variables.

Examples:
  ./z-bootstrap.sh github
  ./z-bootstrap.sh primary
  eval "\$(./z-bootstrap.sh primary)"
  eval "\$(./z-bootstrap.sh all)"
EOF
}

cmd_github() {
  bw_login_or_unlock
  header "GitHub SSH Key"
  save_github_key
  header "Git Identity"
  configure_git_identity
}

cmd_primary() {
  local had_agent=$([[ -n "${SSH_AUTH_SOCK:-}" ]] && echo yes || true)

  if [[ ! -t 1 ]]; then
    bw_login_or_unlock >&2
    header "Primary SSH Key" >&2
    load_primary_key >&2
    [[ -n "${SSH_AUTH_SOCK:-}" ]] && printf 'export SSH_AUTH_SOCK=%q\n' "$SSH_AUTH_SOCK"
    [[ -n "${SSH_AGENT_PID:-}" ]] && printf 'export SSH_AGENT_PID=%q\n' "$SSH_AGENT_PID"
    echo 'hash -r'
  else
    bw_login_or_unlock
    header "Primary SSH Key"
    load_primary_key
    if [[ -z "$had_agent" ]]; then
      echo
      warn "ssh-agent was started in a subprocess — its variables won't persist."
      info "To keep them in your current shell, run:"
      echo -e "  ${BOLD}eval \"\$(./z-bootstrap.sh primary)\"${RESET}"
    fi
  fi
}

cmd_all() {
  local had_agent=$([[ -n "${SSH_AUTH_SOCK:-}" ]] && echo yes || true)

  if [[ ! -t 1 ]]; then
    bw_login_or_unlock >&2
    header "GitHub SSH Key" >&2
    save_github_key >&2
    header "Git Identity" >&2
    configure_git_identity >&2
    header "Primary SSH Key" >&2
    load_primary_key >&2
    printf 'export BW_SESSION=%q\n' "$BW_SESSION"
    [[ -n "${SSH_AUTH_SOCK:-}" ]] && printf 'export SSH_AUTH_SOCK=%q\n' "$SSH_AUTH_SOCK"
    [[ -n "${SSH_AGENT_PID:-}" ]] && printf 'export SSH_AGENT_PID=%q\n' "$SSH_AGENT_PID"
    echo 'hash -r'
  else
    bw_login_or_unlock
    header "GitHub SSH Key"
    save_github_key
    header "Git Identity"
    configure_git_identity
    header "Primary SSH Key"
    load_primary_key
    echo
    ok "All keys provisioned."
    if [[ -z "$had_agent" ]]; then
      warn "ssh-agent was started in a subprocess — its variables won't persist."
      info "To keep them in your current shell, run:"
      echo -e "  ${BOLD}eval \"\$(./z-bootstrap.sh all)\"${RESET}"
    fi
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
    all)            cmd_all "$@" ;;
    *)              err "Unknown command: ${cmd}"; echo; cmd_help; exit 1 ;;
  esac
}

main "$@"
