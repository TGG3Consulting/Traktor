//go:build postgres

// Postgres-реализация Store. Компилируется только с тегом `postgres` в CI
// (там доступен pgx). В дефолтной офлайн-сборке исключена, поэтому не ломает
// `go build ./...`. Схема — migrations/0001_init.sql.
package store

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Postgres struct{ pool *pgxpool.Pool }

func NewPostgres(pool *pgxpool.Pool) *Postgres { return &Postgres{pool: pool} }

// Реализация методов Store поверх pgx добавляется на шаге поднятия БД вместе с
// миграциями (expand→migrate→contract). Пока каркас не расходится со схемой.
var _ = context.Background
