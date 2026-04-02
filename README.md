# z-bluefin-bootstrap

Bluefin laptop bootstrap — provisions SSH keys via Bitwarden, sets hostname, installs dotfiles and packages from [z-bluefin-dotfiles](https://github.com/juangalt/z-bluefin-dotfiles).

## Quick start

```bash
./z-bluefin-bootstrap.sh status
./z-bluefin-bootstrap.sh set-hostname my-laptop
./z-bluefin-bootstrap.sh install github-key
./z-bluefin-bootstrap.sh install dotfiles
./z-bluefin-bootstrap.sh install packages

# Or all at once:
./z-bluefin-bootstrap.sh install all

# Load recovery SSH key into agent:
eval "$(./z-bluefin-bootstrap.sh recovery-key)"
```

## Commands

| Command | Description |
|---|---|
| `status` | Show current state (hostname, SSH keys, dotfiles, brew packages) |
| `set-hostname <name>` | Set the system hostname via hostnamectl |
| `install github-key` | Save GitHub SSH key to `~/.ssh/github` (requires Bitwarden) |
| `install dotfiles` | Clone z-bluefin-dotfiles and apply config files with chezmoi |
| `install packages` | Install brew packages and flatpaks from Brewfile |
| `install all` | Run github-key + dotfiles + packages in one shot (requires Bitwarden) |
| `recovery-key` | Load recovery SSH key into ssh-agent (needs eval) |
| `help` | Show usage |

## Requirements

- [Bluefin](https://projectbluefin.io/) with CLI Bling enabled (`ujust bluefin-cli`) and Developer Mode (`ujust devmode`) for Bluefin DX tooling
- `bw` (Bitwarden CLI)
- `jq`
- `ssh-add`, `ssh-agent`
- `brew` (for auto-installing chezmoi if missing, and for package installation)

## Architecture

```
bootstrap  = orchestrator: SSH keys, hostname, clone repo, invoke chezmoi, install packages
dotfiles   = source of truth: configs, Brewfile (data only)
chezmoi    = engine: applies config files
```
