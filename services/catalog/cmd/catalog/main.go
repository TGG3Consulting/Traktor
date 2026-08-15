// Сервис catalog: дерево категорий работ и техники с шаблонами характеристик.
//
// Хранилище выбирается по DATABASE_URL (пусто — сокращённый справочник в
// памяти, задано — Postgres с накатом миграций и полным сидом).
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

	"traktor/catalog/internal/config"
	"traktor/catalog/internal/httpapi"
	"traktor/catalog/internal/notify"
	"traktor/catalog/internal/store"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	if err := run(log); err != nil {
		log.Error("catalog остановлен с ошибкой", "err", err)
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

	var notifier notify.Notifier = notify.Noop{}
	if cfg.NotificationsURL != "" {
		notifier = notify.NewHTTP(cfg.NotificationsURL, log)
		log.Info("уведомления о модерации включены", "notifications", cfg.NotificationsURL)
	} else {
		log.Warn("NOTIFICATIONS_URL не задан: решения модерации не уйдут владельцу")
	}

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           httpapi.NewWithNotifier(st, notifier).Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("catalog слушает", "addr", srv.Addr)
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
		log.Warn("DATABASE_URL не задан: справочник в памяти, только основные виды работ")
		return store.NewMemory(), func() {}, nil
	}

	log.Info("накатываем миграции схемы catalog")
	if err := store.Migrate(ctx, cfg.DatabaseURL); err != nil {
		return nil, nil, err
	}
	pool, err := store.OpenPool(ctx, cfg.DatabaseURL)
	if err != nil {
		return nil, nil, err
	}
	log.Info("хранилище: Postgres")
	return store.NewPostgres(pool), pool.Close, nil
}
