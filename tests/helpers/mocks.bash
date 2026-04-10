#!/usr/bin/env bash
# Mock factory helpers. Requires setup_mock_bin() to have been called first.

# Write a simple mock that exits with EXIT_CODE and optionally prints OUTPUT to stdout.
# Usage: mock_cmd NAME EXIT_CODE [OUTPUT]
mock_cmd() {
  local name="$1" exit_code="${2:-0}" output="${3:-}"
  {
    printf '#!/usr/bin/env bash\n'
    [[ -n "$output" ]] && printf 'printf "%%s\\n" %q\n' "$output"
    printf 'exit %s\n' "$exit_code"
  } > "$MOCK_BIN/$name"
  chmod +x "$MOCK_BIN/$name"
}

# Write a mock that appends its arguments to a capture file and exits/prints as above.
# Capture file: $BATS_TEST_TMPDIR/<name>.calls
# Usage: mock_cmd_capture NAME EXIT_CODE [OUTPUT]
mock_cmd_capture() {
  local name="$1" exit_code="${2:-0}" output="${3:-}"
  local capture="$BATS_TEST_TMPDIR/${name}.calls"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "$capture"
    [[ -n "$output" ]] && printf 'printf "%%s\\n" %q\n' "$output"
    printf 'exit %s\n' "$exit_code"
  } > "$MOCK_BIN/$name"
  chmod +x "$MOCK_BIN/$name"
}

# Write a bw mock pre-configured for a given vault status.
# STATUS: unlocked | authenticated | locked | unauthenticated | <any>
# Usage: mock_bw_status STATUS [SESSION_TOKEN]
mock_bw_status() {
  local status="$1" token="${2:-fake-session-token}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf '"'"'{"status":"%s"}\n'"'"' %q ;;\n' "$status"
    printf '  login|unlock) printf "%%s\\n" %q ;;\n' "$token"
    printf '  get) exit 0 ;;\n'
    printf '  sync) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
}

# Write a bw mock where 'bw get' fails (item not found).
mock_bw_get_fail() {
  local status="${1:-unlocked}" token="${2:-fake-session-token}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf '"'"'{"status":"%s"}\n'"'"' %q ;;\n' "$status"
    printf '  login|unlock) printf "%%s\\n" %q ;;\n' "$token"
    printf '  get) exit 1 ;;\n'
    printf '  sync) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
}

# Write a real-ish jq mock that echoes a fixed value.
# Usage: mock_jq_value VALUE
mock_jq_value() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$1" > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
}

# Write a jq mock that dispatches on the filter expression (the argument after -r).
# Each argument is a PATTERN=VALUE pair; PATTERN is glob-matched against the jq filter.
# Usage: mock_jq_dispatch ".status=unlocked" ".sshKey.privateKey=KEY_CONTENT"
mock_jq_dispatch() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'FILTER="${@: -1}"\n'
    printf 'case "$FILTER" in\n'
    for mapping in "$@"; do
      printf '  *%s*) printf "%%s\\n" %q ;;\n' "${mapping%%=*}" "${mapping#*=}"
    done
    printf '  *) printf "jq mock: unmatched filter: %%s\\n" "$FILTER" >&2; exit 1 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
}

# Write a git mock that handles -C <dir> <subcmd> dispatch for push operations.
# $1 = "changes" (git diff --cached exits 1, i.e. staged changes exist) or "clean" (exits 0)
# Capture file: $BATS_TEST_TMPDIR/git.calls
mock_git_for_push() {
  local has_changes="${1:-changes}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "$BATS_TEST_TMPDIR/git.calls"
    printf 'subcmd="$1"; [[ "$1" == "-C" ]] && subcmd="$3"\n'
    printf 'case "$subcmd" in\n'
    printf '  add) exit 0 ;;\n'
    printf '  diff)\n'
    if [[ "$has_changes" == "changes" ]]; then
      printf '    exit 1 ;;\n'
    else
      printf '    exit 0 ;;\n'
    fi
    printf '  commit) exit 0 ;;\n'
    printf '  push) exit 0 ;;\n'
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/git"
  chmod +x "$MOCK_BIN/git"
}

