# Word2MD

A command-line tool that converts Word documents (.docx) to Markdown format.

## Installation

```bash
npm install
```

## Usage

### Single File Conversion

```bash
# Basic usage (output to same directory)
node src/cli.js document.docx

# Specify output path
node src/cli.js document.docx -o output.md
```

### Batch Conversion

```bash
# Convert all docx files in a directory
node src/cli.js ./documents/

# Specify output directory
node src/cli.js ./documents/ -o ./markdown/
```

### Options

| Option | Description |
|--------|-------------|
| `-o, --output <path>` | Specify output path (file or directory) |
| `-i, --no-images` | Don't extract images |
| `-r, --recursive` | Process subdirectories recursively |
| `-V, --version` | Show version number |
| `-h, --help` | Show help information |

## Supported Formats

- ✅ Headings (h1-h6)
- ✅ Bold, Italic
- ✅ Links
- ✅ Images (automatically extracted to images folder)
- ✅ Unordered/Ordered lists
- ✅ Tables
- ✅ Code blocks

## Global Installation (Optional)

```bash
npm link
# Then you can use directly
word2md document.docx
```

## Web UI

Start the visual interface:

```bash
npm run ui
# Visit http://localhost:3456
```

Supports drag-and-drop upload of Word documents, real-time preview and Markdown download.
