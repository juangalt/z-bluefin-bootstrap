#!/usr/bin/env bats
# Tests for: cmd_status()

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
  load_bootstrap_functions
}

# Helper: mock hostname to return a fixed value
mock_hostname() {
  mock_cmd hostname 0 "$1"
}

# ── Hostname ────────────────────────────────────────────────────────────────

@test "status: shows hostname" {
  mock_hostname "test-box"
  run cmd_status
  assert_success
  assert_output --partial "Hostname: test-box"
}

# ── Tailscale ───────────────────────────────────────────────────────────────

@test "status: shows tailscale connected with hostname and account" {
  mock_hostname "test-box"
  mock_cmd tailscale 0 "{}"
  mock_jq_dispatch ".BackendState=Running" ".Self.HostName=ts-node" ".CurrentTailnet.Name=user@example.com"
  run cmd_status
  assert_success
  assert_output --partial "Tailscale connected"
  assert_output --partial "ts-node"
  assert_output --partial "user@example.com"
}

@test "status: warns when tailscale is running but not connected" {
  mock_hostname "test-box"
  mock_cmd tailscale 0 "{}"
  mock_jq_dispatch ".BackendState=NeedsLogin" ".Self.HostName=unknown" ".CurrentTailnet.Name=unknown"
  run cmd_status
  assert_success
  assert_output --partial "Tailscale running but not connected to a tailnet"
}

@test "status: warns when tailscale is not installed" {
  mock_hostname "test-box"
  # Ensure tailscale is not on PATH — restrict to MOCK_BIN only
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run cmd_status
  export PATH="$saved_path"
  assert_success
  assert_output --partial "Tailscale not installed"
}

@test "status: warns when tailscale is installed but not running" {
  mock_hostname "test-box"
  mock_cmd tailscale 1
  run cmd_status
  assert_success
  assert_output --partial "Tailscale installed but not running"
}

# ── GitHub SSH key ──────────────────────────────────────────────────────────

@test "status: shows ok when github key exists with 600 permissions" {
  mock_hostname "test-box"
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/github"
  chmod 600 "$HOME/.ssh/github"
  run cmd_status
  assert_success
  assert_output --partial "GitHub SSH key installed"
  assert_output --partial "mode 600"
}

@test "status: warns when github key is missing" {
  mock_hostname "test-box"
  run cmd_status
  assert_success
  assert_output --partial "GitHub SSH key not installed"
}

@test "status: warns when github key has wrong permissions" {
  mock_hostname "test-box"
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/github"
  chmod 644 "$HOME/.ssh/github"
  run cmd_status
  assert_success
  assert_output --partial "permissions are 644"
  assert_output --partial "expected 600"
}

# ── SSH config ─────────────────────────────────────────────────────────────

@test "status: shows ok when ssh config has github.com entry" {
  mock_hostname "test-box"
  mkdir -p "$HOME/.ssh"
  printf 'Host github.com\n  IdentityFile ~/.ssh/github\n' > "$HOME/.ssh/config"
  run cmd_status
  assert_success
  assert_output --partial "SSH config has github.com entry"
}

@test "status: warns when ssh config has no github.com entry" {
  mock_hostname "test-box"
  run cmd_status
  assert_success
  assert_output --partial "No github.com entry"
}

# ── chezmoi drift ──────────────────────────────────────────────────────────

@test "status: shows ok when chezmoi reports no drift" {
  mock_hostname "test-box"
  mock_chezmoi_for_status clean
  run cmd_status
  assert_success
  assert_output --partial "chezmoi installed"
  assert_output --partial "all managed files in sync"
  refute_output --partial "template file(s) differ"
}

@test "status: warns when chezmoi reports non-template drift" {
  mock_hostname "test-box"
  mock_chezmoi_for_status drift
  run cmd_status
  assert_success
  assert_output --partial "2 file(s) out of sync"
  refute_output --partial "template file(s) differ"
}

@test "status: shows ok + template info when only templates differ" {
  mock_hostname "test-box"
  mock_chezmoi_for_status template-only
  run cmd_status
  assert_success
  assert_output --partial "all managed files in sync"
  assert_output --partial "1 template file(s) differ"
  assert_output --partial "expected"
  refute_output --partial "out of sync"
}

@test "status: shows warning + template info for mixed drift" {
  mock_hostname "test-box"
  mock_chezmoi_for_status mixed
  run cmd_status
  assert_success
  assert_output --partial "1 file(s) out of sync"
  assert_output --partial "1 template file(s) differ"
}

