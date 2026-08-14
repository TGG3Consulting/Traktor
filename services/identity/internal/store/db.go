package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/golang-migrate/migrate/v4"
	migratepgx "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib" // database/sql-драйвер "pgx/v5" для миграций

	"traktor/identity/migrations"
)

// OpenPool открывает пул соединений и проверяет доступность базы.
func OpenPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("store: разбор DATABASE_URL: %w", err)
	}
	cfg.MaxConns = 10
	cfg.MaxConnLifetime = time.Hour
	cfg.HealthCheckPeriod = time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("store: подключение к базе: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("store: база недоступна: %w", err)
	}
	return pool, nil
}

// Migrate накатывает схему через golang-migrate (правило 23 — не самопис).
// Идемпотентно: на актуальной базе повторный запуск ничего не меняет.
func Migrate(ctx context.Context, dsn string) error {
	src, err := iofs.New(migrations.FS, ".")
	if err != nil {
		return fmt.Errorf("store: чтение миграций: %w", err)
	}

	db, err := sql.Open("pgx/v5", dsn)
	if err != nil {
		return fmt.Errorf("store: открытие соединения для миграций: %w", err)
	}
	defer db.Close()

	pingCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		return fmt.Errorf("store: база недоступна для миграций: %w", err)
	}

	// Своя таблица версий на сервис: иначе при общей базе (локальный dev,
	// staging) второй сервис увидит чужую версию схемы и решит, что накатывать
	// нечего — его таблицы просто не появятся.
	driver, err := migratepgx.WithInstance(db, &migratepgx.Config{
		MigrationsTable: "schema_migrations_identity",
	})
	if err != nil {
		return fmt.Errorf("store: драйвер миграций: %w", err)
	}
	m, err := migrate.NewWithInstance("iofs", src, "pgx5", driver)
	if err != nil {
		return fmt.Errorf("store: инициализация миграций: %w", err)
	}
	if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
		return fmt.Errorf("store: применение миграций: %w", err)
	}
	return nil
}
