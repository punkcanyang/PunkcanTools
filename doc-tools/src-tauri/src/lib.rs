use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use headless_chrome::types::PrintToPdfOptions;
use headless_chrome::{Browser, LaunchOptionsBuilder};
use quick_xml::events::{BytesStart, Event};
use quick_xml::Reader;
use std::borrow::Cow;
use std::io::{Cursor, Read};
use std::path::PathBuf;
use std::thread;
use std::time::Duration;
use tempfile::tempdir;
use url::Url;
use zip::ZipArchive;

#[tauri::command]
async fn convert_html_to_pdf(
    html_content: String,
    include_page_numbers: Option<bool>,
) -> Result<String, String> {
    let include_page_numbers = include_page_numbers.unwrap_or(true);
    tauri::async_runtime::spawn_blocking(move || {
        convert_html_to_pdf_blocking(&html_content, include_page_numbers)
    })
        .await
        .map_err(|error| format!("HTML 轉 PDF 任務失敗: {error}"))?
}

#[tauri::command]
async fn convert_docx_to_markdown(docx_base64: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || convert_docx_to_markdown_blocking(&docx_base64))
        .await
        .map_err(|error| format!("DOCX 轉 Markdown 任務失敗: {error}"))?
}

fn convert_html_to_pdf_blocking(html_content: &str, include_page_numbers: bool) -> Result<String, String> {
    let browser_path = detect_browser_path().ok_or_else(|| {
        "找不到可用的 Chromium 瀏覽器，請安裝 Chrome / Edge / Brave。".to_string()
    })?;

    let temp = tempdir().map_err(|error| error.to_string())?;
    let html_path = temp.path().join("input.html");
    std::fs::write(&html_path, html_content).map_err(|error| error.to_string())?;

    let html_url = Url::from_file_path(&html_path)
        .map_err(|_| "無法建立 HTML 檔案 URL".to_string())?
        .to_string();

    let launch_options = LaunchOptionsBuilder::default()
        .path(Some(browser_path))
        .headless(true)
        .sandbox(false)
        .build()
        .map_err(|error| error.to_string())?;

    let browser = Browser::new(launch_options).map_err(|error| error.to_string())?;
    let tab = browser.new_tab().map_err(|error| error.to_string())?;

    tab.navigate_to(&html_url)
        .map_err(|error| error.to_string())?;
    tab.wait_until_navigated()
        .map_err(|error| error.to_string())?;
    thread::sleep(Duration::from_millis(1200));

    let footer_template = r#"
<div style="width:100%;padding:0 0 6px;text-align:center;font-size:9px;color:#666;">
  <span class="pageNumber"></span>
</div>
"#;

    let pdf_options = if include_page_numbers {
        PrintToPdfOptions {
            display_header_footer: Some(true),
            print_background: Some(true),
            prefer_css_page_size: Some(true),
            header_template: Some("<div></div>".to_string()),
            footer_template: Some(footer_template.to_string()),
            ..Default::default()
        }
    } else {
        PrintToPdfOptions {
            display_header_footer: Some(false),
            print_background: Some(true),
            prefer_css_page_size: Some(true),
            ..Default::default()
        }
    };

    let pdf_bytes = tab
        .print_to_pdf(Some(pdf_options))
        .map_err(|error| error.to_string())?;

    Ok(BASE64.encode(pdf_bytes))
}

fn convert_docx_to_markdown_blocking(docx_base64: &str) -> Result<String, String> {
    let bytes = BASE64
        .decode(docx_base64.as_bytes())
        .map_err(|error| format!("DOCX base64 解碼失敗: {error}"))?;
    parse_docx_to_markdown(&bytes)
}

