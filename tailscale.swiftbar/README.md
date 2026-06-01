# SwiftBar Tailscale Plugin

This folder is the root for a SwiftBar plugin that controls local Homebrew Tailscale commands from the macOS menubar.

## Files

- `tailscale.10s.sh`: SwiftBar plugin script (refresh every 10 seconds).

## Features

- Use fixed CLI path: `/opt/homebrew/bin/tailscale`
- Run `tailscale up`
- Run `tailscale down`
- Show daemon/connected status in menubar
- Open Tailscale app
- Open command log

## Install

1. Install SwiftBar and tailscale:
   - `brew install --cask swiftbar; brew install tailscale`
2. In SwiftBar settings, set plugin folder to this directory:
   - `swift-bar-tailscale`
3. Make script executable:
   - `chmod +x swift-bar-tailscale/tailscale.10s.sh`
4. Click "Refresh All" in SwiftBar.

## Notes

- This plugin does not start or stop `tailscaled` directly.
- It is designed to work alongside the GUI Tailscale app.
- Logs:
  - `/tmp/tailscale-up-swiftbar.log`
