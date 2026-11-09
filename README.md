# tailgum

A lightweight, interactive Terminal User Interface (TUI) built with **Bash**, **Gum**, and **JQ** to manage your Tailscale connection and switch Exit Nodes (with local LAN access enabled) without memorizing or typing long CLI commands.

## ✨ Features

- **Single-Prompt Privilege Elevation**: Automatically elevates permissions on startup via `exec sudo "$0" "$@"`, making it seamless even on systems configured with `sudo` `timestamp_timeout=0`.
- **Automatic Daemon Recovery**: Checks if `tailscaled` is running via `systemd` and starts both the service and the tailnet (`tailscale up`) automatically if stopped.
- **Live JSON State Parsing**: Queries `tailscale status --json` in real time using `jq` to separate **Online** and **Offline** Exit Nodes clearly.
- **LAN-Safe Exit Node Switching**: Connects to your chosen Exit Node with `--exit-node-allow-lan-access=true` automatically applied so you never lose access to your local network devices (NAS, routers, printers, etc.).
- **Clean TUI Experience**: Powered by Charmbracelet's `gum` with loading spinners, styled status boxes, and keyboard-driven navigation.

---

## 📦 Prerequisites

Before using `tailgum`, make sure you have **`tailscale`**, **`gum`**, and **`jq`** installed on your system.

### Arch Linux
```bash
sudo pacman -S tailscale gum jq
```

### Debian / Ubuntu
```bash
# 1. Install Tailscale (if not already installed)
curl -fsSL https://tailscale.com/install.sh | sh

# 2. Add Charm repository for Gum & install Gum + JQ
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install -y gum jq
```

### Fedora
```bash
# 1. Add Charm repository for Gum
echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo

# 2. Install Tailscale, Gum, and JQ
sudo dnf install -y tailscale gum jq
```

---

## 🚀 Installation & Usage

1. Create `~/.local/bin` (if it doesn't exist) and download the script directly:

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/tailgum/main/tailgum -o ~/.local/bin/tailgum
```

2. Make the script executable:

```bash
chmod +x ~/.local/bin/tailgum
```

3. Run it from anywhere in your terminal:

```bash
tailgum
```

*(Note: If `~/.local/bin` is not in your `$PATH`, add `export PATH="$HOME/.local/bin:$PATH"` to your `~/.bashrc` or `~/.zshrc`).*

---

## ⚠️ Disclaimer & License

This tool was originally created for personal use and is shared with the community **"as-is"**, without warranty of any kind. Feel free to fork, modify, and adapt it to your own workflow.

Released under the [MIT License](LICENSE).
