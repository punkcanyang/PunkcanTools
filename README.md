# PunkcanTools

個人實用工具集。這個倉庫是多個小工具與實驗專案的集合，根目錄 README 只做總覽；實際安裝、開發與使用方式請進各子專案閱讀自己的 README。

## 子專案

| 子專案 | 類型 | 說明 |
| --- | --- | --- |
| [astro-chart](./astro-chart/) | Node.js / Web / CLI | 星盤計算工具，輸入時間與地點後產生行星位置、宮位、相位與逆行資訊。 |
| [doc-tools](./doc-tools/) | Tauri 桌面工具 | 文件轉換整合版，提供 HTML 轉 PDF、Word `.docx` 轉 Markdown，並收納合併前的歷史模組。 |
| [VRS](./VRS/) | Bash 腳本集 | 多協定 VPN / proxy 一鍵安裝腳本，支援 Debian、Ubuntu、CentOS、RHEL、Rocky、Alma。 |
| [LCLLink](./LCLLink/) | Chrome Extension | 多協定代理客戶端 Chrome 擴充功能，Phase 1 以 WebSocket 支援 VLESS、Trojan、Shadowsocks、SS-2022。 |
| [IP-Scan](./IP-Scan/) | Tauri 桌面工具 | 跨平台網路 IP 掃描工具，支援 CIDR 掃描、ICMP ping、常用連接埠掃描與基礎裝置判斷。 |
| [pr-radar](./pr-radar/) | React / Node.js / PostgreSQL | AI 驅動的 GitHub PR / Issue 分析工具，用於同步資料、去重、依賴檢測與 Vision 偏離評估。 |

## Doc Tools 歷史模組

| 模組 | 說明 |
| --- | --- |
| [html-book-pdf](./doc-tools/legacy-projects/html-book-pdf/) | 將已排版的 HTML 轉成分頁 PDF，保留 print CSS 與分頁規則，也保留舊版桌面 App 打包流程。 |
| [word2md](./doc-tools/legacy-projects/word2md/) | 舊版 Word `.docx` 轉 Markdown 工具，支援 CLI、批次轉換與 Web UI。 |

## 使用方式

每個子專案的依賴、環境變數、啟動方式與打包方式都不同。請先進入對應目錄，再依該目錄的 README 操作：

```bash
cd astro-chart
cd doc-tools
cd VRS
cd LCLLink
cd IP-Scan
cd pr-radar
```

## 授權

MIT License

## 作者

[@punkcanyang](https://github.com/punkcanyang)