fn parse_docx_to_markdown(bytes: &[u8]) -> Result<String, String> {
    let cursor = Cursor::new(bytes);
    let mut archive = ZipArchive::new(cursor).map_err(|error| error.to_string())?;
    let mut document = archive
        .by_name("word/document.xml")
        .map_err(|error| format!("DOCX 缺少 document.xml: {error}"))?;

    let mut xml = String::new();
    document
        .read_to_string(&mut xml)
        .map_err(|error| error.to_string())?;

    let mut reader = Reader::from_str(&xml);
    reader.config_mut().trim_text(true);

    let mut output = String::new();
    let mut buffer = Vec::new();

    let mut paragraph_text = String::new();
    let mut paragraph_style: Option<String> = None;
    let mut in_text = false;

    let mut in_table = false;
    let mut in_cell = false;
    let mut current_row: Vec<String> = Vec::new();
    let mut table_rows: Vec<Vec<String>> = Vec::new();
    let mut cell_parts: Vec<String> = Vec::new();

    loop {
        match reader.read_event_into(&mut buffer) {
            Ok(Event::Start(element)) => {
                let name = local_name(element.name().as_ref());
                match name.as_str() {
                    "p" => {
                        paragraph_text.clear();
                        paragraph_style = None;
                    }
                    "pStyle" => {
                        paragraph_style = attribute_value(&element, b"val");
                    }
                    "t" => in_text = true,
                    "tab" => paragraph_text.push('\t'),
                    "br" => paragraph_text.push(' '),
                    "tbl" => {
                        in_table = true;
                        table_rows.clear();
                    }
                    "tr" => current_row.clear(),
                    "tc" => {
                        in_cell = true;
                        cell_parts.clear();
                    }
                    _ => {}
                }
            }
            Ok(Event::Empty(element)) => {
                let name = local_name(element.name().as_ref());
                match name.as_str() {
                    "pStyle" => {
                        paragraph_style = attribute_value(&element, b"val");
                    }
                    "tab" => paragraph_text.push('\t'),
                    "br" => paragraph_text.push(' '),
                    _ => {}
                }
            }
            Ok(Event::Text(text)) => {
                if in_text {
                    let decoded = text.decode().map_err(|error| error.to_string())?;
                    paragraph_text.push_str(&decoded);
                }
            }
            Ok(Event::End(element)) => {
                let name = local_name(element.name().as_ref());
                match name.as_str() {
                    "t" => in_text = false,
                    "p" => {
                        let trimmed = paragraph_text.trim();
                        if !trimmed.is_empty() {
                            let line = format_paragraph(trimmed, paragraph_style.as_deref());
                            if in_cell {
                                cell_parts.push(line);
                            } else if !in_table {
                                output.push_str(&line);
                                output.push_str("\n\n");
                            }
                        }
                    }
                    "tc" => {
                        in_cell = false;
                        let content = cell_parts.join(" ").trim().to_string();
                        current_row.push(content);
                    }
                    "tr" => {
                        if !current_row.is_empty() {
                            table_rows.push(current_row.clone());
                        }
                    }
                    "tbl" => {
                        in_table = false;
                        if !table_rows.is_empty() {
                            output.push_str(&table_to_markdown(&table_rows));
                            output.push('\n');
                        }
                    }
                    _ => {}
                }
            }
            Ok(Event::Eof) => break,
            Err(error) => return Err(format!("解析 DOCX XML 失敗: {error}")),
            _ => {}
        }

        buffer.clear();
    }

    Ok(output.trim().to_string())
}

fn format_paragraph(text: &str, style: Option<&str>) -> String {
    if let Some(style_value) = style {
        if let Some(level) = parse_heading_level(style_value) {
            let level = level.clamp(1, 6);
            return format!("{} {}", "#".repeat(level), text);
        }
    }

    text.to_string()
}

fn parse_heading_level(style: &str) -> Option<usize> {
    let normalized = style.to_lowercase();
    if !normalized.starts_with("heading") {
        return None;
    }

    normalized
        .chars()
        .filter(char::is_ascii_digit)
        .collect::<String>()
        .parse::<usize>()
        .ok()
}

