# z-bluefin-bootstrap

Bluefin laptop bootstrap — provisions SSH keys via Bitwarden, sets hostname, and recovers dotfiles from [z-bluefin-dotfiles](https://github.com/juangalt/z-bluefin-dotfiles).

## Quick start

```bash
# Step by step:
./z-bluefin-bootstrap.sh status
./z-bluefin-bootstrap.sh set-hostname my-laptop
./z-bluefin-bootstrap.sh github
./z-bluefin-bootstrap.sh dotfiles

# Or all at once:
./z-bluefin-bootstrap.sh all

# Optional — load primary SSH key into agent:
eval "$(./z-bluefin-bootstrap.sh primary)"
```

## Commands

| Command | Description |
|---|---|
| `status` | Show current state (hostname, SSH keys, dotfiles, git) |
| `set-hostname <name>` | Set the system hostname via hostnamectl |
| `github` | Save GitHub SSH key to `~/.ssh/github` + configure git identity |
| `dotfiles` | Clone z-bluefin-dotfiles and apply with chezmoi |
| `all` | Run github + dotfiles in one shot |
| `primary` | Load primary SSH key into ssh-agent (optional, needs eval) |
| `help` | Show usage |

## Requirements

- `bw` (Bitwarden CLI)
- `jq`
- `ssh-add`, `ssh-agent`
- `brew` (for auto-installing chezmoi if missing)
