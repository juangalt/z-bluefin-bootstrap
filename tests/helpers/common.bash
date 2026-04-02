#!/usr/bin/env bash
# Common setup helpers for the z-bluefin-bootstrap.sh test suite.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$TESTS_DIR/../z-bluefin-bootstrap.sh"

# Load bats-support and bats-assert from vendored submodules.
load "$TESTS_DIR/bats.d/bats-support/load"
load "$TESTS_DIR/bats.d/bats-assert/load"

# Source z-bluefin-bootstrap.sh with main() stubbed so individual functions can be called
# directly. Relies on main "$@" being the last line of the script.
load_bootstrap_functions() {
  # shellcheck disable=SC1090
  source <(head -n -1 "$BOOTSTRAP"; printf 'main() { :; }\n')
}

# Standard environment isolation — call at the top of every setup().
isolate_environment() {
  unset BW_SESSION SSH_AUTH_SOCK SSH_AGENT_PID
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# Create a per-test mock bin dir and prepend it to PATH.
setup_mock_bin() {
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
}