fn table_to_markdown(rows: &[Vec<String>]) -> String {
    let mut normalized = rows.to_vec();
    let max_columns = normalized.iter().map(|row| row.len()).max().unwrap_or(0);
    if max_columns == 0 {
        return String::new();
    }

    for row in &mut normalized {
        while row.len() < max_columns {
            row.push(String::new());
        }
    }

    let mut result = String::new();

    let header = &normalized[0];
    result.push('|');
    result.push_str(
        &header
            .iter()
            .map(|cell| format!(" {} ", escape_table_cell(cell)))
            .collect::<Vec<_>>()
            .join("|"),
    );
    result.push_str("|\n|");
    result.push_str(&vec![" --- ".to_string(); max_columns].join("|"));
    result.push_str("|\n");

    for row in normalized.iter().skip(1) {
        result.push('|');
        result.push_str(
            &row.iter()
                .map(|cell| format!(" {} ", escape_table_cell(cell)))
                .collect::<Vec<_>>()
                .join("|"),
        );
        result.push_str("|\n");
    }

    result
}

fn escape_table_cell(cell: &str) -> String {
    cell.replace('|', "\\|")
}

fn attribute_value(element: &BytesStart, wanted: &[u8]) -> Option<String> {
    let expected = local_name(wanted);
    for attr in element.attributes().flatten() {
        if local_name(attr.key.as_ref()) == expected {
            match attr.value {
                Cow::Borrowed(value) => return String::from_utf8(value.to_vec()).ok(),
                Cow::Owned(value) => return String::from_utf8(value).ok(),
            }
        }
    }
    None
}

fn local_name(name: &[u8]) -> String {
    let raw = std::str::from_utf8(name).unwrap_or_default();
    raw.rsplit(':').next().unwrap_or(raw).to_string()
}

fn detect_browser_path() -> Option<PathBuf> {
    let candidates = [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
        "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
        "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
        "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
        "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
        "/usr/bin/microsoft-edge",
        "/usr/bin/brave-browser",
    ];

    candidates
        .iter()
        .map(PathBuf::from)
        .find(|path| path.exists())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            convert_html_to_pdf,
            convert_docx_to_markdown
        ])
        .run(tauri::generate_context!())
        .expect("error while running doc tools");
}

#[cfg(test)]
mod tests {
    use super::parse_docx_to_markdown;
    use std::io::{Cursor, Write};
    use zip::write::{FileOptions, ZipWriter};

    fn build_docx_bytes(document_xml: &str) -> Vec<u8> {
        let cursor = Cursor::new(Vec::new());
        let mut zip = ZipWriter::new(cursor);
        let options: FileOptions<'_, ()> = FileOptions::default();
        zip.start_file("word/document.xml", options).unwrap();
        zip.write_all(document_xml.as_bytes()).unwrap();
        zip.finish().unwrap().into_inner()
    }

    #[test]
    fn parses_heading_and_paragraph() {
        let document_xml = r#"
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      <w:r><w:t>Title</w:t></w:r>
    </w:p>
    <w:p><w:r><w:t>Body text</w:t></w:r></w:p>
  </w:body>
</w:document>
"#;
        let bytes = build_docx_bytes(document_xml);
        let markdown = parse_docx_to_markdown(&bytes).unwrap();
        assert!(markdown.contains("# Title"));
        assert!(markdown.contains("Body text"));
    }

    #[test]
    fn parses_simple_table() {
        let document_xml = r#"
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:tbl>
      <w:tr>
        <w:tc><w:p><w:r><w:t>H1</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>H2</w:t></w:r></w:p></w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
  </w:body>
</w:document>
"#;
        let bytes = build_docx_bytes(document_xml);
        let markdown = parse_docx_to_markdown(&bytes).unwrap();
        assert!(markdown.contains("| H1 | H2 |"));
        assert!(markdown.contains("| A | B |"));
    }
}
