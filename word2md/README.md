# Word2MD

将 Word 文档 (.docx) 转换为 Markdown 格式的命令行工具。

## 安装

```bash
npm install
```

## 使用方法

### 单文件转换

```bash
# 基本用法（输出到同目录）
node src/cli.js document.docx

# 指定输出路径
node src/cli.js document.docx -o output.md
```

### 批量转换

```bash
# 转换目录中所有 docx 文件
node src/cli.js ./documents/

# 指定输出目录
node src/cli.js ./documents/ -o ./markdown/
```

### 选项

| 选项 | 说明 |
|------|------|
| `-o, --output <path>` | 指定输出路径（文件或目录） |
| `-i, --no-images` | 不提取图片 |
| `-r, --recursive` | 递归处理子目录 |
| `-V, --version` | 显示版本号 |
| `-h, --help` | 显示帮助信息 |

## 支持的格式

- ✅ 标题 (h1-h6)
- ✅ 粗体、斜体
- ✅ 链接
- ✅ 图片（自动提取到 images 目录）
- ✅ 无序/有序列表
- ✅ 表格
- ✅ 代码块

## 全局安装（可选）

```bash
npm link
# 然后可以直接使用
word2md document.docx
```

## Web UI

启动可视化界面：

```bash
npm run ui
# 访问 http://localhost:3456
```

支持拖拽上传 Word 文档，实时预览并下载 Markdown。

