#!/usr/bin/env bats
# Tests for: cmd_set_hostname()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Precondition tests ──────────────────────────────────────────────────────

@test "set-hostname: exits 1 when no argument given" {
  run cmd_set_hostname
  assert_failure
  assert_output --partial "Usage:"
}

@test "set-hostname: exits 1 when hostnamectl is absent" {
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run cmd_set_hostname "new-host"
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: hostnamectl"
}

# ── Success tests ───────────────────────────────────────────────────────────

@test "set-hostname: calls hostnamectl with the given hostname" {
  mock_cmd_capture hostnamectl 0
  run cmd_set_hostname "my-new-host"
  assert_success
  assert_output --partial "Hostname set to 'my-new-host'"
  [[ -f "$BATS_TEST_TMPDIR/hostnamectl.calls" ]]
  [[ "$(cat "$BATS_TEST_TMPDIR/hostnamectl.calls")" == "set-hostname my-new-host" ]]
}

# ── Failure tests ───────────────────────────────────────────────────────────

@test "set-hostname: exits 1 when hostnamectl fails" {
  mock_cmd hostnamectl 1
  run cmd_set_hostname "bad-host"
  assert_failure
  assert_output --partial "hostnamectl set-hostname failed"
}
