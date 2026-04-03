#!/usr/bin/env bats
# Tests for: push_packages()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# Helper: mock brew that captures calls and creates a Brewfile.
# $1 = "same" to produce identical Brewfile, "different" to produce a changed one
mock_brew_for_dump() {
  local mode="${1:-different}"
  local source_brewfile="$DOTFILES_DIR/Brewfile"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "$BATS_TEST_TMPDIR/brew.calls"
    printf 'case "$1" in\n'
    printf '  bundle)\n'
    printf '    case "$2" in\n'
    printf '      dump)\n'
    printf '        for arg in "$@"; do\n'
    printf '          case "$arg" in --file=*) file="${arg#--file=}" ;; esac\n'
    printf '        done\n'
    if [[ "$mode" == "same" ]]; then
      printf '        cp %q "$file"\n' "$source_brewfile"
    else
      printf '        printf "brew \\"atuin\\"\\nbrew \\"bat\\"\\nbrew \\"new-package\\"\\n" > "$file"\n'
    fi
    printf '        exit 0 ;;\n'
    printf '      *) exit 0 ;;\n'
    printf '    esac ;;\n'
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/brew"
  chmod +x "$MOCK_BIN/brew"
}

# ── Tool/precondition tests ──────────────────────────────────────────────────

@test "push_packages: exits 1 when brew is absent" {
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run push_packages
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: brew"
}

@test "push_packages: exits 1 when Brewfile does not exist" {
  mock_cmd brew 0
  run push_packages
  assert_failure
  assert_output --partial "Brewfile not found"
}

# ── Sync tests ────────────────────────────────────────────────────────────────

@test "push_packages: reports already in sync when dump matches" {
  mkdir -p "$DOTFILES_DIR/.git"
  printf 'brew "atuin"\nbrew "bat"\n' > "$DOTFILES_DIR/Brewfile"
  mock_brew_for_dump same
  run push_packages
  assert_success
  assert_output --partial "Brewfile already in sync"
}

@test "push_packages: shows diff and aborts when user declines" {
  mkdir -p "$DOTFILES_DIR/.git"
  printf 'brew "atuin"\nbrew "bat"\n' > "$DOTFILES_DIR/Brewfile"
  mock_brew_for_dump different
  mock_git_for_push changes
  _push_packages_decline() { echo "n" | push_packages; }
  run _push_packages_decline
  assert_success
  assert_output --partial "Aborted"
}

@test "push_packages: updates Brewfile and commits on confirmation" {
  mkdir -p "$DOTFILES_DIR/.git"
  printf 'brew "atuin"\nbrew "bat"\n' > "$DOTFILES_DIR/Brewfile"
  mock_brew_for_dump different
  mock_git_for_push changes
  _push_packages_confirm() { echo "y" | push_packages; }
  run _push_packages_confirm
  assert_success
  assert_output --partial "Brewfile updated"
  assert_output --partial "Committed"
  assert_output --partial "Pushed to remote"
  [[ -f "$BATS_TEST_TMPDIR/git.calls" ]]
  grep -q "add -A" "$BATS_TEST_TMPDIR/git.calls"
  grep -q "commit -m" "$BATS_TEST_TMPDIR/git.calls"
  grep -q "push" "$BATS_TEST_TMPDIR/git.calls"
}

@test "push_packages: exits 1 when brew bundle dump fails" {
  mkdir -p "$DOTFILES_DIR/.git"
  printf 'brew "atuin"\n' > "$DOTFILES_DIR/Brewfile"
  mock_cmd brew 1
  run push_packages
  assert_failure
  assert_output --partial "brew bundle dump failed"
}
