# CLAUDE.md

## Public repository

This repo is **public**. Never commit secrets, credentials, API keys, private keys, or personal information. Bitwarden item names are acceptable (they are not secrets), but actual key material must never appear in code, tests, or git history.

## What this repo is

`z-bluefin-bootstrap` is a Bash CLI tool that orchestrates the setup of a new Bluefin laptop (assumes Bluefin DX is installed). It provisions SSH keys via Bitwarden, sets the hostname, and recovers dotfiles/configuration from the `z-bluefin-dotfiles` repo.

## CLI

The only executable is `z-bluefin-bootstrap.sh`. Commands:

```bash
./z-bluefin-bootstrap.sh status [--details]              # Check current state (--details lists packages & dconf areas)
./z-bluefin-bootstrap.sh set-hostname my-laptop         # Set system hostname
./z-bluefin-bootstrap.sh install github-key             # Save GitHub SSH key
./z-bluefin-bootstrap.sh install dotfiles               # Clone z-bluefin-dotfiles + chezmoi apply
./z-bluefin-bootstrap.sh install packages               # Install brew packages + flatpaks from Brewfile
./z-bluefin-bootstrap.sh install dconf                  # Load saved GNOME dconf settings from ini files
./z-bluefin-bootstrap.sh install all                    # Run github-key + dotfiles + packages + dconf in one shot
./z-bluefin-bootstrap.sh push packages                  # Dump current brew/flatpak state to Brewfile and push
./z-bluefin-bootstrap.sh push dotfiles                  # Re-add local dotfile changes to chezmoi source and push
./z-bluefin-bootstrap.sh push dconf                     # Dump live GNOME dconf settings to ini files and push
eval "$(./z-bluefin-bootstrap.sh recovery-key)"         # Load recovery key into ssh-agent
```

## Key design constraints

- Each command handles Bitwarden login internally — no separate login step.
- **GitHub key is written to disk** at `~/.ssh/github` with 600 permissions.
- **Recovery key is never written to disk** — loaded into ssh-agent only.
- `recovery-key` auto-detects eval mode (non-TTY stdout) and exports ssh-agent variables.
- `chezmoi` is auto-installed via `brew` if missing.

## Three tracking systems

The dotfiles repo (`~/z-bluefin-dotfiles`) tracks configuration via three separate mechanisms, each with its own apply, drift-detection, and push method:

| | **Dotfiles** (chezmoi) | **Packages** (Brewfile) | **GNOME settings** (dconf) |
|---|---|---|---|
| **What** | Shell configs, gitconfig, XDG configs | Brew formulae, casks, flatpaks | Ptyxis terminal, keybindings, extensions |
| **Storage** | `dot_*`, `private_dot_*` files | `Brewfile` | `gnome/*.ini` files |
| **Apply** | `chezmoi init --apply` | `brew bundle install` | `install dconf` (`dconf load`) |
| **Detect drift** | `chezmoi status` (built-in) | `brew bundle check` + `brew bundle cleanup` | Per-key `dconf read` vs saved ini values |
| **Push changes** | `push dotfiles` → `chezmoi re-add` | `push packages` → `brew bundle dump` | `push dconf` → selective per-key update |
| **In `.chezmoiignore`?** | No (chezmoi manages these) | Yes | Yes |

### Why three systems instead of one

Chezmoi manages regular dotfiles natively (file → file copies). But `Brewfile` and `gnome/*.ini` are not dotfiles deployed to `~/` — they are reference files that feed other tools (`brew bundle`, `dconf load`). They live in the dotfiles repo for convenience but are in `.chezmoiignore` so chezmoi doesn't try to deploy them.

### dconf specifics

- The ini-to-dconf-path mapping is defined in `DCONF_MAP` in `z-bluefin-bootstrap.sh`. Update it when adding a new `.ini` file.
- `desktop.ini` uses root dconf path `/` which cannot be round-tripped (`dconf dump /` returns the entire database). It is excluded from install, drift detection, and push.
- `push dconf` does a selective per-key update: it reads each key's live value and writes it back to the ini file, preserving the file's curated key set. A naive `dconf dump` would pollute the file with system-managed keys.

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
