# z-bluefin-bootstrap

Bluefin laptop bootstrap — provisions SSH keys via Bitwarden, sets hostname, and recovers dotfiles from [z-bluefin-dotfiles](https://github.com/juangalt/z-bluefin-dotfiles).

## Usage

```bash
# Provision GitHub SSH key + git identity
./z-bluefin-bootstrap.sh github

# Load primary SSH key into ssh-agent
eval "$(./z-bluefin-bootstrap.sh primary)"

# Clone and apply dotfiles with chezmoi
./z-bluefin-bootstrap.sh dotfiles

# Do everything at once
eval "$(./z-bluefin-bootstrap.sh all)"
```

## Commands

| Command | Description |
|---|---|
| `github` | Log in + save GitHub SSH key + configure git identity |
| `primary` | Log in + load primary SSH key into ssh-agent (never on disk) |
| `dotfiles` | Clone z-bluefin-dotfiles and apply with chezmoi |
| `all` | Run github + primary + dotfiles in sequence |
| `status` | Show system status (hostname, tailscale, SSH keys, dotfiles) |
| `set-hostname NAME` | Set the system hostname via hostnamectl |
| `help` | Show usage |

## Requirements

- `bw` (Bitwarden CLI)
- `jq`
- `ssh-add`, `ssh-agent`
- `brew` (for auto-installing chezmoi if missing)
