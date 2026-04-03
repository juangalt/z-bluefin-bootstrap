#!/usr/bin/env bash
# z-bluefin-bootstrap.sh — Bluefin laptop bootstrap
#
# Usage: z-bluefin-bootstrap.sh <command> [options]
# Run:   z-bluefin-bootstrap.sh help

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
ok()     { echo -e "  ${GREEN}✔${RESET}  $*"; }
warn()   { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
err()    { echo -e "  ${RED}✘${RESET}  $*" >&2; }
info()   { echo -e "  ${BLUE}ℹ${RESET}  $*"; }
dim()    { echo -e "       ${DIM}$*${RESET}"; }
header() { echo -e "\n${BOLD}$*${RESET}"; }
die()    { err "$*"; exit 1; }

have() { command -v "$1" &>/dev/null; }
require() {
  have "$1" || die "Required tool not found: $1"
}

# ── Configuration ─────────────────────────────────────────────────────────────
DOTFILES_REPO="git@github.com:juangalt/z-bluefin-dotfiles.git"
DOTFILES_DIR="$HOME/z-bluefin-dotfiles"
GITHUB_KEY_FILE="$HOME/.ssh/github"

# ── Domain functions ──────────────────────────────────────────────────────────

require_bw_session() {
  [[ -n "${BW_SESSION:-}" ]] || die "BW_SESSION not set — run the login sequence first"
}

bw_login_or_unlock() {
  header "Bitwarden Login"
  if ! have bw; then
    require brew
    info "Installing Bitwarden CLI..."
    brew install bitwarden-cli || die "Failed to install bitwarden-cli"
    ok "Bitwarden CLI installed"
  fi
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
  (umask 077; printf '%s\n' "$key" > "$GITHUB_KEY_FILE")
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

ensure_dotfiles_repo() {
  require git
  if [[ -d "$DOTFILES_DIR" ]]; then
    info "Dotfiles repo already cloned at $DOTFILES_DIR — pulling latest..."
    git -C "$DOTFILES_DIR" pull || die "git pull failed in $DOTFILES_DIR"
    ok "Dotfiles repo updated"
  else
    info "Cloning dotfiles repo..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR" || die "git clone failed for $DOTFILES_REPO"
    ok "Dotfiles repo cloned to $DOTFILES_DIR"
  fi
}

clone_and_apply_dotfiles() {
  if ! have chezmoi; then
    require brew
    info "Installing chezmoi..."
    brew install chezmoi || die "Failed to install chezmoi"
    ok "chezmoi installed"
  fi

  ensure_dotfiles_repo

  info "Applying dotfiles with chezmoi..."
  chezmoi init --source "$DOTFILES_DIR" --apply || die "chezmoi init --apply failed"
  ok "Dotfiles applied"
}

install_packages() {
  require brew
  ensure_dotfiles_repo

  local brewfile="$DOTFILES_DIR/Brewfile"
  [[ -f "$brewfile" ]] || die "Brewfile not found at $brewfile"

  info "Installing packages from Brewfile (brew + flatpak)..."
  brew bundle install --file="$brewfile" --no-upgrade \
    || die "brew bundle install failed"
  ok "All packages installed"
}

confirm_or_abort() {
  local prompt="${1:-Continue?}"
  read -rp "  $prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { info "Aborted."; return 1; }
}

git_commit_and_push() {
  local message="$1"
  require git

  git -C "$DOTFILES_DIR" add -A || die "git add failed"

  if git -C "$DOTFILES_DIR" diff --cached --quiet; then
    info "No changes to commit in dotfiles repo"
    return 0
  fi

  git -C "$DOTFILES_DIR" commit -m "$message" || die "git commit failed"
  ok "Committed: $message"

  git -C "$DOTFILES_DIR" push || die "git push failed"
  ok "Pushed to remote"
}

push_packages() {
  require brew

  local brewfile="$DOTFILES_DIR/Brewfile"
  [[ -f "$brewfile" ]] || die "Brewfile not found at $brewfile — run 'install dotfiles' first"

  local tmpfile
  tmpfile=$(mktemp)

  info "Dumping current packages to temp Brewfile..."
  if ! brew bundle dump --file="$tmpfile" --force; then
    rm -f "$tmpfile"
    die "brew bundle dump failed"
  fi

  local diff_output
  if diff_output=$(diff -u --label "current Brewfile" --label "new Brewfile" "$brewfile" "$tmpfile"); then
    rm -f "$tmpfile"
    ok "Brewfile already in sync"
    return 0
  fi

  echo
  printf '%s\n' "$diff_output"
  echo
  if ! confirm_or_abort "Update Brewfile?"; then
    rm -f "$tmpfile"
    return 0
  fi

  cp "$tmpfile" "$brewfile"
  rm -f "$tmpfile"
  ok "Brewfile updated"

  git_commit_and_push "push packages: update Brewfile"
}

push_dotfiles() {
  require chezmoi

  [[ -d "$DOTFILES_DIR" ]] || die "Dotfiles repo not found at $DOTFILES_DIR — run 'install dotfiles' first"

  local diff_output
  diff_output=$(chezmoi diff --reverse 2>&1) \
    || die "chezmoi diff failed"

  if [[ -z "$diff_output" ]]; then
    ok "Dotfiles already in sync"
    return 0
  fi

  echo
  printf '%s\n' "$diff_output"
  echo
  # Detect template files — chezmoi re-add skips them.
  # chezmoi status outputs "XY <path>" where XY is a two-char status code
  # and <path> is relative to the target dir (home). $NF extracts the path.
  local changed_files template_files non_template_count src
  changed_files=$(chezmoi status | awk '{print $NF}')
  template_files=""
  non_template_count=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    src=$(chezmoi source-path "$HOME/$f" 2>/dev/null) || continue
    if [[ "$src" == *.tmpl ]]; then
      template_files+="  $f"$'\n'
    else
      non_template_count=$((non_template_count + 1))
    fi
  done <<< "$changed_files"

  if [[ "$non_template_count" -eq 0 && -n "$template_files" ]]; then
    warn "All changed files are templates — chezmoi re-add cannot update them"
    info "Edit the .tmpl source files in $DOTFILES_DIR, then re-run to push"
    # Offer to commit+push any manual edits already in the dotfiles repo.
    # git_commit_and_push handles the no-op case (nothing to commit).
    confirm_or_abort "Push pending changes in dotfiles repo?" \
      && git_commit_and_push "push dotfiles: update templates"
    return 0
  fi

  confirm_or_abort "Re-add these files?" || return 0

  if [[ -n "$template_files" ]]; then
    warn "These template files will be skipped by re-add:"
    printf '%s' "$template_files"
    info "Update them manually in $DOTFILES_DIR if needed"
  fi

  chezmoi re-add || die "chezmoi re-add failed"
  ok "chezmoi source updated"

  git_commit_and_push "push dotfiles: re-add managed files"
}

# ── Command functions ─────────────────────────────────────────────────────────

cmd_help() {
  echo -e "${BOLD}z-bluefin-bootstrap.sh${RESET} — Bluefin laptop bootstrap"
  echo
  echo -e "${BOLD}Usage:${RESET} z-bluefin-bootstrap.sh <command>"
  echo
  echo -e "${BOLD}Commands${RESET} ${DIM}(in typical setup order)${RESET}"
  echo -e "  ${CYAN}status${RESET} [--details]     Show current state (SSH, dotfiles, chezmoi drift, brew)"
  echo -e "  ${CYAN}set-hostname${RESET} <name>   Set the system hostname via hostnamectl"
  echo -e "  ${CYAN}install github-key${RESET}    Save GitHub SSH key to ~/.ssh/github ${DIM}(requires Bitwarden)${RESET}"
  echo -e "  ${CYAN}install dotfiles${RESET}      Clone z-bluefin-dotfiles and apply config files with chezmoi"
  echo -e "  ${CYAN}install packages${RESET}      Install brew packages and flatpaks from Brewfile"
  echo -e "  ${CYAN}install all${RESET}           Run github-key + dotfiles + packages in one shot ${DIM}(requires Bitwarden)${RESET}"
  echo -e "  ${CYAN}push packages${RESET}         Dump current brew/flatpak state to Brewfile and push"
  echo -e "  ${CYAN}push dotfiles${RESET}         Re-add local dotfile changes to chezmoi source and push"
  echo -e "  ${CYAN}recovery-key${RESET}          Load recovery SSH key into ssh-agent ${DIM}(needs eval, see below)${RESET}"
  echo -e "  ${CYAN}help${RESET}                  Show this help"
  echo
  echo -e "Each command handles Bitwarden login/unlock automatically."
  echo
  echo -e "${BOLD}Quick start${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}status${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}set-hostname${RESET} my-laptop"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}install github-key${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}install dotfiles${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}install packages${RESET}"
  echo
  echo -e "  ${DIM}# Or all at once:${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}install all${RESET}"
  echo
  echo -e "  ${DIM}# Push local changes back to dotfiles repo:${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}push dotfiles${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}push packages${RESET}"
  echo
  echo -e "  ${DIM}# Load recovery SSH key into agent:${RESET}"
  echo -e "  eval \"\$(./z-bluefin-bootstrap.sh ${CYAN}recovery-key${RESET})\""
  echo
  echo -e "${BOLD}Digging deeper${RESET}"
  echo -e "  ${DIM}# See which dotfiles differ from chezmoi source:${RESET}"
  echo -e "  chezmoi status"
  echo -e "  ${DIM}# Show the actual diff for a drifted file:${RESET}"
  echo -e "  chezmoi diff"
  echo -e "  ${DIM}# List missing brew packages:${RESET}"
  echo -e "  brew bundle check --file=$DOTFILES_DIR/Brewfile --no-upgrade --verbose"
  echo -e "  ${DIM}# Show individual package names in status:${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}status --details${RESET}"
  echo -e "  ${DIM}# Re-apply dotfiles without re-cloning:${RESET}"
  echo -e "  chezmoi apply"
}

cmd_status() {
  local show_details=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --details) show_details=true ;;
      *) die "Unknown option for status: $1" ;;
    esac
    shift
  done

  header "System Status"

  # Hostname
  info "Hostname: $(hostname 2>/dev/null || echo 'unknown')"

  # Tailscale
  if have tailscale; then
    local ts_json
    if ts_json=$(tailscale status --json 2>/dev/null); then
      local ts_state ts_host ts_tailnet
      ts_state=$(printf '%s' "$ts_json" | jq -r '.BackendState // "unknown"')
      ts_host=$(printf '%s' "$ts_json" | jq -r '.Self.HostName // "unknown"')
      ts_tailnet=$(printf '%s' "$ts_json" | jq -r '.CurrentTailnet.Name // "unknown"')
      if [[ "$ts_state" == "Running" ]]; then
        ok "Tailscale connected — hostname: ${ts_host}, account: ${ts_tailnet}"
      else
        warn "Tailscale running but not connected to a tailnet"
      fi
    else
      warn "Tailscale installed but not running"
    fi
  else
    warn "Tailscale not installed"
  fi

  header "SSH"

  # GitHub SSH key
  if [[ -f "$GITHUB_KEY_FILE" ]]; then
    local perms
    perms=$(stat -c '%a' "$GITHUB_KEY_FILE" 2>/dev/null || echo "???")
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

  header "Dotfiles"

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
      warn "chezmoi: ${drift} file(s) out of sync — run 'push dotfiles' or 'install dotfiles'"
    fi
  else
    warn "chezmoi not installed"
  fi
  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    local uncommitted unpushed
    uncommitted=$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null | grep -c '.' || true)
    unpushed=$(git -C "$DOTFILES_DIR" log --oneline '@{upstream}..HEAD' 2>/dev/null | grep -c '.' || true)
    if [[ "$uncommitted" -gt 0 ]]; then
      warn "dotfiles repo: ${uncommitted} uncommitted change(s)"
    fi
    if [[ "$unpushed" -gt 0 ]]; then
      warn "dotfiles repo: ${unpushed} unpushed commit(s)"
    fi
    if [[ "$uncommitted" -eq 0 && "$unpushed" -eq 0 ]]; then
      ok "dotfiles repo: clean and up to date with remote"
    fi
  fi

  header "Packages"

  # Brew packages
  if have brew; then
    local brewfile="$DOTFILES_DIR/Brewfile"
    if [[ -f "$brewfile" ]]; then
      # ── Missing: in Brewfile but not installed ──
      local brew_check_output
      if brew_check_output=$(brew bundle check --file="$brewfile" --no-upgrade --verbose 2>/dev/null); then
        ok "Brewfile: all packages installed"
      else
        local missing
        missing=$(printf '%s\n' "$brew_check_output" | grep -c '^→' || true)
        warn "Brewfile: ${missing} package(s) missing — run 'install packages' to install"
        if [[ "$show_details" == true ]]; then
          printf '%s\n' "$brew_check_output" | grep '^→' | while IFS= read -r line; do
            info "  ${line#→ }"
          done
        fi
      fi

      # ── Extras: installed but not in Brewfile ──
      local cleanup_output
      cleanup_output=$(brew bundle cleanup --file="$brewfile" 2>/dev/null) || true
      local extras
      extras=$(printf '%s\n' "$cleanup_output" | grep -cvE '^(Would |Run |$)' || true)
      if [[ "$extras" -eq 0 ]]; then
        ok "Brewfile: no extra packages"
      else
        warn "Brewfile: ${extras} extra package(s) installed but not in Brewfile — run 'push packages' to update"
        if [[ "$show_details" == true ]]; then
          printf '%s\n' "$cleanup_output" | while IFS= read -r line; do
            if [[ "$line" =~ ^Would\  ]]; then
              dim "${line}"
            elif [[ "$line" =~ ^Run\  ]]; then
              continue
            elif [[ -n "$line" ]]; then
              info "  ${line}"
            fi
          done
        fi
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

