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
  mock_git_identity "" ""
  run cmd_status
  assert_success
  assert_output --partial "Hostname: test-box"
}

# ── Tailscale ───────────────────────────────────────────────────────────────

@test "status: shows tailscale running with hostname" {
  mock_hostname "test-box"
  mock_git_identity "" ""
  # Mock tailscale to return JSON
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf '"'"'{"Self":{"HostName":"ts-node"}}'"'"'\n'
  } > "$MOCK_BIN/tailscale"
  chmod +x "$MOCK_BIN/tailscale"
  mock_jq_value "ts-node"
  run cmd_status
  assert_success
  assert_output --partial "Tailscale running"
  assert_output --partial "ts-node"
}

@test "status: warns when tailscale is not installed" {
  mock_hostname "test-box"
  mock_git_identity "" ""
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
  mock_git_identity "" ""
  mock_cmd tailscale 1
  run cmd_status
  assert_success
  assert_output --partial "Tailscale installed but not running"
}

# ── GitHub SSH key ──────────────────────────────────────────────────────────

@test "status: shows ok when github key exists with 600 permissions" {
  mock_hostname "test-box"
  mock_git_identity "" ""
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
  mock_git_identity "" ""
  run cmd_status
  assert_success
  assert_output --partial "GitHub SSH key not installed"
}

@test "status: warns when github key has wrong permissions" {
  mock_hostname "test-box"
  mock_git_identity "" ""
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/github"
  chmod 644 "$HOME/.ssh/github"
  run cmd_status
  assert_success
  assert_output --partial "permissions are 644"
  assert_output --partial "expected 600"
}

# ── Git identity ────────────────────────────────────────────────────────────

@test "status: shows ok when git identity is configured" {
  mock_hostname "test-box"
  mock_git_identity "Test User" "test@example.com"
  run cmd_status
  assert_success
  assert_output --partial "Git identity: Test User <test@example.com>"
}

@test "status: warns when git identity is not configured" {
  mock_hostname "test-box"
  mock_git_identity "" ""
  run cmd_status
  assert_success
  assert_output --partial "Git identity not configured"
}

@test "status: warns when git identity is partially configured" {
  mock_hostname "test-box"
  mock_git_identity "Test User" ""
  run cmd_status
  assert_success
  assert_output --partial "partially configured"
}
