// Сервис orders: задания заказчика — черновики визарда, публикация, лента,
// деталка (ТЗ §2.6–2.8).
//
// Хранилище выбирается по DATABASE_URL (пусто — в памяти, задано — Postgres с
// PostGIS и накатом миграций).
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"traktor/orders/internal/config"
	"traktor/orders/internal/httpapi"
	"traktor/orders/internal/service"
	"traktor/orders/internal/store"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	if err := run(log); err != nil {
		log.Error("orders остановлен с ошибкой", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg := config.Load()

	st, closeStore, err := openStore(ctx, cfg, log)
	if err != nil {
		return err
	}
	defer closeStore()

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           httpapi.New(service.New(st, time.Now)).Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("orders слушает", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		log.Info("получен сигнал остановки, завершаем текущие запросы")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		return srv.Shutdown(shutdownCtx)
	}
}

func openStore(ctx context.Context, cfg *config.Config, log *slog.Logger) (store.Store, func(), error) {
	if cfg.DatabaseURL == "" {
		log.Warn("DATABASE_URL не задан: задания хранятся в памяти и не переживут перезапуск")
		return store.NewMemory(), func() {}, nil
	}

	log.Info("накатываем миграции схемы orders")
	if err := store.Migrate(ctx, cfg.DatabaseURL); err != nil {
		return nil, nil, err
	}
	pool, err := store.OpenPool(ctx, cfg.DatabaseURL)
	if err != nil {
		return nil, nil, err
	}
	log.Info("хранилище: Postgres + PostGIS")
	return store.NewPostgres(pool), pool.Close, nil
}
