#!/usr/bin/env bats
# Tests for: load_recovery_key()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Tool/precondition tests ──────────────────────────────────────────────────

@test "load_recovery_key: exits 1 when bw is absent" {
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  mock_ssh_agent
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  export BW_SESSION="fake"
  run load_recovery_key
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: bw"
}

@test "load_recovery_key: exits 1 when jq is absent" {
  mock_bw_status unlocked
  mock_cmd ssh-add 0
  mock_ssh_agent
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  export BW_SESSION="fake"
  run load_recovery_key
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: jq"
}

@test "load_recovery_key: exits 1 when ssh-add is absent" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_ssh_agent
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  export BW_SESSION="fake"
  run load_recovery_key
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: ssh-add"
}

@test "load_recovery_key: exits 1 when ssh-agent is absent" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  unset SSH_AUTH_SOCK
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  export BW_SESSION="fake"
  run load_recovery_key
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: ssh-agent"
}

@test "load_recovery_key: exits 1 when BW_SESSION is unset" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  mock_ssh_agent
  unset BW_SESSION
  run load_recovery_key
  assert_failure
  assert_output --partial "BW_SESSION not set"
}

@test "load_recovery_key: exits 1 when bw get fails" {
  mock_bw_get_fail unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  mock_ssh_agent
  export BW_SESSION="fake"
  run load_recovery_key
  assert_failure
  assert_output --partial "Failed to fetch"
}

@test "load_recovery_key: exits 1 when key is empty" {
  mock_bw_status unlocked
  mock_jq_value ""
  mock_cmd ssh-add 0
  mock_ssh_agent
  export BW_SESSION="fake"
  run load_recovery_key
  assert_failure
  assert_output --partial "Recovery SSH key is empty"
}

@test "load_recovery_key: exits 1 when ssh-add fails" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 1
  export SSH_AUTH_SOCK="/tmp/existing-agent.sock"
  export BW_SESSION="fake"
  run load_recovery_key
  assert_failure
  assert_output --partial "Failed to load recovery SSH key"
}

# ── Success tests ────────────────────────────────────────────────────────────

@test "load_recovery_key: succeeds when SSH_AUTH_SOCK is pre-set" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  export SSH_AUTH_SOCK="/tmp/existing-agent.sock"
  export BW_SESSION="fake"
  run load_recovery_key
  assert_success
  assert_output --partial "Recovery SSH key loaded"
}

@test "load_recovery_key: starts ssh-agent when SSH_AUTH_SOCK is unset" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  mock_ssh_agent
  unset SSH_AUTH_SOCK
  export BW_SESSION="fake"
  run load_recovery_key
  assert_success
  assert_output --partial "ssh-agent started"
  assert_output --partial "Recovery SSH key loaded"
}

@test "load_recovery_key: does not write any file to ~/.ssh" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd ssh-add 0
  export SSH_AUTH_SOCK="/tmp/existing-agent.sock"
  export BW_SESSION="fake"
  mkdir -p "$HOME/.ssh"
  run load_recovery_key
  assert_success
  # .ssh should be empty — no key file written
  [[ -z "$(ls -A "$HOME/.ssh")" ]]
}
