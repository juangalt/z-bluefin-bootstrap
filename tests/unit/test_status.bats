#!/usr/bin/env bats
# Tests for: cmd_status()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# Helper: mock hostname to return a fixed value
mock_hostname() {
  mock_cmd hostname 0 "$1"
}

# ── Hostname ────────────────────────────────────────────────────────────────

@test "status: shows hostname" {
  mock_hostname "test-box"
  run cmd_status
  assert_success
  assert_output --partial "Hostname: test-box"
}

# ── Tailscale ───────────────────────────────────────────────────────────────

@test "status: shows tailscale connected with hostname and account" {
  mock_hostname "test-box"
  mock_cmd tailscale 0 "{}"
  # jq is called 3 times: BackendState, HostName, CurrentTailnet.Name
  mock_jq_sequence "Running" "ts-node" "user@example.com"
  run cmd_status
  assert_success
  assert_output --partial "Tailscale connected"
  assert_output --partial "ts-node"
  assert_output --partial "user@example.com"
}

@test "status: warns when tailscale is running but not connected" {
  mock_hostname "test-box"
  mock_cmd tailscale 0 "{}"
  mock_jq_sequence "NeedsLogin" "unknown" "unknown"
  run cmd_status
  assert_success
  assert_output --partial "Tailscale running but not connected to a tailnet"
}

@test "status: warns when tailscale is not installed" {
  mock_hostname "test-box"
  # Ensure tailscale is not on PATH — restrict to MOCK_BIN only
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run cmd_status
  export PATH="$saved_path"
  assert_success
  assert_output --partial "Tailscale not installed"
}

@test "status: warns when tailscale is installed but not running" {
  mock_hostname "test-box"
  mock_cmd tailscale 1
  run cmd_status
  assert_success
  assert_output --partial "Tailscale installed but not running"
}

# ── GitHub SSH key ──────────────────────────────────────────────────────────

@test "status: shows ok when github key exists with 600 permissions" {
  mock_hostname "test-box"
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/github"
  chmod 600 "$HOME/.ssh/github"
  run cmd_status
  assert_success
  assert_output --partial "GitHub SSH key installed"
  assert_output --partial "mode 600"
}

@test "status: warns when github key is missing" {
  mock_hostname "test-box"
  run cmd_status
  assert_success
  assert_output --partial "GitHub SSH key not installed"
}

@test "status: warns when github key has wrong permissions" {
  mock_hostname "test-box"
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/github"
  chmod 644 "$HOME/.ssh/github"
  run cmd_status
  assert_success
  assert_output --partial "permissions are 644"
  assert_output --partial "expected 600"
}

# ── SSH config ─────────────────────────────────────────────────────────────

@test "status: shows ok when ssh config has github.com entry" {
  mock_hostname "test-box"
  mkdir -p "$HOME/.ssh"
  printf 'Host github.com\n  IdentityFile ~/.ssh/github\n' > "$HOME/.ssh/config"
  run cmd_status
  assert_success
  assert_output --partial "SSH config has github.com entry"
}

@test "status: warns when ssh config has no github.com entry" {
  mock_hostname "test-box"
  run cmd_status
  assert_success
  assert_output --partial "No github.com entry"
}

# ── chezmoi drift ──────────────────────────────────────────────────────────

@test "status: shows ok when chezmoi reports no drift" {
  mock_hostname "test-box"
  mock_cmd chezmoi 0 ""
  run cmd_status
  assert_success
  assert_output --partial "chezmoi installed"
  assert_output --partial "all managed files in sync"
}

@test "status: warns when chezmoi reports drift" {
  mock_hostname "test-box"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'if [[ "$1" == "status" ]]; then\n'
    printf '  printf "MM .gitconfig\\n M .claude\\n"\n'
    printf '  exit 0\n'
    printf 'fi\n'
  } > "$MOCK_BIN/chezmoi"
  chmod +x "$MOCK_BIN/chezmoi"
  run cmd_status
  assert_success
  assert_output --partial "2 file(s) out of sync"
}

# ── Brew bundle check ──────────────────────────────────────────────────────

@test "status: shows ok when all brew packages installed" {
  mock_hostname "test-box"
  mock_cmd brew 0
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  assert_output --partial "Brewfile: all packages installed"
}

@test "status: warns when brew packages are missing" {
  mock_hostname "test-box"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "brew bundle can'"'"'t satisfy your Brewfile'"'"'s dependencies.\\n"\n'
    printf 'printf "→ Formula ansible-lint needs to be installed.\\n"\n'
    printf 'printf "→ Cask claude-code needs to be installed.\\n"\n'
    printf 'exit 1\n'
  } > "$MOCK_BIN/brew"
  chmod +x "$MOCK_BIN/brew"
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  assert_output --partial "2 package(s) missing"
}

@test "status: warns when brew is not installed" {
  mock_hostname "test-box"
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run cmd_status
  export PATH="$saved_path"
  assert_success
  assert_output --partial "Homebrew not installed"
}

@test "status: skips brew check when Brewfile is absent" {
  mock_hostname "test-box"
  mock_cmd brew 0
  run cmd_status
  assert_success
  refute_output --partial "Brewfile"
}

# ── Dotfiles repo git state ──────────────────────────────────────────────────

@test "status: shows dotfiles repo clean when up to date" {
  mock_hostname "test-box"
  mock_cmd chezmoi 0 ""
  mkdir -p "$DOTFILES_DIR/.git"
  mock_git_for_status "" ""
  run cmd_status
  assert_success
  assert_output --partial "dotfiles repo: clean and up to date with remote"
}

@test "status: warns when dotfiles repo has uncommitted changes" {
  mock_hostname "test-box"
  mock_cmd chezmoi 0 ""
  mkdir -p "$DOTFILES_DIR/.git"
  mock_git_for_status " M dot_bashrc
 M dot_zshrc
" ""
  run cmd_status
  assert_success
  assert_output --partial "dotfiles repo: 2 uncommitted change(s)"
}

@test "status: warns when dotfiles repo has unpushed commits" {
  mock_hostname "test-box"
  mock_cmd chezmoi 0 ""
  mkdir -p "$DOTFILES_DIR/.git"
  mock_git_for_status "" "abc1234 some commit
"
  run cmd_status
  assert_success
  assert_output --partial "dotfiles repo: 1 unpushed commit(s)"
}

@test "status: shows both uncommitted and unpushed warnings" {
  mock_hostname "test-box"
  mock_cmd chezmoi 0 ""
  mkdir -p "$DOTFILES_DIR/.git"
  mock_git_for_status " M dot_bashrc
" "abc1234 some commit
"
  run cmd_status
  assert_success
  assert_output --partial "1 uncommitted change(s)"
  assert_output --partial "1 unpushed commit(s)"
  refute_output --partial "clean and up to date"
}

# ── Extra brew packages ──────────────────────────────────────────────────────

@test "status: warns when extra brew packages are installed" {
  mock_hostname "test-box"
  mock_brew_for_status 0 1 "cowsay
fortune"
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  assert_output --partial "extra packages installed locally"
}

@test "status: no extra packages warning when none" {
  mock_hostname "test-box"
  mock_brew_for_status 0 0
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  refute_output --partial "extra packages"
}

