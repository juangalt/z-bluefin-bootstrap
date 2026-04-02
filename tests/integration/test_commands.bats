#!/usr/bin/env bats
# Integration tests for z-bluefin-bootstrap.sh commands

BOOTSTRAP="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/z-bluefin-bootstrap.sh"

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
}

# ── help ─────────────────────────────────────────────────────────────────────

@test "help: shows usage text" {
  run bash "$BOOTSTRAP" help
  assert_success
  assert_output --partial "Bluefin laptop bootstrap"
  assert_output --partial "github"
  assert_output --partial "recovery-key"
  assert_output --partial "dotfiles"
  assert_output --partial "packages"
}

@test "--help: shows usage text" {
  run bash "$BOOTSTRAP" --help
  assert_success
  assert_output --partial "Bluefin laptop bootstrap"
}

@test "unknown command: exits 1" {
  run bash "$BOOTSTRAP" bogus
  assert_failure
  assert_output --partial "Unknown command: bogus"
}

# ── github ───────────────────────────────────────────────────────────────────

@test "github: logs in and saves key" {
  mock_bw_status unauthenticated
  mock_jq_sequence "unauthenticated" "-----BEGIN OPENSSH PRIVATE KEY-----"
  run bash "$BOOTSTRAP" github
  assert_success
  assert_output --partial "BW_SESSION exported"
  assert_output --partial "GitHub SSH key saved"
  refute_output --partial "Git identity"
  [[ -f "$HOME/.ssh/github" ]]
  [[ "$(stat -c '%a' "$HOME/.ssh/github")" == "600" ]]
}

# ── recovery-key ─────────────────────────────────────────────────────────────

@test "recovery-key: logs in and loads key into ssh-agent" {
  mock_bw_status unauthenticated
  mock_jq_sequence "unauthenticated" "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  mock_ssh_agent
  # run captures stdout (non-TTY), so auto-detect triggers eval mode;
  # progress goes to stderr which run also captures
  run bash "$BOOTSTRAP" recovery-key
  assert_success
  assert_output --partial "BW_SESSION exported"
  assert_output --partial "Recovery SSH key loaded"
  assert_output --partial "export SSH_AUTH_SOCK="
}

@test "recovery-key: eval mode exports ssh-agent vars" {
  mock_bw_status unauthenticated
  mock_jq_sequence "unauthenticated" "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  mock_ssh_agent
  run bash -c "bash '$BOOTSTRAP' recovery-key 2>/dev/null"
  assert_success
  assert_output --partial "export SSH_AUTH_SOCK="
  assert_output --partial "hash -r"
}

@test "recovery-key: eval mode sends progress to stderr only" {
  mock_bw_status unauthenticated
  mock_jq_sequence "unauthenticated" "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  mock_ssh_agent
  run bash -c "bash '$BOOTSTRAP' recovery-key 2>/dev/null"
  refute_output --partial "Bitwarden Login"
  refute_output --partial "Recovery SSH Key"
}

# ── all ──────────────────────────────────────────────────────────────────────

@test "all: runs login + github + dotfiles + packages" {
  mock_bw_status unauthenticated
  mock_jq_sequence "unauthenticated" "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd git 0
  mock_cmd chezmoi 0
  mock_cmd brew 0
  mkdir -p "$HOME/z-bluefin-dotfiles"
  touch "$HOME/z-bluefin-dotfiles/Brewfile"
  run bash "$BOOTSTRAP" all
  assert_success
  assert_output --partial "BW_SESSION exported"
  assert_output --partial "GitHub SSH key saved"
  assert_output --partial "Dotfiles applied"
  assert_output --partial "All packages installed"
  assert_output --partial "Bootstrap complete."
  refute_output --partial "Git identity"
  refute_output --partial "Primary SSH key"
}

# ── status ────────────────────────────────────────────────────────────────

@test "status: runs without errors and shows system status" {
  mock_cmd hostname 0 "int-test-box"
  run bash "$BOOTSTRAP" status
  assert_success
  assert_output --partial "System Status"
  assert_output --partial "Hostname: int-test-box"
}

@test "help: shows status and set-hostname commands" {
  run bash "$BOOTSTRAP" help
  assert_success
  assert_output --partial "status"
  assert_output --partial "set-hostname"
}

# ── set-hostname ──────────────────────────────────────────────────────────

@test "set-hostname: exits 1 without argument" {
  run bash "$BOOTSTRAP" set-hostname
  assert_failure
  assert_output --partial "Usage:"
}

@test "set-hostname: calls hostnamectl successfully" {
  mock_cmd_capture hostnamectl 0
  run bash "$BOOTSTRAP" set-hostname test-host
  assert_success
  assert_output --partial "Hostname set to 'test-host'"
}

# ── packages ─────────────────────────────────────────────────────────────────

@test "packages: fails when Brewfile missing" {
  mock_cmd brew 0
  run bash "$BOOTSTRAP" packages
  assert_failure
  assert_output --partial "Brewfile not found"
}

@test "packages: installs from Brewfile" {
  mock_cmd brew 0
  mkdir -p "$HOME/z-bluefin-dotfiles"
  touch "$HOME/z-bluefin-dotfiles/Brewfile"
  run bash "$BOOTSTRAP" packages
  assert_success
  assert_output --partial "All packages installed"
}

# ── dotfiles ─────────────────────────────────────────────────────────────────

@test "dotfiles: warns when github key missing" {
  mock_cmd git 0
  mock_cmd chezmoi 0
  run bash "$BOOTSTRAP" dotfiles
  assert_success
  assert_output --partial "GitHub SSH key not found"
  assert_output --partial "Dotfiles applied"
}

@test "dotfiles: clones and applies successfully" {
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/github"
  mock_cmd git 0
  mock_cmd chezmoi 0
  run bash "$BOOTSTRAP" dotfiles
  assert_success
  refute_output --partial "GitHub SSH key not found"
  assert_output --partial "Dotfiles applied"
}

