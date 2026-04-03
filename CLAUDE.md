# CLAUDE.md

## Public repository

This repo is **public**. Never commit secrets, credentials, API keys, private keys, or personal information. Bitwarden item names are acceptable (they are not secrets), but actual key material must never appear in code, tests, or git history.

## What this repo is

`z-bluefin-bootstrap` is a Bash CLI tool that orchestrates the setup of a new Bluefin laptop (assumes Bluefin DX is installed). It provisions SSH keys via Bitwarden, sets the hostname, and recovers dotfiles/configuration from the `z-bluefin-dotfiles` repo.

## CLI

The only executable is `z-bluefin-bootstrap.sh`. Commands:

```bash
./z-bluefin-bootstrap.sh status [--details]              # Check current state (--details lists packages)
./z-bluefin-bootstrap.sh set-hostname my-laptop         # Set system hostname
./z-bluefin-bootstrap.sh install github-key             # Save GitHub SSH key
./z-bluefin-bootstrap.sh install dotfiles               # Clone z-bluefin-dotfiles + chezmoi apply
./z-bluefin-bootstrap.sh install packages               # Install brew packages + flatpaks from Brewfile
./z-bluefin-bootstrap.sh install all                    # Run github-key + dotfiles + packages in one shot
./z-bluefin-bootstrap.sh push packages                  # Dump current brew/flatpak state to Brewfile and push
./z-bluefin-bootstrap.sh push dotfiles                  # Re-add local dotfile changes to chezmoi source and push
eval "$(./z-bluefin-bootstrap.sh recovery-key)"         # Load recovery key into ssh-agent
```

## Key design constraints

- Each command handles Bitwarden login internally — no separate login step.
- **GitHub key is written to disk** at `~/.ssh/github` with 600 permissions.
- **Recovery key is never written to disk** — loaded into ssh-agent only.
- `recovery-key` auto-detects eval mode (non-TTY stdout) and exports ssh-agent variables.
- **Dotfiles** are cloned from `git@github.com:juangalt/z-bluefin-dotfiles.git` to `~/z-bluefin-dotfiles` and applied via `chezmoi init --source ... --apply`.
- **Packages** are installed by bootstrap via `brew bundle install` from the Brewfile in the dotfiles repo (not by chezmoi run scripts).
- `chezmoi` is auto-installed via `brew` if missing.

## Bitwarden items

| Command | Item name | JSON path |
|---|---|---|
| `install github-key` | `ssh-access service key: github` | `.sshKey.privateKey` |
| `recovery-key` | `SSH Key - id_ed25519 - PRIMARY/RECOVERY` | `.sshKey.privateKey` |

## Testing

```bash
bats tests/unit/ tests/integration/     # Run all tests
bats tests/unit/test_github.bats        # Run a single file
bats --filter "save_github" tests/unit/ # Filter by test name
```

- **BATS** with **bats-support** and **bats-assert** vendored as git submodules in `tests/bats.d/`
- All external tools are mocked via PATH prepend — no real system calls in tests
- Tool-absent tests save/restore PATH around `run` to avoid breaking BATS cleanup
