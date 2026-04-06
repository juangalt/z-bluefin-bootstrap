#!/usr/bin/env bats
# Tests for: install_dconf()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# ── Tool/precondition tests ──────────────────────────────────────────────────

@test "install_dconf: exits 1 when dconf is absent" {
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run install_dconf
  export PATH="$saved_path"
  assert_failure
  assert_output --partial "Required tool not found: dconf"
}

@test "install_dconf: exits 1 when gnome dir is missing" {
  mock_cmd dconf 0
  mock_cmd git 0
  mkdir -p "$DOTFILES_DIR"
  run install_dconf
  assert_failure
  assert_output --partial "GNOME settings dir not found"
}

# ── Sync tests ────────────────────────────────────────────────────────────────

@test "install_dconf: reports already in sync when no drift" {
  setup_gnome_ini_files
  mock_cmd git 0
  mock_dconf --capture \
    "/org/gnome/Ptyxis/foo=one" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=four"
  run install_dconf
  assert_success
  assert_output --partial "GNOME settings already in sync"
  if [[ -f "$BATS_TEST_TMPDIR/dconf.calls" ]]; then
    run grep "^load " "$BATS_TEST_TMPDIR/dconf.calls"
    assert_failure
  fi
}

@test "install_dconf: loads only drifted areas" {
  setup_gnome_ini_files
  mock_cmd git 0
  mock_dconf --capture \
    "/org/gnome/Ptyxis/foo=CHANGED" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=four"
  run install_dconf
  assert_success
  assert_output --partial "Loading ptyxis settings"
  assert_output --partial "ptyxis applied"
  assert_output --partial "1 area(s) updated"
  run grep "^load " "$BATS_TEST_TMPDIR/dconf.calls"
  assert_success
  assert_output --partial "load /org/gnome/Ptyxis/"
  refute_output --partial "load /org/gnome/shell/"
  refute_output --partial "load /org/gnome/settings-daemon/"
}

@test "install_dconf: loads all areas when all have drifted" {
  setup_gnome_ini_files
  mock_cmd git 0
  mock_dconf --capture \
    "/org/gnome/Ptyxis/foo=CHANGED" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=CHANGED" \
    "/org/gnome/shell/qux=CHANGED"
  run install_dconf
  assert_success
  assert_output --partial "3 area(s) updated"
  run grep "^load " "$BATS_TEST_TMPDIR/dconf.calls"
  assert_success
  assert_output --partial "load /org/gnome/Ptyxis/"
  assert_output --partial "load /org/gnome/shell/"
  assert_output --partial "load /org/gnome/settings-daemon/plugins/media-keys/"
}

@test "install_dconf: exits 1 when dconf load fails" {
  setup_gnome_ini_files
  mock_cmd git 0
  # Custom dconf mock: read returns changed values, load exits 1
  {
    printf '#!/usr/bin/env bash\n'
    printf 'if [[ "$1" == "load" ]]; then exit 1; fi\n'
    printf '[[ "$1" != "read" ]] && exit 0\n'
    printf 'case "$2" in\n'
    printf '  "/org/gnome/Ptyxis/foo") printf "CHANGED\\n" ;;\n'
    printf '  "/org/gnome/settings-daemon/plugins/media-keys/baz") printf "three\\n" ;;\n'
    printf '  "/org/gnome/shell/qux") printf "four\\n" ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/dconf"
  chmod +x "$MOCK_BIN/dconf"
  run install_dconf
  assert_failure
  assert_output --partial "dconf load failed"
}