# Write a chezmoi mock for status checks with template awareness.
# $1 = "clean" (no drift), "drift" (non-template only),
#       "template-only" (templates only), "mixed" (both)
# Status mode uses 2 non-template files for drift; push mode uses 1.
mock_chezmoi_for_status() {
  local mode="${1:-clean}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status)\n'
    case "$mode" in
      clean)
        : ;;
      drift)
        printf '    printf "MM .bashrc\\n M .zshrc\\n"\n' ;;
      template-only)
        printf '    printf "MM .claude/settings.json\\n"\n' ;;
      mixed)
        printf '    printf "MM .bashrc\\nMM .claude/settings.json\\n"\n' ;;
    esac
    printf '    exit 0 ;;\n'
    printf '  source-path)\n'
    printf '    case "$2" in\n'
    printf '      */.claude/settings.json) printf "%%s/private_dot_claude/settings.json.tmpl\\n" "%s" ;;\n' "$DOTFILES_DIR"
    printf '      *) printf "%%s/dot_bashrc\\n" "%s" ;;\n' "$DOTFILES_DIR"
    printf '    esac\n'
    printf '    exit 0 ;;\n'
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/chezmoi"
  chmod +x "$MOCK_BIN/chezmoi"
}

# Write a chezmoi mock for push operations (diff, status, source-path, re-add).
# $1 = "drift" (non-template), "clean" (no diff), "template-only", "mixed"
mock_chezmoi_for_push() {
  local mode="${1:-drift}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "$BATS_TEST_TMPDIR/chezmoi.calls"
    printf 'case "$1" in\n'
    printf '  diff)\n'
    case "$mode" in
      clean)
        : ;;
      drift)
        printf '    printf "diff --git a/.bashrc b/.bashrc\\n--- a/.bashrc\\n+++ b/.bashrc\\n@@ -1 +1,2 @@\\n+export FOO=bar\\n"\n'
        ;;
      template-only)
        printf '    printf "diff --git a/.claude/settings.json b/.claude/settings.json\\n--- a\\n+++ b\\n@@ -1 +1,2 @@\\n+new line\\n"\n'
        ;;
      mixed)
        printf '    printf "diff --git a/.bashrc b/.bashrc\\n--- a\\n+++ b\\n@@ -1 +1,2 @@\\n+export FOO=bar\\ndiff --git a/.claude/settings.json b/.claude/settings.json\\n--- a\\n+++ b\\n@@ -1 +1,2 @@\\n+new line\\n"\n'
        ;;
    esac
    printf '    exit 0 ;;\n'
    printf '  status)\n'
    case "$mode" in
      clean)
        : ;;
      drift)
        printf '    printf "MM .bashrc\\n"\n' ;;
      template-only)
        printf '    printf "MM .claude/settings.json\\n"\n' ;;
      mixed)
        printf '    printf "MM .bashrc\\nMM .claude/settings.json\\n"\n' ;;
    esac
    printf '    exit 0 ;;\n'
    printf '  source-path)\n'
    printf '    case "$2" in\n'
    printf '      */.claude/settings.json) printf "%%s\\n" "%s/private_dot_claude/settings.json.tmpl" ;;\n' "$DOTFILES_DIR"
    printf '      *) printf "%%s\\n" "%s/dot_bashrc" ;;\n' "$DOTFILES_DIR"
    printf '    esac\n'
    printf '    exit 0 ;;\n'
    printf '  re-add) exit 0 ;;\n'
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/chezmoi"
  chmod +x "$MOCK_BIN/chezmoi"
}

# Write a git mock for status checks (uncommitted changes + unpushed commits).
# $1 = porcelain output for `git status` (empty string = clean)
# $2 = oneline output for `git log` (empty string = no unpushed)
mock_git_for_status() {
  local status_output="${1:-}"
  local log_output="${2:-}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'subcmd="$1"; [[ "$1" == "-C" ]] && subcmd="$3"\n'
    printf 'case "$subcmd" in\n'
    printf '  status) printf "%%s" %q ;;\n' "$status_output"
    printf '  log) printf "%%s" %q ;;\n' "$log_output"
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/git"
  chmod +x "$MOCK_BIN/git"
}