cmd_install_github_key() {
  bw_login_or_unlock
  header "GitHub SSH Key"
  save_github_key
}

warn_if_no_github_key() {
  [[ -f "$GITHUB_KEY_FILE" ]] || \
    warn "GitHub SSH key not found — clone may fail. Run 'install github-key' first."
}

cmd_install_dotfiles() {
  warn_if_no_github_key
  header "Dotfiles"
  clone_and_apply_dotfiles
}

cmd_install_packages() {
  warn_if_no_github_key
  header "Packages"
  install_packages
}

cmd_install_all() {
  bw_login_or_unlock
  header "GitHub SSH Key"
  save_github_key
  header "Dotfiles"
  clone_and_apply_dotfiles
  header "Packages"
  install_packages
  echo
  ok "Bootstrap complete."
}

cmd_install() {
  local subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    github-key) cmd_install_github_key "$@" ;;
    dotfiles)   cmd_install_dotfiles "$@" ;;
    packages)   cmd_install_packages "$@" ;;
    all)        cmd_install_all "$@" ;;
    *)          die "Usage: z-bluefin-bootstrap.sh install {github-key|dotfiles|packages|all}" ;;
  esac
}

cmd_push_packages() {
  header "Push Packages"
  push_packages
}

cmd_push_dotfiles() {
  header "Push Dotfiles"
  push_dotfiles
}

cmd_push() {
  local subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    packages) cmd_push_packages "$@" ;;
    dotfiles) cmd_push_dotfiles "$@" ;;
    *)        die "Usage: z-bluefin-bootstrap.sh push {packages|dotfiles}" ;;
  esac
}

_run_recovery_key_steps() {
  bw_login_or_unlock
  header "Recovery SSH Key"
  load_recovery_key
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

# ── Main dispatcher ───────────────────────────────────────────────────────────

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    status)         cmd_status "$@" ;;
    set-hostname)   cmd_set_hostname "$@" ;;
    install)        cmd_install "$@" ;;
    push)           cmd_push "$@" ;;
    recovery-key)   cmd_recovery_key "$@" ;;
    help|--help|-h) cmd_help ;;
    *)              err "Unknown command: ${cmd}"; echo; cmd_help; exit 1 ;;
  esac
}

main "$@"
