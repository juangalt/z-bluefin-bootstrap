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

# dconf area-to-path mapping — update when adding a new gnome/*.ini file.
# desktop.ini excluded: root path "/" cannot be round-tripped with dconf dump.
declare -gA DCONF_MAP=(
  [ptyxis]="/org/gnome/Ptyxis/"
  [keybindings]="/org/gnome/settings-daemon/plugins/media-keys/"
  [extensions]="/org/gnome/shell/"
)
mapfile -t DCONF_AREAS < <(printf '%s\n' "${!DCONF_MAP[@]}" | sort)

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
  [[ "${_DOTFILES_ENSURED:-}" == true ]] && return 0
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
  _DOTFILES_ENSURED=true
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

install_dconf() {
  require dconf
  ensure_dotfiles_repo

  local gnome_dir="$DOTFILES_DIR/gnome"
  [[ -d "$gnome_dir" ]] || die "GNOME settings dir not found at $gnome_dir"

  classify_dconf_drift
  if [[ "$DCONF_DRIFT_COUNT" -eq 0 ]]; then
    ok "GNOME settings already in sync"
    return 0
  fi

  local area dconf_path ini_file
  while IFS= read -r area; do
    [[ -n "$area" ]] || continue
    dconf_path="${DCONF_MAP[$area]}"
    ini_file="$gnome_dir/${area}.ini"
    info "Loading ${area} settings (${dconf_path})..."
    dconf load "$dconf_path" < "$ini_file" || die "dconf load failed for ${area}"
    ok "${area} applied"
  done <<< "$DCONF_DRIFTED_AREAS"

  ok "GNOME settings applied (${DCONF_DRIFT_COUNT} area(s) updated)"
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

# Classify chezmoi drift into template vs non-template files.
# Sets global variables:
#   TEMPLATE_FILES / TEMPLATE_COUNT / TEMPLATE_SOURCE_FILES
#   NON_TEMPLATE_FILES / NON_TEMPLATE_COUNT
# Returns 1 if chezmoi status reports no drift at all.
classify_chezmoi_drift() {
  local status_output
  status_output=$(chezmoi status 2>/dev/null) || true
  TEMPLATE_FILES=""
  TEMPLATE_SOURCE_FILES=""
  NON_TEMPLATE_FILES=""
  TEMPLATE_COUNT=0
  NON_TEMPLATE_COUNT=0

  [[ -z "$status_output" ]] && return 1

  local line f src
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    f="${line:3}"
    src=$(chezmoi source-path "$HOME/$f" 2>/dev/null) || src=""
    if [[ "$src" == *.tmpl ]]; then
      TEMPLATE_FILES+="$f"$'\n'
      TEMPLATE_SOURCE_FILES+="$src"$'\n'
      TEMPLATE_COUNT=$((TEMPLATE_COUNT + 1))
    else
      NON_TEMPLATE_FILES+="$f"$'\n'
      NON_TEMPLATE_COUNT=$((NON_TEMPLATE_COUNT + 1))
    fi
  done <<< "$status_output"
}

# Check whether a single dconf area has drifted from its saved .ini file.
# Returns 0 if drift found, 1 if all keys match.
_dconf_area_has_drift() {
  ! diff -q "$2" <(_generate_updated_dconf_ini "$1" "$2") >/dev/null 2>&1
}

# Generate an updated .ini file by reading live dconf values for each tracked key.
# Preserves the file's section structure and key set — only values change.
# $1 = dconf base path, $2 = path to .ini file
# Outputs updated content to stdout.
_generate_updated_dconf_ini() {
  local base_path="$1" ini_file="$2"
  local section="" key val full_path live_val

  while IFS= read -r line; do
    if [[ "$line" =~ ^\[(.+)\]$ ]]; then
      section="${BASH_REMATCH[1]}"
      printf '%s\n' "$line"
      continue
    fi
    if [[ -z "$line" || "$line" != *=* ]]; then
      printf '%s\n' "$line"
      continue
    fi
    key="${line%%=*}"
    val="${line#*=}"

    if [[ "$base_path" == "/" ]]; then
      full_path="/${section}/${key}"
    elif [[ "$section" == "/" ]]; then
      full_path="${base_path}${key}"
    else
      full_path="${base_path}${section}/${key}"
    fi

    live_val=$(dconf read "$full_path" 2>/dev/null) || live_val=""
    if [[ -n "$live_val" ]]; then
      printf '%s=%s\n' "$key" "$live_val"
    else
      printf '%s\n' "$line"
    fi
  done < "$ini_file"
}

# Classify dconf drift across all tracked GNOME setting areas.
# Sets global variables:
#   DCONF_DRIFTED_AREAS / DCONF_DRIFT_COUNT / DCONF_TOTAL
# Returns 1 if gnome/ dir is missing.
classify_dconf_drift() {
  DCONF_DRIFTED_AREAS=""
  DCONF_DRIFT_COUNT=0
  DCONF_TOTAL=0

  local gnome_dir="$DOTFILES_DIR/gnome"
  [[ -d "$gnome_dir" ]] || return 1

  local area dconf_path ini_file
  for area in "${DCONF_AREAS[@]}"; do
    dconf_path="${DCONF_MAP[$area]}"
    ini_file="$gnome_dir/${area}.ini"
    [[ -f "$ini_file" ]] || continue
    DCONF_TOTAL=$((DCONF_TOTAL + 1))
    if _dconf_area_has_drift "$dconf_path" "$ini_file"; then
      DCONF_DRIFTED_AREAS+="$area"$'\n'
      DCONF_DRIFT_COUNT=$((DCONF_DRIFT_COUNT + 1))
    fi
  done
}

# Filter unified diff output to show only diffs for files in a given list.
# $1 = full diff output (from chezmoi diff --reverse)
# $2 = newline-separated list of target paths to include
_show_diff_for_files() {
  local full_diff="$1" file_list="$2"
  local line current_chunk="" current_path="" show=false

  while IFS= read -r line; do
    if [[ "$line" == "diff --git "* ]]; then
      [[ "$show" == true && -n "$current_chunk" ]] && printf '%s\n' "$current_chunk"
      current_path="${line##* b/}"
      current_chunk="$line"
      show=false
      while IFS= read -r f; do
        [[ -n "$f" && "$current_path" == "$f" ]] && { show=true; break; }
      done <<< "$file_list"
    else
      [[ -n "$current_chunk" ]] && current_chunk+=$'\n'"$line"
    fi
  done <<< "$full_diff"
  [[ "$show" == true && -n "$current_chunk" ]] && printf '%s\n' "$current_chunk"
}

push_packages() {
  require brew

  local brewfile="$DOTFILES_DIR/Brewfile"
  [[ -f "$brewfile" ]] || die "Brewfile not found at $brewfile — run 'install dotfiles' first"

  # ── Remove orphaned dependencies ──
  local autoremove_output orphan_lines orphan_count
  autoremove_output=$(brew autoremove --dry-run 2>/dev/null) || true
  if [[ -n "$autoremove_output" ]]; then
    orphan_lines=$(printf '%s\n' "$autoremove_output" | grep -vE '^(==>|$)' || true)
    orphan_count=$(printf '%s\n' "$orphan_lines" | grep -c . || true)
    if [[ "$orphan_count" -gt 0 ]]; then
      warn "${orphan_count} orphaned package(s) found"
      printf '%s\n' "$orphan_lines" | while IFS= read -r pkg; do
        dim "${pkg}"
      done
      if confirm_or_abort "Remove orphaned packages?"; then
        brew autoremove || die "brew autoremove failed"
        ok "Orphaned packages removed"
      fi
    fi
  fi

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

  classify_chezmoi_drift || true

  if [[ "$NON_TEMPLATE_COUNT" -gt 0 ]]; then
    echo
    header "Changed files (will be re-added)"
    _show_diff_for_files "$diff_output" "$NON_TEMPLATE_FILES"
  fi

  if [[ "$TEMPLATE_COUNT" -gt 0 ]]; then
    echo
    header "Template files (may differ after re-add)"
    _show_diff_for_files "$diff_output" "$TEMPLATE_FILES"
    info "Template diffs are expected — .tmpl source files contain template syntax"
    info "Edit the .tmpl source files in $DOTFILES_DIR if actual changes are needed"
  fi

  if [[ "$NON_TEMPLATE_COUNT" -eq 0 && "$TEMPLATE_COUNT" -gt 0 ]]; then
    echo
    info "Skipping re-add — template files require manual editing"
    info "Edit these source files directly:"
    while IFS= read -r src; do
      [[ -n "$src" ]] || continue
      dim "$src"
    done <<< "$TEMPLATE_SOURCE_FILES"
    return 0
  fi

  echo

  confirm_or_abort "Re-add ${NON_TEMPLATE_COUNT} changed file(s)?" || return 0

  chezmoi re-add || die "chezmoi re-add failed"
  ok "chezmoi source updated"

  git_commit_and_push "push dotfiles: re-add managed files"

  if [[ "$TEMPLATE_COUNT" -gt 0 ]]; then
    info "Template files still need manual editing:"
    while IFS= read -r src; do
      [[ -n "$src" ]] || continue
      dim "$src"
    done <<< "$TEMPLATE_SOURCE_FILES"
  fi
}

push_dconf() {
  require dconf

  local gnome_dir="$DOTFILES_DIR/gnome"
  [[ -d "$gnome_dir" ]] || die "GNOME settings dir not found at $gnome_dir — run 'install dotfiles' first"

  classify_dconf_drift
  if [[ "$DCONF_DRIFT_COUNT" -eq 0 ]]; then
    ok "GNOME settings already in sync"
    return 0
  fi

  # Generate updated content once per area (avoids double dconf read)
  local area dconf_path ini_file
  declare -A updated_content
  while IFS= read -r area; do
    [[ -n "$area" ]] || continue
    dconf_path="${DCONF_MAP[$area]}"
    ini_file="$gnome_dir/${area}.ini"
    updated_content[$area]=$(_generate_updated_dconf_ini "$dconf_path" "$ini_file")
  done <<< "$DCONF_DRIFTED_AREAS"

  echo
  while IFS= read -r area; do
    [[ -n "$area" ]] || continue
    ini_file="$gnome_dir/${area}.ini"
    diff -u --label "gnome/${area}.ini (saved)" --label "gnome/${area}.ini (live)" \
      "$ini_file" <(printf '%s\n' "${updated_content[$area]}") || true
  done <<< "$DCONF_DRIFTED_AREAS"
  echo

  confirm_or_abort "Update ${DCONF_DRIFT_COUNT} dconf ini file(s)?" || return 0

  while IFS= read -r area; do
    [[ -n "$area" ]] || continue
    ini_file="$gnome_dir/${area}.ini"
    printf '%s\n' "${updated_content[$area]}" > "$ini_file"
  done <<< "$DCONF_DRIFTED_AREAS"
  ok "dconf ini files updated"

  git_commit_and_push "push dconf: update gnome ini files"
}

# ── Command functions ─────────────────────────────────────────────────────────

cmd_help() {
  echo -e "${BOLD}z-bluefin-bootstrap.sh${RESET} — Bluefin laptop bootstrap"
  echo
  echo -e "${BOLD}Usage:${RESET} z-bluefin-bootstrap.sh <command>"
  echo
  echo -e "${BOLD}Commands${RESET} ${DIM}(in typical setup order)${RESET}"
  echo -e "  ${CYAN}status${RESET}                Show current state (SSH, dotfiles, chezmoi drift, dconf drift, brew)"
  echo -e "  ${CYAN}set-hostname${RESET} <name>   Set the system hostname (and refresh Tailscale device name)"
  echo -e "  ${CYAN}install github-key${RESET}    Save GitHub SSH key to ~/.ssh/github ${DIM}(requires Bitwarden)${RESET}"
  echo -e "  ${CYAN}install dotfiles${RESET}      Clone z-bluefin-dotfiles and apply config files with chezmoi"
  echo -e "  ${CYAN}install packages${RESET}      Install brew packages and flatpaks from Brewfile"
  echo -e "  ${CYAN}install dconf${RESET}        Load saved GNOME dconf settings from ini files"
  echo -e "  ${CYAN}install all${RESET}           Run github-key + clone repo + packages + dotfiles + dconf ${DIM}(requires Bitwarden)${RESET}"
  echo -e "  ${CYAN}push packages${RESET}         Dump current brew/flatpak state to Brewfile and push"
  echo -e "  ${CYAN}push dotfiles${RESET}         Re-add local dotfile changes to chezmoi source and push"
  echo -e "  ${CYAN}push dconf${RESET}            Dump live GNOME dconf settings to ini files and push"
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
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}install dconf${RESET}"
  echo
  echo -e "  ${DIM}# Or all at once:${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}install all${RESET}"
  echo
  echo -e "  ${DIM}# Push local changes back to dotfiles repo:${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}push dotfiles${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}push packages${RESET}"
  echo -e "  ./z-bluefin-bootstrap.sh ${CYAN}push dconf${RESET}"
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
  echo -e "  ${DIM}# Re-apply dotfiles without re-cloning:${RESET}"
  echo -e "  chezmoi apply"
}

