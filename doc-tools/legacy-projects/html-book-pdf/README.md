# html-book-pdf

把已經排版好的 HTML 轉成可列印、可出版的分頁 PDF，並提供可打包的桌面 app（macOS + Windows）。

這個工具適合以下情境：

- HTML 已經有完整排版與 print CSS
- 需要保留 `@page`、`page-break-*`、`break-*` 等分頁規則
- 想把本機 HTML 直接輸出成一頁一頁的 PDF 出版物

它的做法是：

1. 讀取原始 HTML
2. 注入 `<base>`，確保相對路徑資源可正常載入
3. 視需要補上列印 CSS 覆寫
4. 透過 Chromium DevTools Protocol 輸出 PDF
5. 在每頁底部置中加入頁碼

## 需求

請先確認電腦上至少有一套以下瀏覽器：

- Google Chrome
- Brave
- Microsoft Edge

如果瀏覽器不在預設位置，可用 `--browser-path` 指定執行檔。

## 用法

```bash
cd /Users/punkcan/SourceCode/PunkcanTools/html-book-pdf
node src/cli.js ./book.html -o ./book.pdf
```

如果 HTML 裡本來就有 `@page` 與分頁規則，通常這樣就夠了。

## 常用範例

直接把使用者提供的測試 HTML 轉成 PDF：

```bash
cd /Users/punkcan/SourceCode/PunkcanTools/html-book-pdf
node src/cli.js \
  /Users/punkcan/OrbStack/kaliHermes/home/punkcan/output/ai-first-publication.html \
  -o /Users/punkcan/OrbStack/kaliHermes/home/punkcan/output/ai-first-publication.pdf
```

若 HTML 沒有自行定義紙張與邊界，可強制補上：

```bash
node src/cli.js ./book.html -o ./book.pdf --format A4 --margin 20mm
```

若每個頁面區塊都有共用 class，可讓工具幫你補斷頁：

```bash
node src/cli.js ./book.html -o ./book.pdf --page-selector .page
```

若要額外覆寫列印樣式：

```bash
node src/cli.js ./book.html -o ./book.pdf --css ./print-overrides.css
```

## 桌面 App

```bash
cd /Users/punkcan/SourceCode/PunkcanTools/html-book-pdf
npm install
npm run electron
```

啟動後直接把 HTML 拖進視窗，按「匯出 PDF」就會下載結果。

## 打包

```bash
cd /Users/punkcan/SourceCode/PunkcanTools/html-book-pdf
npm run build:mac
npm run build:win
```

輸出檔案會放在 `dist/`。

## 參數

- `-o, --output <file>`: 輸出 PDF 路徑
- `--browser <name>`: `chrome`、`brave`、`edge` 或 `auto`
- `--browser-path <path>`: 直接指定瀏覽器執行檔
- `--wait <ms>`: 載入後再等待幾毫秒再列印，預設 `1200`
- `--page-selector <css>`: 對符合 selector 的區塊補上每頁斷頁
- `--format <size>`: 強制指定紙張大小，例如 `A4`
- `--margin <value>`: 強制指定 `@page` 邊界，例如 `20mm`
- `--css <file>`: 額外注入的列印 CSS 檔
- `--keep-temp`: 保留暫存 HTML，方便除錯
- `--verbose`: 顯示實際使用的瀏覽器與暫存資訊

## 注意事項

- 這個工具預設尊重原始 HTML 的 print CSS，不會主動重排內容。
- 頁碼固定在每頁底部置中，內容為當前頁碼（不顯示總頁數）。
- 若你的 HTML 依賴遠端字型、圖片或外部資源，輸出品質取決於列印時那些資源能否正常載入。
- 如果版面有動態生成內容，請用 `--wait` 拉長等待時間。
