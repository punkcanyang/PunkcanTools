# Repository Guidelines

## Project Structure & Module Organization

This repository is a Bash-based collection of one-click VPN/proxy installers. The root scripts (`install.sh`, `install-centos.sh`, `uninstall.sh`, `uninstall-centos.sh`, `show-config.sh`, `health-check.sh`) cover the default VLESS + Reality setup. Each protocol directory follows the same layout:

- `vless-ws/`, `hysteria2/`, `tuic-v5/`, `trojan/`, `trojan-go/`
- `shadowsocks/`, `shadowsocks-2022/`, `wireguard/`, `openvpn/`, `ikev2/`, `ipsec/`
- Per protocol: `install.sh`, `install-centos.sh`, `uninstall.sh`, `uninstall-centos.sh`, and usually `show-config.sh`

Documentation lives in `README.md`, `README.en.md`, `TODO.md`, and `WORKLOG.md`. Keep docs synchronized when behavior, supported OS versions, ports, or generated config paths change.

## Build, Test, and Development Commands

There is no compile step. Use these commands from the repository root:

```bash
chmod +x *.sh */*.sh
bash -n *.sh */*.sh
shellcheck *.sh */*.sh
```

`bash -n` is the required syntax check. `shellcheck` is recommended when available. Run installer scripts only on disposable VMs/VPS instances with root access, for example `sudo bash vless-ws/install.sh` on Debian/Ubuntu or `sudo bash vless-ws/install-centos.sh` on RHEL-compatible systems.

## Coding Style & Naming Conventions

Use Bash with `#!/bin/bash` and `set -e`. Keep 4-space indentation inside functions and conditionals. Use uppercase names for configuration constants such as `PORT`, `XRAY_CONFIG_DIR`, and `CLIENT_CONFIG_FILE`; use lowercase snake_case for functions such as `check_root`, `install_dependencies`, and `print_banner`. Preserve the existing logging helpers (`log_info`, `log_warn`, `log_error`, `log_success`) and banner style when adding scripts.

When adding a protocol, keep Debian/Ubuntu and CentOS/RHEL scripts paired, and update README tables plus `TODO.md` or `WORKLOG.md`.

## Testing Guidelines

Before submitting changes, run:

```bash
bash -n *.sh */*.sh
```

For behavioral changes, test on the target distribution and record the OS version, command used, installed service status, firewall change, and generated client config path. Redact UUIDs, passwords, private keys, domains, and share links from logs.

## Commit & Pull Request Guidelines

Git history includes both generic `update` commits and clearer prefixes such as `docs:` and `feat:`. Prefer specific Conventional Commit-style messages: `fix: handle occupied vless-ws port`, `docs: update CentOS install notes`, or `feat: add wireguard client helper`.

Pull requests should include a short summary, affected protocols, affected distributions, validation commands, and any manual VM/VPS test results. Link related issues or TODO items when available.

## Security & Configuration Tips

Do not commit generated client configs, QR codes, private keys, certificates, passwords, server IPs, or live share links. Treat every script as root-level infrastructure code: keep destructive operations explicit, scoped, and documented.
