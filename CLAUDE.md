# CLAUDE.md

## What this repo is

`z-bootstrap` is a standalone Bash CLI tool that provisions SSH keys via Bitwarden. It extracts the identity/key management logic from `z-workstation`'s Layer 1 into a focused, independent tool.

## CLI

The only executable is `z-bootstrap.sh`. Commands:

```bash
./z-bootstrap.sh github                         # Log in + save GitHub SSH key + configure git identity
./z-bootstrap.sh primary                        # Log in + load primary key into ssh-agent
eval "$(./z-bootstrap.sh primary)"              # Same, with ssh-agent vars in host shell
eval "$(./z-bootstrap.sh all)"                  # Run github + primary with env export
```

## Key design constraints

- Each command handles Bitwarden login internally — no separate login step.
- **GitHub key is written to disk** at `~/.ssh/github` with 600 permissions.
- **Primary key is never written to disk** — loaded into ssh-agent only.
- `primary` and `all` auto-detect eval mode (non-TTY stdout) and export ssh-agent variables.

## Bitwarden items

| Command | Item name | JSON path |
|---|---|---|
| `github` | `ssh-access service key: github` | `.sshKey.privateKey` |
| `github` | `git-identity` | `.login.username` (name), `.login.password` (email) |
| `primary` | `SSH Key - id_ed25519 - PRIMARY/RECOVERY` | `.sshKey.privateKey` |

## Testing

```bash
bats tests/unit/ tests/integration/     # Run all tests
bats tests/unit/test_github.bats        # Run a single file
bats --filter "save_github" tests/unit/ # Filter by test name
```

- **BATS** with **bats-support** and **bats-assert** vendored as git submodules in `tests/bats.d/`
- All external tools are mocked via PATH prepend — no real system calls in tests
- Tool-absent tests save/restore PATH around `run` to avoid breaking BATS cleanup
