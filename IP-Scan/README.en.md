# IP-Scan

A cross-platform network IP scanning desktop application built with Tauri 2.0.

## Features

- 🔍 Scan network ranges (CIDR format, e.g., 192.168.1.0/24)
- 📡 ICMP ping detection for active hosts
- 🔌 Port scanning (24 common ports)
- 💓 OS fingerprinting (based on TTL)
- 🖥️ Device type identification
- 📊 Real-time progress display

## Quick Start

### Development Mode
```bash
npm install
npm run tauri dev
```

### Build for Release
```bash
npm run tauri build
```

## Tech Stack

- **Framework**: Tauri 2.0
- **Backend**: Rust (pnet, surge-ping, tokio)
- **Frontend**: HTML + CSS + JavaScript

## Notes

- Some scanning features (like ICMP ping) may require administrator privileges
- Please only use on authorized networks
