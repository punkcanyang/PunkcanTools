# VLESS + Reality One-Click Installation Script

One-click deployment of VLESS + Reality proxy server on Debian/Ubuntu or CentOS/RHEL systems.

## Features

- 🚀 One-click install Xray-core + VLESS + Reality
- 🔐 Auto-generate keys and user configuration
- 🛡️ Auto-configure firewall
- ⚡ Enable BBR acceleration
- 📋 Auto-generate client config, share link and QR code
- 🔍 Easy config viewing: `xray-show-config` command
- 🔄 Scheduled health check and auto-restart

## System Requirements

| OS | Supported Versions |
|----|-------------------|
| Debian | 11 / 12 / 13 |
| Ubuntu | 20.04 / 22.04 / 24.04 |
| CentOS | 8 / 9 |
| RHEL / Rocky / Alma | 8 / 9 |

- Root access
- Network connection
- Installers install protocol dependencies automatically. IKEv2, IPsec, WireGuard, and OpenVPN explicitly install commonly missing minimal-image tools such as `curl`, `openssl`, `iproute2`/`iproute`, `iptables`, and `procps`/`procps-ng`.

## Quick Start

### Debian / Ubuntu Installation

```bash
# Download script
git clone https://github.com/punkcanyang/PunkcanTools.git
cd PunkcanTools/vless-reality-setup

# Make executable
chmod +x *.sh

# Run installation
sudo bash install.sh
```

### CentOS / RHEL Installation

```bash
# Download script
git clone https://github.com/punkcanyang/PunkcanTools.git
cd PunkcanTools/vless-reality-setup

# Make executable
chmod +x *.sh

# Run installation (CentOS version)
sudo bash install-centos.sh
```

## AI Automation Scope

The first AI automation target is VLESS + Reality only. Other protocols remain manual-first until this command flow is stable.

- Remote protocol: VLESS + Reality
- Remote core: Xray-core
- Local client core: Xray-core
- Local client platforms: macOS + Linux
- Output contract: fixed JSON/YAML schema, plus the existing `vless://` share link
- Multi-line failover: multiple VLESS + Reality nodes ordered by manual priority, connectivity, latency, then failure count

The installer preserves SSH firewall access before enabling firewall rules. If an existing Xray config is detected, the installer stops by default to avoid overwriting another protocol. Use `--replace` only when replacement is intentional:

```bash
sudo bash install.sh --replace
sudo bash install-centos.sh --replace
```

Xray-backed protocols currently share `/usr/local/etc/xray/config.json` and the same `xray` systemd service; they are not installed side by side yet. VLESS + Reality, VLESS WS, Trojan, Shadowsocks, and SS-2022 write `/usr/local/etc/xray/vrs-protocol` as an ownership marker. Installers stop on a different or missing marker unless `--replace` is passed. Uninstallers stop on a different or missing marker unless `--force` is passed.

Automation-friendly examples:

```bash
sudo bash install.sh --yes --port 443 --dest www.microsoft.com --dest-port 443 --json
sudo bash install-centos.sh --yes --port 443 --dest www.microsoft.com --dest-port 443 --json
```

Supported automation flags:

| Flag | Description |
|------|-------------|
| `--port PORT` | Set VLESS listen port; if explicitly set and occupied, installation fails |
| `--dest HOST` | Set Reality destination and SNI |
| `--dest-port PORT` | Set Reality destination port |
| `--uuid UUID` | Use a fixed client UUID |
| `--short-id HEX` | Use a fixed Reality short ID |
| `--server-ip IP` | Use a fixed server address in client output |
| `--json` | Print JSON contract after installation |
| `--yaml` | Print YAML contract after installation |
| `--yes`, `--non-interactive` | Do not prompt; fail on risky conditions |
| `--replace` | Explicitly allow replacing an existing Xray config |

Generated machine-readable outputs:

- `/usr/local/etc/xray/vless-reality.json`
- `/usr/local/etc/xray/vless-reality.yaml`
- `/usr/local/etc/xray/vless-link.txt`
- `/usr/local/etc/xray/client-config.txt`

Formal contract files:

- `docs/ai-contract/vless-reality.schema.json`
- `docs/ai-contract/vless-reality.example.json`
- `docs/ai-contract/vless-reality.example.yaml`

Mask real `uuid`, `publicKey`, `shortId`, `shareLink`, and real server addresses in logs, issues, pull requests, and chat reports.

## Local Command Line Client

P2 adds `client/vrs-client.sh`. It imports the remote `vless-reality.json` contract, generates a local Xray client config, and provides basic start, stop, restart, status, log, export, list, and connectivity-check commands. The first version supports VLESS + Reality only on macOS and Linux.

