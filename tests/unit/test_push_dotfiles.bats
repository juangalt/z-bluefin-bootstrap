#!/usr/bin/env bats
# Tests for: push_dotfiles()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Tool/precondition tests ──────────────────────────────────────────────────

@test "push_dotfiles: exits 1 when chezmoi is absent" {
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run push_dotfiles
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: chezmoi"
}

@test "push_dotfiles: exits 1 when DOTFILES_DIR does not exist" {
  mock_cmd chezmoi 0
  run push_dotfiles
  assert_failure
  assert_output --partial "Dotfiles repo not found"
}

# ── Sync tests ────────────────────────────────────────────────────────────────

@test "push_dotfiles: reports already in sync when no drift" {
  mock_chezmoi_for_push clean
  mkdir -p "$DOTFILES_DIR/.git"
  run push_dotfiles
  assert_success
  assert_output --partial "Dotfiles already in sync"
}

@test "push_dotfiles: shows diff and aborts when user declines" {
  mock_chezmoi_for_push drift
  mock_git_for_push changes
  mkdir -p "$DOTFILES_DIR/.git"
  _push_dotfiles_decline() { echo "n" | push_dotfiles; }
  run _push_dotfiles_decline
  assert_success
  assert_output --partial "Aborted"
}

@test "push_dotfiles: re-adds and commits on confirmation" {
  mock_chezmoi_for_push drift
  mock_git_for_push changes
  mkdir -p "$DOTFILES_DIR/.git"
  _push_dotfiles_confirm() { echo "y" | push_dotfiles; }
  run _push_dotfiles_confirm
  assert_success
  assert_output --partial "chezmoi source updated"
  assert_output --partial "Committed"
  assert_output --partial "Pushed to remote"
  [[ -f "$BATS_TEST_TMPDIR/chezmoi.calls" ]]
  grep -q "re-add" "$BATS_TEST_TMPDIR/chezmoi.calls"
  [[ -f "$BATS_TEST_TMPDIR/git.calls" ]]
  grep -q "add -A" "$BATS_TEST_TMPDIR/git.calls"
  grep -q "commit -m" "$BATS_TEST_TMPDIR/git.calls"
}

@test "push_dotfiles: exits 1 when chezmoi re-add fails" {
  mkdir -p "$DOTFILES_DIR/.git"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  diff) printf "diff output\\n"; exit 0 ;;\n'
    printf '  status) printf "MM .bashrc\\n" ;;\n'
    printf '  source-path) printf "%s/dot_bashrc\\n" ;;\n' "$DOTFILES_DIR"
    printf '  re-add) exit 1 ;;\n'
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/chezmoi"
  chmod +x "$MOCK_BIN/chezmoi"
  mock_git_for_push changes
  _push_dotfiles_fail() { echo "y" | push_dotfiles; }
  run _push_dotfiles_fail
  assert_failure
  assert_output --partial "chezmoi re-add failed"
}

# ── Template tests ────────────────────────────────────────────────────────────

@test "push_dotfiles: template-only shows guidance and skips re-add" {
  mock_chezmoi_for_push template-only
  mkdir -p "$DOTFILES_DIR/.git"
  run push_dotfiles
  assert_success
  assert_output --partial "Template files (may differ after re-add)"
  assert_output --partial "Template diffs are expected"
  assert_output --partial "Skipping re-add"
  assert_output --partial "Edit these source files directly"
  assert_output --partial "settings.json.tmpl"
  refute_output --partial "chezmoi source updated"
  refute_output --partial "Re-add"
  refute_output --partial "No changes to commit"
  # chezmoi re-add should NOT have been called
  if [[ -f "$BATS_TEST_TMPDIR/chezmoi.calls" ]]; then
    ! grep -q "re-add" "$BATS_TEST_TMPDIR/chezmoi.calls"
  fi
}

@test "push_dotfiles: warns about templates but re-adds non-template files" {
  mock_chezmoi_for_push mixed
  mock_git_for_push changes
  mkdir -p "$DOTFILES_DIR/.git"
  _push_dotfiles_mixed() { echo "y" | push_dotfiles; }
  run _push_dotfiles_mixed
  assert_success
  assert_output --partial "Changed files (will be re-added)"
  assert_output --partial "Template files (may differ after re-add)"
  assert_output --partial "Template diffs are expected"
  assert_output --partial "chezmoi source updated"
  assert_output --partial "Committed"
  assert_output --partial "still need manual editing"
  assert_output --partial "settings.json.tmpl"
}
