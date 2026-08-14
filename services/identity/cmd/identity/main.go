// Сервис identity: OTP-вход (Dexatel), JWT ES256, /me, JWKS.
// Дефолтная сборка использует in-memory store (dev/тесты); прод — с тегом
// `postgres` и реальным Cloud SQL.
package main

import (
	"log"
	"net/http"
	"time"

	"traktor/identity/internal/config"
	"traktor/identity/internal/httpapi"
	"traktor/identity/internal/service"
	"traktor/identity/internal/sms"
	"traktor/identity/internal/store"
	"traktor/identity/internal/token"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	var provider sms.Provider
	if cfg.TestMode || cfg.DexatelKey == "" {
		log.Println("identity: SMS в тест-режиме (fake provider)")
		provider = sms.NewFake()
	} else {
		provider = sms.NewDexatel(cfg.DexatelKey, cfg.DexatelSender)
	}

	st := store.NewMemory() // прод: store.NewPostgres(pool) с тегом postgres
	signer := token.NewSigner(cfg.PrivKey, cfg.Kid)
	auth := service.NewAuth(st, provider, signer, time.Now)
	srv := httpapi.New(auth, &cfg.PrivKey.PublicKey, cfg.Kid)

	addr := ":" + cfg.Port
	log.Printf("identity: слушаю %s", addr)
	if err := http.ListenAndServe(addr, srv.Routes()); err != nil {
		log.Fatal(err)
	}
}
