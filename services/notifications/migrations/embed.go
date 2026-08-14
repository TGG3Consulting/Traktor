// Package migrations — SQL-схема notifications, вшитая в бинарник (go:embed).
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
