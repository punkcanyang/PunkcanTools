# HTML Book PDF Desktop App Design

## Goal

在既有 `html-book-pdf` 工具上做一個可打包的桌面 app，讓使用者把單一 HTML 檔拖進視窗後即可輸出 PDF；輸出的每一頁都要在下方置中顯示頁碼，並支援 `macOS` 與 `Windows` 安裝包產出。

## Scope

這次只做：

- 單一 HTML 檔拖放匯入
- Electron 桌面 app 視窗
- 本機轉檔服務與桌面 UI 整合
- PDF 頁碼 footer，固定在下方中間
- `macOS + Windows` 打包設定

這次不做：

- 多檔批次處理
- 可視化版面編輯器
- 自訂複雜 header / footer 編輯器
- 自動更新
- 雲端同步或帳號系統

## Architecture

維持 `html-book-pdf` 的核心轉檔模組為單一真實來源，CLI 與桌面 app 都呼叫同一套 `convertHtmlToPdf()` 流程。為了可靠產生置中頁碼，PDF 輸出從目前的 Chromium `--print-to-pdf` 命令列模式，改為 Chrome DevTools Protocol 的 `Page.printToPDF` 呼叫，因為只有這條路徑能穩定注入 `displayHeaderFooter` 與自訂 `footerTemplate`。

桌面 app 採 `Electron + 本機 HTTP server + 靜態頁面`，沿用 repo 裡 `word2md` 已存在的打包模式：

- Electron main process 負責啟動 app 視窗與內建 server
- Node HTTP server 負責提供頁面、接收 HTML、觸發轉檔、回傳 PDF
- Renderer 前端是一頁式拖放介面，只保留拖放區、檔名顯示、輸出按鈕、狀態訊息
- 打包使用 `electron-builder`，目標與 `word2md` 對齊

## Components

### 1. Core PDF renderer

調整現有 `src/book-pdf.js`：

- 保留 HTML 注入、base href、列印 CSS 處理
- 新增 CDP 列印流程
- 新增頁碼 footer template，樣式固定為底部置中
- CLI 繼續可用，預設也會帶頁碼
- 輸出流程可同時被 server 與 CLI 呼叫

### 2. Desktop shell

新增 Electron shell：

- `main.js` 啟動 BrowserWindow
- app ready 時啟動內建 server
- 視窗關閉或 app 結束時回收 server
- 載入本機 UI 頁面

這一層只做桌面包裝，不重複實作轉檔邏輯。

### 3. Local web server

新增簡單 server 模組：

- `GET /` 回傳 GUI 頁面
- `POST /api/render` 接收 HTML 檔
- 轉檔完成後直接回傳 `application/pdf`

server 不做資料庫，不保留上傳紀錄；檔案只寫入暫存目錄。

### 4. GUI page

新增靜態頁面：

- 拖放區支援拖入 `.html`
- 可退回點擊選檔
- 顯示目前檔名與處理狀態
- 成功後觸發 PDF 下載

版面維持簡潔，不做多欄或多頁流程。視覺上以桌面工具為主，不追求行銷頁式設計。

### 5. Packaging

沿用 `electron-builder`：

- `macOS`: `dmg`、`zip`
- `Windows`: `nsis`、`portable`

第一版不處理簽章與 notarization，只先保證本機可打包出安裝產物。

## Data Flow

1. 使用者啟動桌面 app
2. Electron main process 啟動本機 server 並開啟單視窗 UI
3. 使用者拖入 HTML 檔
4. 前端以 `FormData` 上傳到 `/api/render`
5. server 將檔案寫入暫存位置
6. 核心轉檔模組產出 PDF
7. server 把 PDF 作為下載回應傳回
8. 前端以原檔名推導 PDF 檔名並下載

## Page Numbering

頁碼採 footer template 注入，內容只包含：

- `pageNumber`
- 必要的容器樣式

需求明確固定為：

- 位置在頁面底部
- 水平置中
- 所有頁面都顯示
- 不顯示文件標題、網址、日期

若原始 HTML 已自行用 CSS 做頁腳，這次實作不嘗試合併，只以瀏覽器列印 footer 為準。footer 內容預設只顯示數字頁碼，不顯示總頁數。

## Error Handling

- 沒有檔案：前端提示請拖入 HTML
- 非 HTML 檔：前端與後端都拒收
- 找不到瀏覽器：API 回傳明確錯誤訊息
- 轉檔失敗：API 回傳 500 與簡短錯誤
- 暫存清理失敗：記錄到 console，但不影響主要回應
- 內建 server 啟動失敗：桌面 app 啟動時直接報錯，不進入空白視窗
- 打包設定錯誤：以 build script 失敗明確暴露，不吞錯

## Testing

測試分三層：

- 單元測試：CLI / option parsing / footer template / HTML 注入
- server 測試：`POST /api/render` 的輸入驗證與 response headers
- app 結構驗證：Electron 入口與打包設定存在且可啟動
- 實際驗證：用現成測試 HTML 產出 PDF，確認檔案存在且 `file` 能辨識頁數
- 打包驗證：至少在目前機器上完成一次 `macOS` build；`Windows` 設定完成，若當前環境無法交叉產物驗證，需明確記錄

## Constraints

- 依賴本機已安裝 Chrome / Brave / Edge
- GUI 只服務本機使用，不處理權限與帳號
- 維持 ASCII 為主，不引入前端框架
- 優先沿用 repo 既有 Electron 打包模式，不引入 Tauri