# Write a brew mock for status checks (bundle check + bundle cleanup).
# $1 = exit code for `brew bundle check` (0 = all installed, 1 = missing)
# $2 = stdout for `brew bundle check` (optional)
# $3 = exit code for `brew bundle cleanup` (0 = no extras, 1 = extras found)
# $4 = stdout for `brew bundle cleanup` (optional)
mock_brew_for_status() {
  local check_rc="${1:-0}" check_output="${2:-}" \
        cleanup_rc="${3:-0}" cleanup_output="${4:-}" \
        present_names="${5:-}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  bundle)\n'
    printf '    case "$2" in\n'
    printf '      check)\n'
    [[ -n "$check_output" ]] && printf '        printf "%%s\\n" %q\n' "$check_output"
    printf '        exit %s ;;\n' "$check_rc"
    printf '      cleanup)\n'
    [[ -n "$cleanup_output" ]] && printf '        printf "%%s\\n" %q\n' "$cleanup_output"
    printf '        exit %s ;;\n' "$cleanup_rc"
    printf '      *) exit 0 ;;\n'
    printf '    esac ;;\n'
    printf '  list)\n'
    [[ -n "$present_names" ]] && printf '    printf "%%s\\n" %s\n' "$present_names"
    printf '    exit 0 ;;\n'
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/brew"
  chmod +x "$MOCK_BIN/brew"
}

# Write an ssh-agent mock that emits eval-able export lines.
mock_ssh_agent() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "SSH_AUTH_SOCK=/tmp/fake-agent.$$; export SSH_AUTH_SOCK;\\n"\n'
    printf 'printf "SSH_AGENT_PID=$$; export SSH_AGENT_PID;\\n"\n'
    printf 'printf "echo Agent pid $$;\\n"\n'
    printf 'exit 0\n'
  } > "$MOCK_BIN/ssh-agent"
  chmod +x "$MOCK_BIN/ssh-agent"
}

# Write a dconf mock that dispatches `dconf read <path>` based on the key path.
# Each positional argument is a /full/dconf/path=value pair.
# Pass --capture as first arg to log calls to $BATS_TEST_TMPDIR/dconf.calls.
# Usage: mock_dconf "/org/gnome/Ptyxis/interface-style='system'" ...
#        mock_dconf --capture "/org/gnome/Ptyxis/foo=NEWVAL" ...
mock_dconf() {
  local capture=false
  if [[ "${1:-}" == "--capture" ]]; then capture=true; shift; fi
  {
    printf '#!/usr/bin/env bash\n'
    [[ "$capture" == true ]] && printf 'printf "%%s\\n" "$*" >> %q\n' "$BATS_TEST_TMPDIR/dconf.calls"
    printf '[[ "$1" != "read" ]] && exit 0\n'
    printf 'case "$2" in\n'
    for mapping in "$@"; do
      printf '  %q) printf "%%s\\n" %q ;;\n' "${mapping%%=*}" "${mapping#*=}"
    done
    printf '  *) ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/dconf"
  chmod +x "$MOCK_BIN/dconf"
}

# Mock sudo as a transparent passthrough: `sudo foo a b` runs `foo a b`.
mock_sudo_passthrough() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'exec "$@"\n'
  } > "$MOCK_BIN/sudo"
  chmod +x "$MOCK_BIN/sudo"
}

# Mock tailscale: `status` exits with $1, `set` exits with $2, all calls captured.
# Capture file: $BATS_TEST_TMPDIR/tailscale.calls
# Usage: mock_tailscale STATUS_RC SET_RC
mock_tailscale() {
  local status_rc="${1:-0}" set_rc="${2:-0}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> %q\n' "$BATS_TEST_TMPDIR/tailscale.calls"
    printf 'case "$1" in\n'
    printf '  status) exit %s ;;\n' "$status_rc"
    printf '  set)    exit %s ;;\n' "$set_rc"
    printf '  *) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/tailscale"
  chmod +x "$MOCK_BIN/tailscale"
}
