/*
__ai_context__: 嵌入 Web UI 静态资源。
使用 Go 1.16+ 的 embed 功能将 web/ 目录下的文件编译进二进制。
WHY: 避免分发时需要额外携带静态文件，单个二进制即可运行。
*/
package web

import "embed"

// Content 嵌入的 Web UI 静态文件
// WHY: 使用 //go:embed 指令在编译时将整个 web 目录打包进二进制
//
//go:embed index.html
var Content embed.FS