@test "status --details: lists drifted file names" {
  mock_hostname "test-box"
  mock_chezmoi_for_status drift
  run cmd_status --details
  assert_success
  assert_output --partial ".bashrc"
  assert_output --partial ".zshrc"
}

@test "status --details: lists template file names" {
  mock_hostname "test-box"
  mock_chezmoi_for_status template-only
  run cmd_status --details
  assert_success
  assert_output --partial ".claude/settings.json"
}

@test "status: hides file names without --details" {
  mock_hostname "test-box"
  mock_chezmoi_for_status mixed
  run cmd_status
  assert_success
  refute_output --partial ".bashrc"
  refute_output --partial ".claude/settings.json"
}

# ── Brew bundle check ──────────────────────────────────────────────────────

@test "status: shows ok when all brew packages installed and no extras" {
  mock_hostname "test-box"
  mock_cmd brew 0
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  assert_output --partial "Brewfile: all packages installed"
  assert_output --partial "Brewfile: no extra packages"
}

@test "status: warns when brew packages are missing" {
  mock_hostname "test-box"
  local check_out
  check_out="brew bundle can't satisfy your Brewfile's dependencies.
→ Formula ansible-lint needs to be installed.
→ Cask claude-code needs to be installed."
  mock_brew_for_status 1 "$check_out"
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  assert_output --partial "2 package(s) missing"
  refute_output --partial "ansible-lint"
}

@test "status: warns when brew is not installed" {
  mock_hostname "test-box"
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run cmd_status
  export PATH="$saved_path"
  assert_success
  assert_output --partial "Homebrew not installed"
}

@test "status: skips brew check when Brewfile is absent" {
  mock_hostname "test-box"
  mock_cmd brew 0
  run cmd_status
  assert_success
  refute_output --partial "Brewfile"
}

# ── Dotfiles repo git state ──────────────────────────────────────────────────

@test "status: shows dotfiles repo clean when up to date" {
  mock_hostname "test-box"
  mock_cmd chezmoi 0 ""
  mkdir -p "$DOTFILES_DIR/.git"
  mock_git_for_status "" ""
  run cmd_status
  assert_success
  assert_output --partial "dotfiles repo: clean and up to date with remote"
}

@test "status: warns when dotfiles repo has uncommitted changes" {
  mock_hostname "test-box"
  mock_cmd chezmoi 0 ""
  mkdir -p "$DOTFILES_DIR/.git"
  mock_git_for_status " M dot_bashrc
 M dot_zshrc
" ""
  run cmd_status
  assert_success
  assert_output --partial "dotfiles repo: 2 uncommitted change(s)"
}

@test "status: warns when dotfiles repo has unpushed commits" {
  mock_hostname "test-box"
  mock_cmd chezmoi 0 ""
  mkdir -p "$DOTFILES_DIR/.git"
  mock_git_for_status "" "abc1234 some commit
"
  run cmd_status
  assert_success
  assert_output --partial "dotfiles repo: 1 unpushed commit(s)"
}

@test "status: shows both uncommitted and unpushed warnings" {
  mock_hostname "test-box"
  mock_cmd chezmoi 0 ""
  mkdir -p "$DOTFILES_DIR/.git"
  mock_git_for_status " M dot_bashrc
" "abc1234 some commit
"
  run cmd_status
  assert_success
  assert_output --partial "1 uncommitted change(s)"
  assert_output --partial "1 unpushed commit(s)"
  refute_output --partial "clean and up to date"
}

# ── dconf drift ──────────────────────────────────────────────────────────────

@test "status: shows ok when all dconf areas are in sync" {
  mock_hostname "test-box"
  setup_gnome_ini_files
  mock_dconf \
    "/org/gnome/Ptyxis/foo=one" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=four"
  run cmd_status
  assert_success
  assert_output --partial "dconf: all 3 GNOME setting area(s) in sync"
}

@test "status: warns when some dconf areas have drifted" {
  mock_hostname "test-box"
  setup_gnome_ini_files
  mock_dconf \
    "/org/gnome/Ptyxis/foo=CHANGED" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=four"
  run cmd_status
  assert_success
  assert_output --partial "dconf: 1 area(s) out of sync"
  assert_output --partial "ptyxis"
}

@test "status: warns when all dconf areas have drifted" {
  mock_hostname "test-box"
  setup_gnome_ini_files
  mock_dconf \
    "/org/gnome/Ptyxis/foo=CHANGED" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=CHANGED" \
    "/org/gnome/shell/qux=CHANGED"
  run cmd_status
  assert_success
  assert_output --partial "dconf: 3 area(s) out of sync"
}

