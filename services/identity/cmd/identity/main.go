// Сервис identity: OTP-вход (Dexatel), JWT ES256, /me, JWKS.
//
// Хранилище выбирается по DATABASE_URL: пусто — in-memory (dev и тесты),
// задано — Postgres через pgx с автоматическим накатом миграций.
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

	"traktor/identity/internal/config"
	"traktor/identity/internal/httpapi"
	"traktor/identity/internal/service"
	"traktor/identity/internal/sms"
	"traktor/identity/internal/store"
	"traktor/identity/internal/token"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)

	if err := run(log); err != nil {
		log.Error("identity остановлен с ошибкой", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if cfg.EphemeralKey {
		log.Warn("ключ подписи сгенерирован при старте: после перезапуска все токены станут недействительными (задайте JWT_EC_PRIVATE_KEY_PEM)")
	}

	var provider sms.Provider
	if cfg.TestMode || cfg.DexatelKey == "" {
		log.Info("SMS в тест-режиме (fake provider)")
		provider = sms.NewFake()
	} else {
		provider = sms.NewDexatel(cfg.DexatelKey, cfg.DexatelSender)
	}

	st, closeStore, err := openStore(ctx, cfg, log)
	if err != nil {
		return err
	}
	defer closeStore()

	signer := token.NewSigner(cfg.PrivKey, cfg.Kid)
	auth := service.NewAuth(st, provider, signer, time.Now).WithModerators(cfg.ModeratorPhones)
	if cfg.OTPStaticCode != "" {
		log.Warn("вход по фиксированному коду — только для разработки",
			"code", cfg.OTPStaticCode)
		auth = auth.WithStaticCode(cfg.OTPStaticCode)
	}
	api := httpapi.New(auth, &cfg.PrivKey.PublicKey, cfg.Kid)

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           api.Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("identity слушает", "addr", srv.Addr)
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

// openStore возвращает хранилище и функцию его закрытия.
func openStore(ctx context.Context, cfg *config.Config, log *slog.Logger) (store.Store, func(), error) {
	if cfg.DatabaseURL == "" {
		log.Warn("DATABASE_URL не задан: работаем на in-memory хранилище, данные не переживут перезапуск")
		return store.NewMemory(), func() {}, nil
	}

	log.Info("накатываем миграции схемы identity")
	if err := store.Migrate(ctx, cfg.DatabaseURL); err != nil {
		return nil, nil, err
	}
	pool, err := store.OpenPool(ctx, cfg.DatabaseURL)
	if err != nil {
		return nil, nil, err
	}
	pg, err := store.NewPostgres(pool, cfg.PhoneEncKey)
	if err != nil {
		pool.Close()
		return nil, nil, err
	}
	log.Info("хранилище: Postgres")
	return pg, pool.Close, nil
}
