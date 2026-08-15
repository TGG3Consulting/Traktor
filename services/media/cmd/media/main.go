// Сервис media: временные ссылки на загрузку фотографий и документов.
//
// Файлы идут от клиента прямо в хранилище (MinIO локально, Cloudflare R2 в
// бою), сервис только подписывает ссылки и решает, что можно грузить.
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

	"traktor/media/internal/config"
	"traktor/media/internal/httpapi"
	"traktor/media/internal/storage"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(log)

	cfg := config.Load()
	store, err := storage.New(cfg.Endpoint, cfg.AccessKey, cfg.SecretKey,
		cfg.Bucket, cfg.PublicBaseURL, cfg.UseSSL)
	if err != nil {
		log.Error("хранилище не настроено", "err", err)
		os.Exit(1)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	if err := store.Ready(ctx); err != nil {
		// Не падаем: хранилище может подняться позже, а сервис нужен для
		// healthz и не мешает остальным.
		log.Warn("хранилище пока недоступно", "err", err)
	}
	cancel()

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           httpapi.New(store).Routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Info("media слушает", "addr", srv.Addr, "bucket", cfg.Bucket)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("сервер остановился", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	shutdownCtx, done := context.WithTimeout(context.Background(), 10*time.Second)
	defer done()
	_ = srv.Shutdown(shutdownCtx)
	log.Info("media остановлен")
}
