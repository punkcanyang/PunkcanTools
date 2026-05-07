# AI Contract - VLESS + Reality

本目录定义 VRS 第一版 AI 自动部署合约。第一版只支援根目录 VLESS + Reality，server 端与本地 command line client 都以 Xray-core 为核心。

## 文件

- `vless-reality.schema.json`: JSON Schema，定义安装完成后的机器可读输出。
- `vless-reality.example.json`: JSON 输出范例，对应 `/usr/local/etc/xray/vless-reality.json`。
- `vless-reality.example.yaml`: YAML 输出范例，对应 `/usr/local/etc/xray/vless-reality.yaml`。

## 安装命令

Debian / Ubuntu:

```bash
sudo bash install.sh --yes --port 443 --dest www.microsoft.com --dest-port 443 --json
```

CentOS / RHEL:

```bash
sudo bash install-centos.sh --yes --port 443 --dest www.microsoft.com --dest-port 443 --json
```

若已存在 Xray 配置，脚本会停止，避免覆盖其他协议。确认要替换时才加 `--replace`。

## 输出位置

安装完成后固定生成：

| 路径 | 用途 |
|------|------|
| `/usr/local/etc/xray/vless-reality.json` | AI 读取用 JSON 合约 |
| `/usr/local/etc/xray/vless-reality.yaml` | AI 读取用 YAML 合约 |
| `/usr/local/etc/xray/vless-link.txt` | `vless://` 分享链接 |
| `/usr/local/etc/xray/client-config.txt` | 人类可读完整配置 |

这些输出含有可连线凭证，脚本会设为 `chmod 600`。

## 字段约定

必须字段：

- `schemaVersion`: 固定为 `vrs.vless-reality.v1`。
- `protocol`: 固定为 `vless-reality`。
- `core`: 固定为 `xray-core`。
- `server`: 客户端连线使用的服务器地址。
- `port`: VLESS 监听端口。
- `uuid`: VLESS 客户端 UUID。
- `flow`: 固定为 `xtls-rprx-vision`。
- `transport`: 固定为 `tcp`。
- `security`: 固定为 `reality`。
- `sni`: Reality 客户端 SNI。
- `dest`: Reality server 端回落目标。
- `destPort`: Reality server 端回落目标端口。
- `publicKey`: Reality public key，供客户端使用。
- `shortId`: Reality short ID。
- `fingerprint`: uTLS 指纹，第一版固定为 `chrome`。
- `shareLink`: 可汇入客户端的 `vless://` 分享链接。
- `paths`: 远端配置与输出文件路径。
- `service`: Xray systemd 服务命令与状态。
- `healthCheck`: 健康检查命令与 cron 约定。

## 敏感资讯规则

对外日志、PR、issue、聊天回报中必须遮罩：

- `uuid`
- `publicKey`
- `shortId`
- `shareLink`
- `server`，若是真实服务器 IP 或域名

允许保留结构、字段名、路径、状态命令与示例保留地址，例如 `203.0.113.10`。
