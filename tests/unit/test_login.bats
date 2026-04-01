#!/usr/bin/env bats
# Tests for: bw_login_or_unlock()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Tool-absent tests ─────────────────────────────────────────────────────────

@test "bw_login_or_unlock: exits 1 when bw is absent" {
  mock_jq_value "unlocked"
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run bw_login_or_unlock
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: bw"
}

@test "bw_login_or_unlock: exits 1 when jq is absent" {
  mock_bw_status unlocked
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run bw_login_or_unlock
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: jq"
}

# ── Vault state tests ─────────────────────────────────────────────────────────

@test "bw_login_or_unlock: skips login when BW_SESSION set and vault unlocked" {
  mock_bw_status unlocked
  mock_jq_value "unlocked"
  export BW_SESSION="existing-token"
  run bw_login_or_unlock
  assert_success
  assert_output --partial "Vault already unlocked"
}

@test "bw_login_or_unlock: skips login when BW_SESSION set and vault authenticated" {
  mock_bw_status authenticated
  mock_jq_value "authenticated"
  export BW_SESSION="existing-token"
  run bw_login_or_unlock
  assert_success
  assert_output --partial "Vault already unlocked"
}

@test "bw_login_or_unlock: calls bw login when vault unauthenticated" {
  mock_bw_status unauthenticated
  mock_jq_value "unauthenticated"
  run bw_login_or_unlock
  assert_success
  assert_output --partial "Logging in"
  assert_output --partial "BW_SESSION exported"
}

@test "bw_login_or_unlock: calls bw unlock when vault locked" {
  mock_bw_status locked
  mock_jq_value "locked"
  run bw_login_or_unlock
  assert_success
  assert_output --partial "Unlocking"
  assert_output --partial "BW_SESSION exported"
}

@test "bw_login_or_unlock: refreshes BW_SESSION when vault unlocked but no session" {
  mock_bw_status unlocked
  mock_jq_value "unlocked"
  unset BW_SESSION
  run bw_login_or_unlock
  assert_success
  assert_output --partial "refreshing BW_SESSION"
  assert_output --partial "BW_SESSION exported"
}

@test "bw_login_or_unlock: exits 1 on unexpected vault status" {
  mock_bw_status "bogus"
  mock_jq_value "bogus"
  run bw_login_or_unlock
  assert_failure
  assert_output --partial "Unexpected bw status: bogus"
}

@test "bw_login_or_unlock: exits 1 when bw login fails" {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf '"'"'{"status":"unauthenticated"}\n'"'"' ;;\n'
    printf '  login) exit 1 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
  mock_jq_value "unauthenticated"
  run bw_login_or_unlock
  assert_failure
  assert_output --partial "bw login failed"
}
