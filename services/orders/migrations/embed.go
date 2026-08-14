// Package migrations — SQL-схема orders, вшитая в бинарник (go:embed).
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