cmd_status() {
  [[ $# -eq 0 ]] || die "status takes no arguments (got: $1)"

  local _status_warns=0
  _swarn() { (( ++_status_warns )); warn "$@"; }
  trap 'unset -f _swarn' RETURN

  header "Dependencies"

  local -a missing_required=()
  local -a required_tools=(brew git jq dconf ssh-agent ssh-add hostnamectl)
  for tool in "${required_tools[@]}"; do
    have "$tool" || missing_required+=("$tool")
  done

  local -a auto_tools=(bw chezmoi)
  local -a missing_auto=()
  for tool in "${auto_tools[@]}"; do
    have "$tool" || missing_auto+=("$tool")
  done

  if [[ ${#missing_required[@]} -eq 0 && ${#missing_auto[@]} -eq 0 ]]; then
    ok "All tools available"
  else
    if [[ ${#missing_required[@]} -eq 0 ]]; then
      local req_list; req_list=$(printf '%s, ' "${required_tools[@]}"); req_list=${req_list%, }
      ok "All required tools available (${req_list})"
    else
      _swarn "${#missing_required[@]} required tool(s) missing"
      for tool in "${missing_required[@]}"; do
        dim "$tool"
      done
    fi
    if [[ ${#missing_auto[@]} -eq 0 ]]; then
      local auto_list; auto_list=$(printf '%s, ' "${auto_tools[@]}"); auto_list=${auto_list%, }
      ok "Optional tools available (${auto_list} — auto-installed via brew when needed)"
    else
      for tool in "${missing_auto[@]}"; do
        if have brew; then
          info "$tool not installed (will be auto-installed via brew when needed)"
        else
          _swarn "$tool not installed (requires brew, which is also missing)"
        fi
      done
    fi
  fi

  header "System ($(hostname 2>/dev/null || echo 'unknown'))"

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
        _swarn "Tailscale running but not connected to a tailnet"
      fi
    else
      _swarn "Tailscale installed but not running — run 'sudo systemctl start tailscaled'"
    fi
  else
    _swarn "Tailscale not installed"
  fi

  header "SSH"

  # GitHub SSH key
  if [[ -f "$GITHUB_KEY_FILE" ]]; then
    local perms
    perms=$(stat -c '%a' "$GITHUB_KEY_FILE" 2>/dev/null || echo "???")
    if [[ "$perms" == "600" ]]; then
      ok "GitHub SSH key installed (~/.ssh/github, mode 600)"
    else
      _swarn "GitHub SSH key exists but permissions are ${perms} (expected 600) — run 'chmod 600 ~/.ssh/github'"
    fi
  else
    _swarn "GitHub SSH key not installed — run 'install github-key'"
  fi

  # SSH config
  if grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
    ok "SSH config has github.com entry"
  else
    _swarn "No github.com entry in ~/.ssh/config — run 'install github-key'"
  fi

  header "Dotfiles"

  # Dotfiles
  if [[ -d "$DOTFILES_DIR" ]]; then
    ok "Dotfiles repo present ($DOTFILES_DIR)"
  else
    _swarn "Dotfiles repo not cloned — run 'install dotfiles'"
  fi
  if have chezmoi; then
    if classify_chezmoi_drift; then
      if [[ "$NON_TEMPLATE_COUNT" -gt 0 ]]; then
        _swarn "chezmoi: ${NON_TEMPLATE_COUNT} file(s) out of sync — run 'push dotfiles' or 'install dotfiles'"
        while IFS= read -r f; do [[ -n "$f" ]] && dim "  ~/$f"; done <<< "$NON_TEMPLATE_FILES"
      else
        ok "chezmoi: all managed files in sync"
      fi
      if [[ "$TEMPLATE_COUNT" -gt 0 ]]; then
        info "chezmoi: ${TEMPLATE_COUNT} template file(s) differ (expected — edit .tmpl sources in $DOTFILES_DIR to update)"
        while IFS= read -r f; do [[ -n "$f" ]] && dim "  ~/$f"; done <<< "$TEMPLATE_FILES"
      fi
    else
      ok "chezmoi: all managed files in sync"
    fi
  fi
  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    local uncommitted unpushed
    uncommitted=$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null | grep -c '.' || true)
    unpushed=$(git -C "$DOTFILES_DIR" log --oneline '@{upstream}..HEAD' 2>/dev/null | grep -c '.' || true)
    if [[ "$uncommitted" -gt 0 ]]; then
      _swarn "dotfiles repo: ${uncommitted} uncommitted change(s) — commit or stash in $DOTFILES_DIR"
    fi
    if [[ "$unpushed" -gt 0 ]]; then
      _swarn "dotfiles repo: ${unpushed} unpushed commit(s) — push from $DOTFILES_DIR"
    fi
    if [[ "$uncommitted" -eq 0 && "$unpushed" -eq 0 ]]; then
      ok "dotfiles repo: clean and up to date with remote"
    fi
  fi

  header "GNOME Settings"

  if have dconf; then
    if [[ -d "$DOTFILES_DIR/gnome" ]]; then
      classify_dconf_drift
      if [[ "$DCONF_DRIFT_COUNT" -gt 0 ]]; then
        local drifted_list="${DCONF_DRIFTED_AREAS%$'\n'}"
        drifted_list="${drifted_list//$'\n'/, }"
        _swarn "${DCONF_DRIFT_COUNT} dconf area(s) out of sync — ${drifted_list}"
        while IFS= read -r area; do
          [[ -n "$area" ]] && dim "  gnome/${area}.ini"
        done <<< "$DCONF_DRIFTED_AREAS"
      else
        ok "All ${DCONF_TOTAL} dconf areas in sync"
      fi
    else
      info "gnome/ directory not found (skipped)"
    fi
  else
    info "dconf not installed (skipped)"
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
        # Cache installed lists once — avoids one `brew list` subprocess per drifted entry.
        local installed_formulae installed_casks
        installed_formulae=$(brew list --formula -1 2>/dev/null || true)
        installed_casks=$(brew list --cask -1 2>/dev/null || true)

        local truly_missing=() not_on_request=()
        local line kind name list d
        while IFS= read -r line; do
          [[ "$line" =~ ^→\  ]] || continue
          if [[ "$line" =~ ^→\ (Formula|Cask)\ ([^ ]+)\  ]]; then
            kind="${BASH_REMATCH[1]}"
            name="${BASH_REMATCH[2]}"
            [[ "$kind" == "Formula" ]] && list="$installed_formulae" || list="$installed_casks"
            if [[ $'\n'"$list"$'\n' == *$'\n'"$name"$'\n'* ]]; then
              not_on_request+=("${line#→ }")
            else
              truly_missing+=("${line#→ }")
            fi
          else
            truly_missing+=("${line#→ }")
          fi
        done < <(printf '%s\n' "$brew_check_output" | grep '^→')

        if ((${#truly_missing[@]} == 0 && ${#not_on_request[@]} == 0)); then
          _swarn "Brewfile: brew bundle check reported drift — run 'install packages'"
        fi
        if ((${#truly_missing[@]} > 0)); then
          _swarn "Brewfile: ${#truly_missing[@]} package(s) missing — run 'install packages' to install"
          for d in "${truly_missing[@]}"; do dim "$d"; done
        fi
        if ((${#not_on_request[@]} > 0)); then
          _swarn "Brewfile: ${#not_on_request[@]} package(s) present but not tracked as on-request — run 'install packages' to update brew metadata"
          for d in "${not_on_request[@]}"; do dim "$d"; done
        fi
      fi

      # ── Extras: installed but not in Brewfile ──
      local cleanup_output
      cleanup_output=$(brew bundle cleanup --file="$brewfile" 2>/dev/null) || true
      local extras
      extras=$(printf '%s\n' "$cleanup_output" | grep -cvE '^(Would |Run |==> |$)' || true)
      if [[ "$extras" -eq 0 ]]; then
        ok "Brewfile: no extra packages"
      else
        _swarn "Brewfile: ${extras} extra package(s) installed but not in Brewfile"
        dim "run 'push packages' to add to Brewfile, or 'brew autoremove' to remove orphaned deps"
        printf '%s\n' "$cleanup_output" | while IFS= read -r line; do
          if [[ "$line" =~ ^Would\  ]]; then
            dim "${line}"
          elif [[ "$line" =~ ^(Run\ |==>\ ) ]]; then
            continue
          elif [[ -n "$line" ]]; then
            dim "${line}"
          fi
        done
      fi
    else
      _swarn "Brewfile not found — run 'install dotfiles' to clone the dotfiles repo"
    fi
  else
    _swarn "Homebrew not installed"
  fi

  # ── Summary ──
  echo
  if [[ "$_status_warns" -eq 0 ]]; then
    ok "All checks passed"
  else
    warn "${_status_warns} issue(s) found"
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

  # Sync new hostname to Tailscale (best-effort, optional dependency).
  # tailscaled reads the OS hostname only at daemon start, so we push the
  # new name via `tailscale set` to avoid a daemon restart and to clear any
  # manual override on the control plane.
  if have tailscale; then
    if tailscale status --json &>/dev/null; then
      info "Refreshing Tailscale device name..."
      if sudo tailscale set --hostname="$new_hostname"; then
        ok "Tailscale device name updated to '${new_hostname}'"
      else
        warn "Failed to update Tailscale device name — run 'sudo tailscale set --hostname=${new_hostname}' manually"
      fi
    else
      info "Tailscale installed but not running — new hostname will apply on next start"
    fi
  fi
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

cmd_install_dconf() {
  warn_if_no_github_key
  header "GNOME Settings"
  install_dconf
}

cmd_install_all() {
  # Order matters:
  #   1. github-key  — SSH key needed for git clone over SSH
  #   2. clone repo  — Brewfile and gnome/*.ini live here
  #   3. packages    — installed before chezmoi so templates can reference them
  #   4. dotfiles    — chezmoi apply, with packages already available
  #   5. dconf       — GNOME settings, may depend on packages (e.g. extensions)
  bw_login_or_unlock
  header "GitHub SSH Key"
  save_github_key
  header "Dotfiles Repository"
  ensure_dotfiles_repo
  header "Packages"
  install_packages
  header "Dotfiles"
  clone_and_apply_dotfiles
  header "GNOME Settings"
  install_dconf
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
    dconf)      cmd_install_dconf "$@" ;;
    all)        cmd_install_all "$@" ;;
    *)          die "Usage: z-bluefin-bootstrap.sh install {github-key|dotfiles|packages|dconf|all}" ;;
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

cmd_push_dconf() {
  header "Push GNOME Settings"
  push_dconf
}

cmd_push() {
  local subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    packages) cmd_push_packages "$@" ;;
    dotfiles) cmd_push_dotfiles "$@" ;;
    dconf)    cmd_push_dconf "$@" ;;
    *)        die "Usage: z-bluefin-bootstrap.sh push {packages|dotfiles|dconf}" ;;
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
