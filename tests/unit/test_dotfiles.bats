#!/usr/bin/env bats
# Tests for: clone_and_apply_dotfiles()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Tool/precondition tests ──────────────────────────────────────────────────

@test "clone_and_apply_dotfiles: exits 1 when git is absent" {
  mock_cmd chezmoi 0
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run clone_and_apply_dotfiles
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: git"
}

@test "clone_and_apply_dotfiles: exits 1 when brew is absent and chezmoi missing" {
  mock_cmd git 0
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run clone_and_apply_dotfiles
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: brew"
}

@test "clone_and_apply_dotfiles: installs chezmoi via brew when missing" {
  mock_cmd git 0
  # brew mock: records args AND creates chezmoi mock so subsequent `have chezmoi` passes
  # Use absolute paths for commands since PATH is restricted during the test
  local bash_path cp_path
  bash_path="$(command -v bash)"
  cp_path="$(command -v cp)"
  {
    printf '#!%s\n' "$bash_path"
    printf 'printf "%%s\\n" "$*" >> %q\n' "$BATS_TEST_TMPDIR/brew.calls"
    printf '%s %q %q\n' "$cp_path" "$MOCK_BIN/git" "$MOCK_BIN/chezmoi"
    printf 'exit 0\n'
  } > "$MOCK_BIN/brew"
  chmod +x "$MOCK_BIN/brew"
  # Restrict PATH to MOCK_BIN only so system chezmoi is not found
  ln -sf "$bash_path" "$MOCK_BIN/bash"
  ln -sf "$(command -v env)" "$MOCK_BIN/env"
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run clone_and_apply_dotfiles
  export PATH="$saved_path"
  assert_success
  assert_output --partial "Installing chezmoi"
  assert_output --partial "chezmoi installed"
  [[ -f "$BATS_TEST_TMPDIR/brew.calls" ]]
  grep -q "install chezmoi" "$BATS_TEST_TMPDIR/brew.calls"
}

# ── Clone/pull tests ─────────────────────────────────────────────────────────

@test "clone_and_apply_dotfiles: clones repo when dir does not exist" {
  mock_cmd_capture git 0
  mock_cmd chezmoi 0
  run clone_and_apply_dotfiles
  assert_success
  assert_output --partial "Cloning dotfiles repo"
  assert_output --partial "Dotfiles repo cloned"
  [[ -f "$BATS_TEST_TMPDIR/git.calls" ]]
  grep -q "clone.*z-bluefin-dotfiles" "$BATS_TEST_TMPDIR/git.calls"
}

@test "clone_and_apply_dotfiles: pulls when dir already exists" {
  mkdir -p "$HOME/z-bluefin-dotfiles"
  mock_cmd_capture git 0
  mock_cmd chezmoi 0
  run clone_and_apply_dotfiles
  assert_success
  assert_output --partial "pulling latest"
  assert_output --partial "Dotfiles repo updated"
  [[ -f "$BATS_TEST_TMPDIR/git.calls" ]]
  grep -q "\-C.*z-bluefin-dotfiles pull" "$BATS_TEST_TMPDIR/git.calls"
}

@test "clone_and_apply_dotfiles: exits 1 when git clone fails" {
  mock_cmd chezmoi 0
  mock_cmd git 1
  run clone_and_apply_dotfiles
  assert_failure
  assert_output --partial "git clone failed"
}

@test "clone_and_apply_dotfiles: exits 1 when git pull fails" {
  mkdir -p "$HOME/z-bluefin-dotfiles"
  mock_cmd chezmoi 0
  mock_cmd git 1
  run clone_and_apply_dotfiles
  assert_failure
  assert_output --partial "git pull failed"
}

# ── chezmoi apply tests ──────────────────────────────────────────────────────

@test "clone_and_apply_dotfiles: runs chezmoi init --apply" {
  mock_cmd git 0
  mock_cmd_capture chezmoi 0
  run clone_and_apply_dotfiles
  assert_success
  assert_output --partial "Applying dotfiles with chezmoi"
  assert_output --partial "Dotfiles applied"
  grep -q "init --source.*z-bluefin-dotfiles --apply" "$BATS_TEST_TMPDIR/chezmoi.calls"
}

@test "clone_and_apply_dotfiles: exits 1 when chezmoi fails" {
  mock_cmd git 0
  mock_cmd chezmoi 1
  run clone_and_apply_dotfiles
  assert_failure
  assert_output --partial "chezmoi init --apply failed"
}
