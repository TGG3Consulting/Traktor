// Сервис notifications: реестр push-токенов устройств и рассылка уведомлений.
//
// Хранилище выбирается по DATABASE_URL (пусто — in-memory, задано — Postgres
// с автоматическим накатом миграций). Провайдер пушей — по FCM_PROJECT_ID
// (пусто — fake, задан — Firebase Admin SDK).
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

	"traktor/notifications/internal/config"
	"traktor/notifications/internal/httpapi"
	"traktor/notifications/internal/push"
	"traktor/notifications/internal/service"
	"traktor/notifications/internal/store"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	if err := run(log); err != nil {
		log.Error("notifications остановлен с ошибкой", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg := config.Load()

	var provider push.Provider
	if cfg.FCMProjectID == "" {
		log.Warn("FCM_PROJECT_ID не задан: push в тест-режиме (fake provider)")
		provider = push.NewFake()
	} else {
		fcm, err := push.NewFCM(ctx, cfg.FCMProjectID)
		if err != nil {
			return err
		}
		provider = fcm
		log.Info("FCM включён", "project", cfg.FCMProjectID)
	}

	st, closeStore, err := openStore(ctx, cfg, log)
	if err != nil {
		return err
	}
	defer closeStore()

	svc := service.New(st, provider, time.Now)
	api := httpapi.New(svc)

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           api.Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("notifications слушает", "addr", srv.Addr, "push", provider.Name())
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
		log.Warn("DATABASE_URL не задан: работаем на in-memory хранилище, регистрации устройств не переживут перезапуск")
		return store.NewMemory(), func() {}, nil
	}

	log.Info("накатываем миграции схемы notifications")
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