Install Xray-core locally first and ensure `xray` is in `PATH`; or set `XRAY_BIN=/path/to/xray`.

```bash
# Install or check local Xray-core
bash client/vrs-client.sh install-core
bash client/vrs-client.sh check-core

# Import the JSON contract fetched from the server; lower priority wins
bash client/vrs-client.sh import ./vless-reality.json --name my-node --priority 10

# Select a route; this writes current, starts the connection, and checks connectivity
bash client/vrs-client.sh use --name my-node

# Auto-select a route by priority, connectivity, latency, and failure count
bash client/vrs-client.sh auto-use

# Run one health-check pass; auto-select if current route is unavailable
bash client/vrs-client.sh watch --once

# Run foreground watcher; periodically checks current and reconnects/switches if needed
bash client/vrs-client.sh watch --interval 60

# Show current route, status, and local proxy ports
bash client/vrs-client.sh current
bash client/vrs-client.sh status
bash client/vrs-client.sh list --sorted

# Check connectivity through the local SOCKS proxy
bash client/vrs-client.sh check

# Stop local proxy
bash client/vrs-client.sh stop

# Install as a user-level background service
bash client/vrs-client.sh service install --name my-node
bash client/vrs-client.sh service status --name my-node
bash client/vrs-client.sh service uninstall --name my-node

# Install watcher as a user-level background service
bash client/vrs-client.sh watch-service install --interval 60
bash client/vrs-client.sh watch-service status
bash client/vrs-client.sh watch-service uninstall
```

Default local ports:

| Type | Address |
|------|---------|
| SOCKS | `127.0.0.1:10808` |
| HTTP | `127.0.0.1:10809` |

The default local state directory is `$HOME/.vrs/client`. Override it with `VRS_CLIENT_HOME=/path/to/client-state`. Named profiles are already supported; future failover work will add ordering by manual priority, connectivity, latency, and failure count.

Multi-route metadata is stored in `$HOME/.vrs/client/profiles/index.json`. A successful `check` writes `lastStatus=online`, `latencyMs`, and resets `failureCount`; a failed check writes `lastStatus=offline` and increments `failureCount`.

`auto-use` reads all `enabled=true` profiles, sorts them by `priority`, `lastStatus`, `latencyMs`, `failureCount`, and name, then tries each candidate. The first route that starts and passes connectivity check becomes current; if all candidates fail, the command exits non-zero.

`install-core` uses Homebrew `brew install xray` on macOS. On Linux it also prefers Homebrew; if Homebrew is unavailable, it downloads and runs the official XTLS `Xray-install` script to install Xray-core.

`service` uses `~/Library/LaunchAgents/io.punkcan.vrs.<name>.plist` on macOS and a `systemd --user` unit named `vrs-client-<name>.service` on Linux. Service mode runs Xray in the foreground and lets launchd/systemd handle restarts.

`watch` periodically checks the current profile. If current is unavailable, it calls `auto-use` to reconnect or switch routes. `watch-service` uses `~/Library/LaunchAgents/io.punkcan.vrs.watch.plist` on macOS and a `systemd --user` unit named `vrs-client-watch.service` on Linux. Watcher logs are written to `$HOME/.vrs/client/logs/watcher.log`.

### Uninstall

```bash
# Debian/Ubuntu
sudo bash uninstall.sh

# CentOS/RHEL
sudo bash uninstall-centos.sh
```

For Xray-backed protocol directories, use the matching uninstall script. The script removes Xray only when `/usr/local/etc/xray/vrs-protocol` matches that protocol. Use `--force` only when intentional:

```bash
sudo bash <protocol-dir>/uninstall.sh --force
```

## Configuration

After installation, the following files are automatically generated:

| File | Description |
|------|-------------|
| `/usr/local/etc/xray/vless-link.txt` | 🔗 Pure VLESS share link (easy to copy) |
| `/usr/local/etc/xray/vless-qrcode.png` | 📱 QR code image (easy to scan) |
| `/usr/local/etc/xray/client-config.txt` | 📄 Complete configuration info |

The configuration includes:
- Server connection info
- VLESS share link (can be imported directly to client)
- JSON format config

## File Structure

```
vless-reality-setup/
├── install.sh          # Debian/Ubuntu install script
├── install-centos.sh   # CentOS/RHEL install script
├── uninstall.sh        # Debian/Ubuntu uninstall script
├── uninstall-centos.sh # CentOS/RHEL uninstall script
├── health-check.sh     # Health check script (universal)
├── show-config.sh      # Config viewer script (universal)
├── client/
│   └── vrs-client.sh   # Local Xray command line client
├── docs/
│   └── ai-contract/    # AI automation JSON/YAML contract
└── README.md           # Documentation
```

