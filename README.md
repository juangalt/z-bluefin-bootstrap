# z-bluefin-bootstrap

Bluefin laptop bootstrap — provisions SSH keys via Bitwarden, sets hostname, installs dotfiles and packages from [z-bluefin-dotfiles](https://github.com/juangalt/z-bluefin-dotfiles).

## Quick start

```bash
./z-bluefin-bootstrap.sh status
./z-bluefin-bootstrap.sh set-hostname my-laptop
./z-bluefin-bootstrap.sh install github-key
./z-bluefin-bootstrap.sh install dotfiles
./z-bluefin-bootstrap.sh install packages
./z-bluefin-bootstrap.sh install dconf

# Or all at once:
./z-bluefin-bootstrap.sh install all

# Load recovery SSH key into agent:
eval "$(./z-bluefin-bootstrap.sh recovery-key)"

# Push local changes back to the dotfiles repo:
./z-bluefin-bootstrap.sh push dotfiles
./z-bluefin-bootstrap.sh push packages
./z-bluefin-bootstrap.sh push dconf
```

## Commands

| Command | Description |
|---|---|
| `status` | Show current state (dependencies, SSH, dotfiles, chezmoi drift, dconf drift, brew) |
| `set-hostname <name>` | Set the system hostname via hostnamectl |
| `install github-key` | Save GitHub SSH key to `~/.ssh/github` (requires Bitwarden) |
| `install dotfiles` | Clone z-bluefin-dotfiles and apply config files with chezmoi |
| `install packages` | Install brew packages and flatpaks from Brewfile |
| `install dconf` | Load saved GNOME dconf settings from ini files |
| `install all` | Run github-key + clone repo + packages + dotfiles + dconf (requires Bitwarden) |
| `push dotfiles` | Re-add local dotfile changes to chezmoi source and push |
| `push packages` | Dump current brew/flatpak state to Brewfile and push |
| `push dconf` | Dump live GNOME dconf settings to ini files and push |
| `recovery-key` | Load recovery SSH key into ssh-agent (needs eval) |
| `help` | Show usage |

## How it tracks configuration

The dotfiles repo tracks three types of configuration. Each uses a different tool chain for applying, detecting drift, and pushing changes.

### Dotfiles (chezmoi)

Shell configs, gitconfig, and XDG configs stored as `dot_*` / `private_dot_*` files. Chezmoi manages these natively — it copies them to `~/` and can detect when they've changed.

- **Apply:** `chezmoi init --apply`
- **Drift:** `chezmoi status` (built-in)
- **Push:** `push dotfiles` runs `chezmoi re-add` to sync changes back to the source repo

### Packages (Brewfile)

Brew formulae, casks, and flatpaks listed in `Brewfile`. This file is in `.chezmoiignore` — it lives in the dotfiles repo but chezmoi doesn't deploy it to `~/`.

- **Apply:** `brew bundle install`
- **Drift:** `brew bundle check` (missing) + `brew bundle cleanup` (extra)
- **Push:** `push packages` runs `brew bundle dump` to capture the current state

### GNOME settings (dconf)

Ptyxis terminal, keyboard shortcuts, and extension configs saved as `gnome/*.ini` files. Also in `.chezmoiignore`. Applied via `install dconf` which calls `dconf load`.

- **Apply:** `install dconf` (`dconf load <path>`)
- **Drift:** per-key `dconf read` compared against saved ini values
- **Push:** `push dconf` reads each tracked key's live value and writes it back to the ini file, preserving the curated key set (a full `dconf dump` would include system-managed keys not in the file)

### The `status` command

`status` checks all three systems in one pass and reports what's out of sync, including specific file names, package names, and dconf areas.

## Requirements

- [Bluefin](https://projectbluefin.io/) with CLI Bling enabled (`ujust bluefin-cli`) and Developer Mode (`ujust devmode`) for Bluefin DX tooling
- `bw` (Bitwarden CLI)
- `jq`
- `ssh-add`, `ssh-agent`
- `brew` (for auto-installing chezmoi if missing, and for package installation)
- `dconf` (for GNOME settings drift detection — automatically available on GNOME desktops)
