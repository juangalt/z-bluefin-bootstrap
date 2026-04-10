#!/usr/bin/env bats
# Integration tests for z-bluefin-bootstrap.sh commands

BOOTSTRAP="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/z-bluefin-bootstrap.sh"

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  DOTFILES_DIR="$HOME/z-bluefin-dotfiles"
}

# ── help ─────────────────────────────────────────────────────────────────────

@test "help: shows usage text" {
  run bash "$BOOTSTRAP" help
  assert_success
  assert_output --partial "Bluefin laptop bootstrap"
  assert_output --partial "install github-key"
  assert_output --partial "install dotfiles"
  assert_output --partial "install packages"
  assert_output --partial "install dconf"
  assert_output --partial "install all"
  assert_output --partial "push packages"
  assert_output --partial "push dotfiles"
  assert_output --partial "push dconf"
  assert_output --partial "recovery-key"
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

# ── install ──────────────────────────────────────────────────────────────────

@test "push: no subcommand shows usage" {
  run bash "$BOOTSTRAP" push
  assert_failure
  assert_output --partial "Usage:"
}

@test "push: unknown subcommand shows usage" {
  run bash "$BOOTSTRAP" push bogus
  assert_failure
  assert_output --partial "Usage:"
}

@test "install: no subcommand shows usage" {
  run bash "$BOOTSTRAP" install
  assert_failure
  assert_output --partial "Usage:"
}

@test "install: unknown subcommand shows usage" {
  run bash "$BOOTSTRAP" install bogus
  assert_failure
  assert_output --partial "Usage:"
}

# ── install github-key ──────────────────────────────────────────────────────

@test "install github-key: logs in and saves key" {
  mock_bw_status unauthenticated
  mock_jq_dispatch ".status=unauthenticated" ".sshKey.privateKey=-----BEGIN OPENSSH PRIVATE KEY-----"
  run bash "$BOOTSTRAP" install github-key
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
  mock_jq_dispatch ".status=unauthenticated" ".sshKey.privateKey=-----BEGIN OPENSSH PRIVATE KEY-----"
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
  mock_jq_dispatch ".status=unauthenticated" ".sshKey.privateKey=-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  mock_ssh_agent
  run bash -c "bash '$BOOTSTRAP' recovery-key 2>/dev/null"
  assert_success
  assert_output --partial "export SSH_AUTH_SOCK="
  assert_output --partial "hash -r"
}

@test "recovery-key: eval mode sends progress to stderr only" {
  mock_bw_status unauthenticated
  mock_jq_dispatch ".status=unauthenticated" ".sshKey.privateKey=-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  mock_ssh_agent
  run bash -c "bash '$BOOTSTRAP' recovery-key 2>/dev/null"
  refute_output --partial "Bitwarden Login"
  refute_output --partial "Recovery SSH Key"
}

# ── install all ──────────────────────────────────────────────────────────────

@test "install all: runs login + github-key + repo clone + packages + dotfiles + dconf" {
  mock_bw_status unauthenticated
  mock_jq_dispatch ".status=unauthenticated" ".sshKey.privateKey=-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd git 0
  mock_cmd chezmoi 0
  mock_cmd brew 0
  mock_cmd dconf 0
  setup_gnome_ini_files
  touch "$DOTFILES_DIR/Brewfile"
  run bash "$BOOTSTRAP" install all
  assert_success
  assert_output --partial "BW_SESSION exported"
  assert_output --partial "GitHub SSH key saved"
  assert_output --partial "Dotfiles Repository"
  assert_output --partial "All packages installed"
  assert_output --partial "Dotfiles applied"
  assert_output --partial "GNOME Settings"
  assert_output --partial "Bootstrap complete."
  refute_output --partial "Git identity"
  refute_output --partial "Primary SSH key"
}

# ── status ────────────────────────────────────────────────────────────────

@test "status: runs without errors and shows system status" {
  mock_cmd hostname 0 "int-test-box"
  run bash "$BOOTSTRAP" status
  assert_success
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

# ── install packages ─────────────────────────────────────────────────────────

@test "install packages: fails when Brewfile missing" {
  mock_cmd brew 0
  mock_cmd git 0
  run bash "$BOOTSTRAP" install packages
  assert_failure
  assert_output --partial "Brewfile not found"
}

@test "install packages: installs from Brewfile" {
  mock_cmd brew 0
  mock_cmd git 0
  mkdir -p "$HOME/z-bluefin-dotfiles"
  touch "$HOME/z-bluefin-dotfiles/Brewfile"
  run bash "$BOOTSTRAP" install packages
  assert_success
  assert_output --partial "All packages installed"
}

@test "install packages: warns when github key missing" {
  mock_cmd brew 0
  mock_cmd git 0
  mkdir -p "$HOME/z-bluefin-dotfiles"
  touch "$HOME/z-bluefin-dotfiles/Brewfile"
  run bash "$BOOTSTRAP" install packages
  assert_success
  assert_output --partial "GitHub SSH key not found"
  assert_output --partial "All packages installed"
}

# ── install dconf ────────────────────────────────────────────────────────────

@test "install dconf: loads settings when drift exists" {
  mock_cmd git 0
  mock_dconf --capture \
    "/org/gnome/Ptyxis/foo=CHANGED" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=four"
  setup_gnome_ini_files
  run bash "$BOOTSTRAP" install dconf
  assert_success
  assert_output --partial "ptyxis applied"
  assert_output --partial "1 area(s) updated"
}

@test "install dconf: warns when github key missing" {
  mock_cmd git 0
  mock_cmd dconf 0
  setup_gnome_ini_files
  run bash "$BOOTSTRAP" install dconf
  assert_success
  assert_output --partial "GitHub SSH key not found"
}

# ── install dotfiles ─────────────────────────────────────────────────────────

@test "install dotfiles: warns when github key missing" {
  mock_cmd git 0
  mock_cmd chezmoi 0
  run bash "$BOOTSTRAP" install dotfiles
  assert_success
  assert_output --partial "GitHub SSH key not found"
  assert_output --partial "Dotfiles applied"
}

@test "install dotfiles: clones and applies successfully" {
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/github"
  mock_cmd git 0
  mock_cmd chezmoi 0
  run bash "$BOOTSTRAP" install dotfiles
  assert_success
  refute_output --partial "GitHub SSH key not found"
  assert_output --partial "Dotfiles applied"
}
