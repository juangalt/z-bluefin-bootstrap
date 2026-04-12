#!/usr/bin/env bats
# Tests for: save_github_key()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
  mock_ssh_for_github none
}

# ── Tool/precondition tests ──────────────────────────────────────────────────

@test "save_github_key: exits 1 when bw is absent" {
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  export BW_SESSION="fake"
  run save_github_key
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: bw"
}

@test "save_github_key: exits 1 when jq is absent" {
  mock_bw_status unlocked
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  export BW_SESSION="fake"
  run save_github_key
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: jq"
}

@test "save_github_key: exits 1 when BW_SESSION is unset" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  unset BW_SESSION
  run save_github_key
  assert_failure
  assert_output --partial "BW_SESSION not set"
}

@test "save_github_key: exits 1 when bw get fails" {
  mock_bw_get_fail unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  run save_github_key
  assert_failure
  assert_output --partial "Failed to fetch"
}

@test "save_github_key: exits 1 when key is empty" {
  mock_bw_status unlocked
  mock_jq_value ""
  export BW_SESSION="fake"
  run save_github_key
  assert_failure
  assert_output --partial "GitHub SSH key is empty"
}

# ── Success tests ────────────────────────────────────────────────────────────

@test "save_github_key: writes key to ~/.ssh/github with 600 permissions" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  run save_github_key
  assert_success
  assert_output --partial "GitHub SSH key saved"
  [[ -f "$HOME/.ssh/github" ]]
  [[ "$(stat -c '%a' "$HOME/.ssh/github")" == "600" ]]
  [[ "$(cat "$HOME/.ssh/github")" == "-----BEGIN OPENSSH PRIVATE KEY-----" ]]
}

@test "save_github_key: creates ~/.ssh if missing" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  [[ ! -d "$HOME/.ssh" ]]
  run save_github_key
  assert_success
  [[ -d "$HOME/.ssh" ]]
}

@test "save_github_key: does not call ssh-add" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  mock_cmd_capture ssh-add 0
  export BW_SESSION="fake"
  run save_github_key
  assert_success
  [[ ! -f "$BATS_TEST_TMPDIR/ssh-add.calls" ]]
}

@test "save_github_key: overwrites existing key" {
  mock_bw_status unlocked
  mock_jq_value "NEW-KEY-CONTENT"
  export BW_SESSION="fake"
  mkdir -p "$HOME/.ssh"
  echo "OLD-KEY" > "$HOME/.ssh/github"
  run save_github_key
  assert_success
  [[ "$(cat "$HOME/.ssh/github")" == "NEW-KEY-CONTENT" ]]
}

# ── SSH config tests ────────────────────────────────────────────────────────

@test "save_github_key: creates ssh config with github.com entry" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  run save_github_key
  assert_success
  assert_output --partial "SSH config updated"
  [[ -f "$HOME/.ssh/config" ]]
  grep -q "Host github.com" "$HOME/.ssh/config"
  grep -q "IdentityFile ~/.ssh/github" "$HOME/.ssh/config"
  [[ "$(stat -c '%a' "$HOME/.ssh/config")" == "600" ]]
}

@test "save_github_key: skips ssh config if github.com entry already exists" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mock_ssh_for_github direct
  run save_github_key
  assert_success
  refute_output --partial "SSH config updated"
}

@test "save_github_key: skips ssh config when alias configures github" {
  mock_bw_status unlocked
  mock_jq_value "-----BEGIN OPENSSH PRIVATE KEY-----"
  export BW_SESSION="fake"
  mock_ssh_for_github alias
  run save_github_key
  assert_success
  refute_output --partial "SSH config updated"
}