@test "status: shows info when dconf is not installed" {
  mock_hostname "test-box"
  # dconf not in MOCK_BIN — restrict PATH so real dconf is not found
  local saved_path="$PATH"
  export PATH="$MOCK_BIN"
  run cmd_status
  export PATH="$saved_path"
  assert_success
  assert_output --partial "dconf not installed"
}

@test "status: silently skips dconf when gnome dir is missing" {
  mock_hostname "test-box"
  mkdir -p "$DOTFILES_DIR"
  mock_cmd dconf 0
  run cmd_status
  assert_success
  refute_output --partial "dconf"
}

@test "status --details: lists drifted dconf area file names" {
  mock_hostname "test-box"
  setup_gnome_ini_files
  mock_dconf \
    "/org/gnome/Ptyxis/foo=CHANGED" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=CHANGED" \
    "/org/gnome/shell/qux=four"
  run cmd_status --details
  assert_success
  assert_output --partial "gnome/ptyxis.ini"
  assert_output --partial "gnome/keybindings.ini"
  refute_output --partial "gnome/extensions.ini"
}

@test "status: hides dconf file names without --details" {
  mock_hostname "test-box"
  setup_gnome_ini_files
  mock_dconf \
    "/org/gnome/Ptyxis/foo=CHANGED" \
    "/org/gnome/settings-daemon/plugins/media-keys/baz=three" \
    "/org/gnome/shell/qux=four"
  run cmd_status
  assert_success
  assert_output --partial "1 area(s) out of sync"
  refute_output --partial "gnome/ptyxis.ini"
}

# ── Extra brew packages ──────────────────────────────────────────────────────

@test "status: warns when extra brew packages are installed with count" {
  mock_hostname "test-box"
  mock_brew_for_status 0 "" 1 "Would uninstall formulae:
cowsay
fortune
==> This operation would free approximately 50MB of disk space.
Run \`brew bundle cleanup --force\` to make these changes."
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  assert_output --partial "2 extra package(s) installed but not in Brewfile"
  assert_output --partial "push packages"
  assert_output --partial "brew autoremove"
  refute_output --partial "cowsay"
}

@test "status: shows no extra packages when cleanup is clean" {
  mock_hostname "test-box"
  mock_brew_for_status 0 "" 0
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  assert_output --partial "Brewfile: no extra packages"
}

@test "status: does not count ==> summary line as extra package" {
  mock_hostname "test-box"
  mock_brew_for_status 0 "" 1 "Would \`brew cleanup\`:
Would remove: /some/cache (100MB)
==> This operation would free approximately 100MB of disk space.
Run \`brew bundle cleanup --force\` to make these changes."
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  assert_output --partial "Brewfile: no extra packages"
}

# ── --details flag ──────────────────────────────────────────────────────────

@test "status --details: shows missing package names" {
  mock_hostname "test-box"
  local check_out
  check_out="brew bundle can't satisfy your Brewfile's dependencies.
→ Formula ansible-lint needs to be installed.
→ Cask claude-code needs to be installed."
  mock_brew_for_status 1 "$check_out"
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status --details
  assert_success
  assert_output --partial "2 package(s) missing"
  assert_output --partial "ansible-lint"
  assert_output --partial "claude-code"
}

@test "status --details: shows extra package names" {
  mock_hostname "test-box"
  mock_brew_for_status 0 "" 1 "Would uninstall formulae:
cowsay
fortune
Would uninstall casks:
vlc
==> This operation would free approximately 100MB of disk space.
Run \`brew bundle cleanup --force\` to make these changes."
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status --details
  assert_success
  assert_output --partial "3 extra package(s)"
  assert_output --partial "cowsay"
  assert_output --partial "fortune"
  assert_output --partial "vlc"
  refute_output --partial "==> This operation"
}

@test "status: hides package names without --details" {
  mock_hostname "test-box"
  local check_out
  check_out="→ Formula ansible-lint needs to be installed."
  mock_brew_for_status 1 "$check_out" 1 "Would uninstall formulae:
cowsay
==> This operation would free approximately 10MB of disk space.
Run \`brew bundle cleanup --force\` to make these changes."
  mkdir -p "$DOTFILES_DIR"
  touch "$DOTFILES_DIR/Brewfile"
  run cmd_status
  assert_success
  assert_output --partial "1 package(s) missing"
  assert_output --partial "1 extra package(s)"
  refute_output --partial "ansible-lint"
  refute_output --partial "cowsay"
}

@test "status: rejects unknown flag" {
  run cmd_status --bogus
  assert_failure
  assert_output --partial "Unknown option for status: --bogus"
}

