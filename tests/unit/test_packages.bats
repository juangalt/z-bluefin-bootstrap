#!/usr/bin/env bats
# Tests for: install_packages()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Tool/precondition tests ──────────────────────────────────────────────────

@test "install_packages: exits 1 when brew is absent" {
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run install_packages
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: brew"
}

@test "install_packages: exits 1 when Brewfile does not exist" {
  mock_cmd brew 0
  run install_packages
  assert_failure
  assert_output --partial "Brewfile not found"
}

# ── Install tests ────────────────────────────────────────────────────────────

@test "install_packages: runs brew bundle install with correct args" {
  mock_cmd_capture brew 0
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run install_packages
  assert_success
  assert_output --partial "Installing packages from Brewfile"
  assert_output --partial "All packages installed"
  [[ -f "$BATS_TEST_TMPDIR/brew.calls" ]]
  grep -q "bundle install --file=.*Brewfile --no-upgrade" "$BATS_TEST_TMPDIR/brew.calls"
}

@test "install_packages: exits 1 when brew bundle install fails" {
  mock_cmd brew 1
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run install_packages
  assert_failure
  assert_output --partial "brew bundle install failed"
}
