// Package migrations — SQL-схема identity, вшитая в бинарник (go:embed).
// Прод-под ничего не докачивает: версия схемы всегда равна версии кода.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
