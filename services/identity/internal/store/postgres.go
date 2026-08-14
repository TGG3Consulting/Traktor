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

// Реализация методов Store поверх pgx добавляется на шаге поднятия БД.
// (Заготовки методов опущены намеренно, чтобы файл не расходился со схемой
//
//	до подключения реального Cloud SQL — заполняется вместе с миграциями.)
var _ = context.Background