Installed commands:
- `xray-show-config` - View config and QR code
- `xray-uninstall.sh` - Uninstall script

## Development Validation

```bash
bash -n *.sh */*.sh
bash client/test-vrs-client.sh
```

`client/test-vrs-client.sh` is an offline regression test. It does not require a real Xray-core binary or a live remote node. It uses a temporary state directory under `/private/tmp` and verifies local CLI import, index state, generated Xray config, failure-path status writes, `auto-use`, and `watch --once`.

## Firewall And SSH Safety

Before changing UFW, firewalld, or iptables rules, installer scripts try to detect and preserve SSH TCP access. Detection uses the current `SSH_CONNECTION`, `sshd -T`, `/etc/ssh/sshd_config`, plus default `22/tcp`.

This is applied to VLESS + Reality and the protocol directories `vless-ws/`, `hysteria2/`, `tuic-v5/`, `trojan/`, `trojan-go/`, `shadowsocks/`, `shadowsocks-2022/`, `wireguard/`, `openvpn/`, `ikev2/`, and `ipsec/` on Debian/Ubuntu and CentOS/RHEL installers.

## Sensitive Output Permissions

Generated client configs, share links, server configs, VPN client files, private keys, PSKs, and password-bearing outputs are tightened to `chmod 600` where applicable. Directories storing VPN client files are tightened to `chmod 700`. Treat these files as live connection credentials and redact them from logs, issues, pull requests, and chat reports.

## Share Link Encoding

Hysteria2, TUIC v5, Trojan, and Trojan-Go share links use the repository's Bash URI encoder for passwords and WebSocket paths. This prevents `/`, `+`, `=`, spaces, and similar characters from breaking `://userinfo@host` or query parameters, without requiring `python3`.

## Common Commands

```bash
# View config and QR code
xray-show-config

# View VLESS share link only
xray-show-config --link

# Show QR code in terminal only
xray-show-config --qr

# View config file paths
xray-show-config --path

# Check service status
systemctl status xray

# View real-time logs
journalctl -u xray -f

# Restart service manually
systemctl restart xray

# Copy link to local (scp)
scp root@server-ip:/usr/local/etc/xray/vless-link.txt ./
```

## Default Configuration

| Item | Default Value |
|------|---------------|
| Port | 443 |
| Protocol | VLESS + Reality |
| SNI | www.microsoft.com |
| Flow | xtls-rprx-vision |

## Security

- Reality protocol provides stronger anti-detection
- Uses x25519 elliptic curve encryption
- Recommended to update Xray-core regularly

## Recommended Clients

| Platform | Recommended Clients |
|----------|-------------------|
| Windows | V2rayN, Clash Verge |
| macOS | V2rayU, ClashX Pro |
| iOS | Shadowrocket, Stash |
| Android | V2rayNG, Clash for Android |
| Linux | v2rayA, Clash |

## FAQ

### Connection Failed

1. Check if server firewall has port 443 open
2. Check if Xray service is running: `systemctl status xray`
3. Check client config, especially Public Key and Short ID

### Slow Speed

1. Confirm BBR is enabled: `sysctl net.ipv4.tcp_congestion_control`
2. Check server bandwidth limits
3. Try changing client fingerprint

### Manually Generate Client Config

If installation was interrupted or you need to regenerate client config:

**1. Get UUID and Short ID from server config:**
```bash
cat /usr/local/etc/xray/config.json | jq '.inbounds[0].settings.clients[0].id'
cat /usr/local/etc/xray/config.json | jq '.inbounds[0].streamSettings.realitySettings.shortIds[0]'
```

**2. Get Public Key from Private Key:**
```bash
# View Private Key first
PRIVATE_KEY=$(cat /usr/local/etc/xray/config.json | jq -r '.inbounds[0].streamSettings.realitySettings.privateKey')
echo "Private Key: $PRIVATE_KEY"

# Get Public Key
/usr/local/bin/xray x25519 -i "$PRIVATE_KEY"
# The Password in output is the Public Key
```

**3. Generate VLESS share link:**
```
vless://UUID@server-ip:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&headerType=none#VLESS-Reality
```

**4. Import to client:**
- **Shadowrocket**: Copy link → Open App → Click "+" → Import from clipboard
- **V2rayN**: Copy link → Server → Import from clipboard
- **Clash**: Need to convert to Clash format config

## License

MIT License
