#!/usr/bin/env bats
# Tests for: configure_git_identity()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Tool/precondition tests ──────────────────────────────────────────────────

@test "configure_git_identity: exits 1 when git is absent" {
  mock_bw_status unlocked
  mock_jq_value "test-user"
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  export BW_SESSION="fake"
  run configure_git_identity
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: git"
}

@test "configure_git_identity: exits 1 when BW_SESSION is unset" {
  mock_bw_status unlocked
  mock_jq_value "test-user"
  mock_cmd git 0
  unset BW_SESSION
  run configure_git_identity
  assert_failure
  assert_output --partial "BW_SESSION not set"
}

@test "configure_git_identity: exits 1 when bw get fails" {
  mock_bw_get_fail unlocked
  mock_jq_value "test-user"
  mock_cmd git 0
  export BW_SESSION="fake"
  run configure_git_identity
  assert_failure
  assert_output --partial "Failed to fetch"
}

@test "configure_git_identity: exits 1 when name is empty" {
  mock_bw_status unlocked
  # jq mock: first call returns empty (name), second would return email
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "\\n"\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
  mock_cmd git 0
  export BW_SESSION="fake"
  run configure_git_identity
  assert_failure
  assert_output --partial "Git user.name is empty"
}

@test "configure_git_identity: exits 1 when email is empty" {
  mock_bw_status unlocked
  # jq mock: first call returns name, second returns empty (email)
  {
    printf '#!/usr/bin/env bash\n'
    printf 'COUNTER_FILE="%s/jq_counter"\n' "$BATS_TEST_TMPDIR"
    printf 'n=0; [[ -f "$COUNTER_FILE" ]] && n=$(cat "$COUNTER_FILE")\n'
    printf 'n=$((n+1)); printf "%%s" "$n" > "$COUNTER_FILE"\n'
    printf 'if [[ $n -eq 1 ]]; then printf "%%s\\n" "Test User"; else printf "\\n"; fi\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
  mock_cmd git 0
  export BW_SESSION="fake"
  run configure_git_identity
  assert_failure
  assert_output --partial "Git user.email is empty"
}

@test "configure_git_identity: sets git user.name and user.email" {
  mock_bw_status unlocked
  # jq mock: first call returns name, second returns email
  {
    printf '#!/usr/bin/env bash\n'
    printf 'COUNTER_FILE="%s/jq_counter"\n' "$BATS_TEST_TMPDIR"
    printf 'n=0; [[ -f "$COUNTER_FILE" ]] && n=$(cat "$COUNTER_FILE")\n'
    printf 'n=$((n+1)); printf "%%s" "$n" > "$COUNTER_FILE"\n'
    printf 'if [[ $n -eq 1 ]]; then printf "%%s\\n" "Test User"; else printf "%%s\\n" "test@example.com"; fi\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
  mock_cmd_capture git 0
  export BW_SESSION="fake"
  run configure_git_identity
  assert_success
  assert_output --partial "Git identity configured: Test User <test@example.com>"
  # Verify git config was called with the right arguments
  assert [ -f "$BATS_TEST_TMPDIR/git.calls" ]
  run cat "$BATS_TEST_TMPDIR/git.calls"
  assert_output --partial "config --global user.name Test User"
  assert_output --partial "config --global user.email test@example.com"
}
