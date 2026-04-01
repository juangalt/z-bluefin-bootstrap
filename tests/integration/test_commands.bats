#!/usr/bin/env bats
# Integration tests for z-bootstrap.sh commands

BOOTSTRAP="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/z-bootstrap.sh"

setup() {
  load '../helpers/common'
  load '../helpers/mocks'
  isolate_environment
  setup_mock_bin
}

# ── help ─────────────────────────────────────────────────────────────────────

@test "help: shows usage text" {
  run bash "$BOOTSTRAP" help
  assert_success
  assert_output --partial "SSH key provisioning"
  assert_output --partial "github"
  assert_output --partial "primary"
}

@test "--help: shows usage text" {
  run bash "$BOOTSTRAP" --help
  assert_success
  assert_output --partial "SSH key provisioning"
}

@test "unknown command: exits 1" {
  run bash "$BOOTSTRAP" bogus
  assert_failure
  assert_output --partial "Unknown command: bogus"
}

# ── github ───────────────────────────────────────────────────────────────────

@test "github: logs in, saves key, and configures git identity" {
  mock_bw_status unauthenticated
  # jq mock: call 1=vault status, 2=ssh key, 3=git name, 4=git email
  {
    printf '#!/usr/bin/env bash\n'
    printf 'COUNTER_FILE="%s/jq_counter"\n' "$BATS_TEST_TMPDIR"
    printf 'n=0; [[ -f "$COUNTER_FILE" ]] && n=$(cat "$COUNTER_FILE")\n'
    printf 'n=$((n+1)); printf "%%s" "$n" > "$COUNTER_FILE"\n'
    printf 'case $n in\n'
    printf '  1) printf "%%s\\n" "unauthenticated" ;;\n'
    printf '  2) printf "%%s\\n" "-----BEGIN OPENSSH PRIVATE KEY-----" ;;\n'
    printf '  3) printf "%%s\\n" "Test User" ;;\n'
    printf '  4) printf "%%s\\n" "test@example.com" ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
  mock_cmd git 0
  run bash "$BOOTSTRAP" github
  assert_success
  assert_output --partial "BW_SESSION exported"
  assert_output --partial "GitHub SSH key saved"
  assert_output --partial "Git identity configured"
  [[ -f "$HOME/.ssh/github" ]]
  [[ "$(stat -c '%a' "$HOME/.ssh/github")" == "600" ]]
}

# ── primary ──────────────────────────────────────────────────────────────────

@test "primary: logs in and loads key into ssh-agent" {
  mock_bw_status unauthenticated
  {
    printf '#!/usr/bin/env bash\n'
    printf 'COUNTER_FILE="%s/jq_counter"\n' "$BATS_TEST_TMPDIR"
    printf 'n=0; [[ -f "$COUNTER_FILE" ]] && n=$(cat "$COUNTER_FILE")\n'
    printf 'n=$((n+1)); printf "%%s" "$n" > "$COUNTER_FILE"\n'
    printf 'if [[ $n -eq 1 ]]; then printf "%%s\\n" "unauthenticated"; else printf "%%s\\n" "-----BEGIN OPENSSH PRIVATE KEY-----"; fi\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
  mock_cmd ssh-add 0
  mock_ssh_agent
  # run captures stdout (non-TTY), so auto-detect triggers eval mode;
  # progress goes to stderr which run also captures
  run bash "$BOOTSTRAP" primary
  assert_success
  assert_output --partial "BW_SESSION exported"
  assert_output --partial "Primary SSH key loaded"
  assert_output --partial "export SSH_AUTH_SOCK="
}

@test "primary: eval mode exports ssh-agent vars" {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf '"'"'{"status":"unauthenticated"}\n'"'"' ;;\n'
    printf '  login) printf "test-token\\n" ;;\n'
    printf '  get) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'COUNTER_FILE="%s/jq_counter"\n' "$BATS_TEST_TMPDIR"
    printf 'n=0; [[ -f "$COUNTER_FILE" ]] && n=$(cat "$COUNTER_FILE")\n'
    printf 'n=$((n+1)); printf "%%s" "$n" > "$COUNTER_FILE"\n'
    printf 'if [[ $n -eq 1 ]]; then printf "%%s\\n" "unauthenticated"; else printf "%%s\\n" "-----BEGIN OPENSSH PRIVATE KEY-----"; fi\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
  mock_cmd ssh-add 0
  mock_ssh_agent
  run bash -c "bash '$BOOTSTRAP' primary 2>/dev/null"
  assert_success
  assert_output --partial "export SSH_AUTH_SOCK="
  assert_output --partial "hash -r"
}

@test "primary: eval mode sends progress to stderr only" {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf '"'"'{"status":"unauthenticated"}\n'"'"' ;;\n'
    printf '  login) printf "tok\\n" ;;\n'
    printf '  get) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'COUNTER_FILE="%s/jq_counter"\n' "$BATS_TEST_TMPDIR"
    printf 'n=0; [[ -f "$COUNTER_FILE" ]] && n=$(cat "$COUNTER_FILE")\n'
    printf 'n=$((n+1)); printf "%%s" "$n" > "$COUNTER_FILE"\n'
    printf 'if [[ $n -eq 1 ]]; then printf "%%s\\n" "unauthenticated"; else printf "%%s\\n" "-----BEGIN OPENSSH PRIVATE KEY-----"; fi\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
  mock_cmd ssh-add 0
  mock_ssh_agent
  run bash -c "bash '$BOOTSTRAP' primary 2>/dev/null"
  refute_output --partial "Bitwarden Login"
  refute_output --partial "Primary SSH Key"
}

# ── all ──────────────────────────────────────────────────────────────────────

@test "all: runs login + github + git identity + primary and exports vars" {
  mock_bw_status unauthenticated
  # jq mock: 1=vault status, 2=ssh key, 3=git name, 4=git email, 5=primary key
  {
    printf '#!/usr/bin/env bash\n'
    printf 'COUNTER_FILE="%s/jq_counter"\n' "$BATS_TEST_TMPDIR"
    printf 'n=0; [[ -f "$COUNTER_FILE" ]] && n=$(cat "$COUNTER_FILE")\n'
    printf 'n=$((n+1)); printf "%%s" "$n" > "$COUNTER_FILE"\n'
    printf 'case $n in\n'
    printf '  1) printf "%%s\\n" "unauthenticated" ;;\n'
    printf '  2) printf "%%s\\n" "-----BEGIN OPENSSH PRIVATE KEY-----" ;;\n'
    printf '  3) printf "%%s\\n" "Test User" ;;\n'
    printf '  4) printf "%%s\\n" "test@example.com" ;;\n'
    printf '  *) printf "%%s\\n" "-----BEGIN OPENSSH PRIVATE KEY-----" ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
  mock_cmd ssh-add 0
  mock_cmd git 0
  mock_ssh_agent
  # run captures stdout (non-TTY), so auto-detect triggers eval mode;
  # progress goes to stderr which run also captures
  run bash "$BOOTSTRAP" all
  assert_success
  assert_output --partial "BW_SESSION exported"
  assert_output --partial "GitHub SSH key saved"
  assert_output --partial "Git identity configured"
  assert_output --partial "Primary SSH key loaded"
  assert_output --partial "export BW_SESSION="
  assert_output --partial "hash -r"
}

@test "all: eval mode sends progress to stderr only" {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'case "$1" in\n'
    printf '  status) printf '"'"'{"status":"unauthenticated"}\n'"'"' ;;\n'
    printf '  login) printf "all-token\\n" ;;\n'
    printf '  get) exit 0 ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/bw"
  chmod +x "$MOCK_BIN/bw"
  # jq mock: 1=vault status, 2=ssh key, 3=git name, 4=git email, 5=primary key
  {
    printf '#!/usr/bin/env bash\n'
    printf 'COUNTER_FILE="%s/jq_counter"\n' "$BATS_TEST_TMPDIR"
    printf 'n=0; [[ -f "$COUNTER_FILE" ]] && n=$(cat "$COUNTER_FILE")\n'
    printf 'n=$((n+1)); printf "%%s" "$n" > "$COUNTER_FILE"\n'
    printf 'case $n in\n'
    printf '  1) printf "%%s\\n" "unauthenticated" ;;\n'
    printf '  2) printf "%%s\\n" "-----BEGIN OPENSSH PRIVATE KEY-----" ;;\n'
    printf '  3) printf "%%s\\n" "Test User" ;;\n'
    printf '  4) printf "%%s\\n" "test@example.com" ;;\n'
    printf '  *) printf "%%s\\n" "-----BEGIN OPENSSH PRIVATE KEY-----" ;;\n'
    printf 'esac\n'
  } > "$MOCK_BIN/jq"
  chmod +x "$MOCK_BIN/jq"
  mock_cmd ssh-add 0
  mock_cmd git 0
  mock_ssh_agent
  run bash -c "bash '$BOOTSTRAP' all 2>/dev/null"
  assert_success
  assert_output --partial "export BW_SESSION="
  assert_output --partial "hash -r"
  refute_output --partial "Bitwarden Login"
  refute_output --partial "GitHub SSH key saved"
}
