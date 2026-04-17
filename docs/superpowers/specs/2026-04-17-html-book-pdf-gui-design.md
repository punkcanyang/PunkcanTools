# HTML Book PDF GUI Design

## Goal

在既有 `html-book-pdf` 工具上補一個最小可用的本機 Web GUI，讓使用者把單一 HTML 檔拖進頁面後即可輸出 PDF；輸出的每一頁都要在下方置中顯示頁碼。

## Scope

這次只做：

- 單一 HTML 檔拖放上傳
- 本機 Web GUI
- 後端轉檔 API
- PDF 頁碼 footer，固定在下方中間

這次不做：

- 多檔批次處理
- 完整桌面 app 打包
- 可視化版面編輯器
- 自訂複雜 header / footer 編輯器

## Architecture

維持 `html-book-pdf` 的核心轉檔模組為單一真實來源，CLI 與 GUI 都呼叫同一套 `convertHtmlToPdf()` 流程。為了可靠產生置中頁碼，PDF 輸出從目前的 Chromium `--print-to-pdf` 命令列模式，改為 Chrome DevTools Protocol 的 `Page.printToPDF` 呼叫，因為只有這條路徑能穩定注入 `displayHeaderFooter` 與自訂 `footerTemplate`。

GUI 採最小 server + 靜態頁面：

- Node HTTP server 負責提供頁面、接收 HTML、觸發轉檔、回傳 PDF
- 前端是一頁式拖放介面，只保留檔案拖放區、檔名顯示、輸出按鈕、狀態訊息

## Components

### 1. Core PDF renderer

調整現有 `src/book-pdf.js`：

- 保留 HTML 注入、base href、列印 CSS 處理
- 新增 CDP 列印流程
- 新增頁碼 footer template，樣式固定為底部置中
- CLI 繼續可用，預設也會帶頁碼

### 2. Local web server

新增簡單 server 模組：

- `GET /` 回傳 GUI 頁面
- `POST /api/render` 接收 HTML 檔
- 轉檔完成後直接回傳 `application/pdf`

server 不做資料庫，不保留上傳紀錄；檔案只寫入暫存目錄。

### 3. GUI page

新增靜態頁面：

- 拖放區支援拖入 `.html`
- 可退回點擊選檔
- 顯示目前檔名與處理狀態
- 成功後觸發 PDF 下載

版面維持簡潔，不做多欄或多頁流程。

## Data Flow

1. 使用者開啟本機 GUI 頁面
2. 拖入 HTML 檔
3. 前端以 `FormData` 上傳到 `/api/render`
4. server 將檔案寫入暫存位置
5. 核心轉檔模組產出 PDF
6. server 把 PDF 作為下載回應傳回
7. 前端以原檔名推導 PDF 檔名並下載

## Page Numbering

頁碼採 footer template 注入，內容只包含：

- `pageNumber`
- 必要的容器樣式

需求明確固定為：

- 位置在頁面底部
- 水平置中
- 所有頁面都顯示
- 不顯示文件標題、網址、日期

若原始 HTML 已自行用 CSS 做頁腳，這次實作不嘗試合併，只以瀏覽器列印 footer 為準。

## Error Handling

- 沒有檔案：前端提示請拖入 HTML
- 非 HTML 檔：前端與後端都拒收
- 找不到瀏覽器：API 回傳明確錯誤訊息
- 轉檔失敗：API 回傳 500 與簡短錯誤
- 暫存清理失敗：記錄到 console，但不影響主要回應

## Testing

測試分三層：

- 單元測試：CLI / option parsing / footer template / HTML 注入
- server 測試：`POST /api/render` 的輸入驗證與 response headers
- 實際驗證：用現成測試 HTML 產出 PDF，確認檔案存在且 `file` 能辨識頁數

## Constraints

- 依賴本機已安裝 Chrome / Brave / Edge
- GUI 只服務本機使用，不處理權限與帳號
- 維持 ASCII 為主，不引入前端框架
