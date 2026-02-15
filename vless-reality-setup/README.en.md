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

### Uninstall

```bash
# Debian/Ubuntu
sudo bash uninstall.sh

# CentOS/RHEL
sudo bash uninstall-centos.sh
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
└── README.md           # Documentation
```

Installed commands:
- `xray-show-config` - View config and QR code
- `xray-uninstall.sh` - Uninstall script

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
