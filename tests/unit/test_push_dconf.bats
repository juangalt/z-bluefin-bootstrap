#!/usr/bin/env bats
# Tests for: push_dconf()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Tool/precondition tests ──────────────────────────────────────────────────

@test "push_dconf: exits 1 when dconf is absent" {
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run push_dconf
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: dconf"
}

@test "push_dconf: exits 1 when gnome dir is missing" {
  mock_cmd dconf 0
  mkdir -p "$DOTFILES_DIR"
  run push_dconf
  assert_failure
  assert_output --partial "GNOME settings dir not found"
}

# ── Sync tests ────────────────────────────────────────────────────────────────

@test "push_dconf: reports already in sync when no drift" {
  setup_gnome_ini_files
  mock_dconf --capture \
    "/org/gnome/Ptyxis/foo=one" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=four"
  run push_dconf
  assert_success
  assert_output --partial "GNOME settings already in sync"
}

@test "push_dconf: shows diff and aborts when user declines" {
  setup_gnome_ini_files
  mock_dconf --capture \
    "/org/gnome/Ptyxis/foo=CHANGED" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=four"
  _push_dconf_decline() { echo "n" | push_dconf; }
  run _push_dconf_decline
  assert_success
  assert_output --partial "Aborted"
  [[ "$(cat "$DOTFILES_DIR/gnome/ptyxis.ini")" == *"foo=one"* ]]
}

@test "push_dconf: updates ini files and commits on confirmation" {
  setup_gnome_ini_files
  mock_dconf --capture \
    "/org/gnome/Ptyxis/foo=NEWVAL" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=four"
  mock_git_for_push changes
  mkdir -p "$DOTFILES_DIR/.git"
  _push_dconf_confirm() { echo "y" | push_dconf; }
  run _push_dconf_confirm
  assert_success
  assert_output --partial "dconf ini files updated"
  assert_output --partial "Committed"
  assert_output --partial "Pushed to remote"
  run cat "$DOTFILES_DIR/gnome/ptyxis.ini"
  assert_output --partial "foo=NEWVAL"
  run cat "$DOTFILES_DIR/gnome/keybindings.ini"
  assert_output --partial "baz=three"
}

@test "push_dconf: only updates drifted areas, leaves others untouched" {
  setup_gnome_ini_files
  mock_dconf --capture \
    "/org/gnome/Ptyxis/foo=CHANGED" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=CHANGED"
  mock_git_for_push changes
  mkdir -p "$DOTFILES_DIR/.git"
  _push_dconf_partial() { echo "y" | push_dconf; }
  run _push_dconf_partial
  assert_success
  assert_output --partial "dconf ini files updated"
  run cat "$DOTFILES_DIR/gnome/ptyxis.ini"
  assert_output --partial "foo=CHANGED"
  run cat "$DOTFILES_DIR/gnome/extensions.ini"
  assert_output --partial "qux=CHANGED"
  run cat "$DOTFILES_DIR/gnome/keybindings.ini"
  assert_output --partial "baz=three"
}
