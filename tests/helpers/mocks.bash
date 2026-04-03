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

# Write a jq mock that returns values in sequence based on call count.
# Usage: mock_jq_sequence VALUE1 VALUE2 ...
# The last value is used for all subsequent calls beyond the count.
mock_jq_sequence() {
  local i=0
  {
    printf '#!/usr/bin/env bash\n'
    printf 'COUNTER_FILE="%s/jq_counter"\n' "$BATS_TEST_TMPDIR"
    printf 'n=0; [[ -f "$COUNTER_FILE" ]] && n=$(cat "$COUNTER_FILE")\n'
    printf 'n=$((n+1)); printf "%%s" "$n" > "$COUNTER_FILE"\n'
    printf 'case $n in\n'
    for val in "$@"; do
      i=$((i+1))
      printf '  %d) printf "%%s\\n" %q ;;\n' "$i" "$val"
    done
    printf '  *) printf "%%s\\n" %q ;;\n' "${!#}"
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
# $2 = exit code for `brew bundle cleanup` (0 = no extras, 1 = extras found)
# $3 = stdout for `brew bundle cleanup` when extras found (optional)
mock_brew_for_status() {
  local check_rc="${1:-0}" cleanup_rc="${2:-0}" cleanup_output="${3:-}"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$2" in\n'
    printf '  check) exit %s ;;\n' "$check_rc"
    printf '  cleanup)\n'
    [[ -n "$cleanup_output" ]] && printf '    printf "%%s\\n" %q\n' "$cleanup_output"
    printf '    exit %s ;;\n' "$cleanup_rc"
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
