// Сервис notifications: реестр push-токенов устройств и рассылка уведомлений.
// Дефолтная сборка — in-memory store + fake push (компилируется офлайн, dev/тест).
// Прод — с тегом `postgres` (Cloud SQL) и FCM (FCM_PROJECT_ID задан).
package main

import (
	"log"
	"net/http"
	"time"

	"traktor/notifications/internal/config"
	"traktor/notifications/internal/httpapi"
	"traktor/notifications/internal/push"
	"traktor/notifications/internal/service"
	"traktor/notifications/internal/store"
)

func main() {
	cfg := config.Load()

	var provider push.Provider
	if cfg.FCMProjectID == "" {
		log.Println("notifications: push в тест-режиме (fake provider)")
		provider = push.NewFake()
	} else {
		// Авторизация FCM — через сервисный аккаунт Cloud Run (metadata),
		// без файлов-ключей в репозитории.
		provider = push.NewFCM(cfg.FCMProjectID, push.NewMetadataTokenSource())
		log.Printf("notifications: FCM включён для проекта %s", cfg.FCMProjectID)
	}

	st := store.NewMemory() // прод: store.NewPostgres(pool) с тегом postgres
	svc := service.New(st, provider, time.Now)
	srv := httpapi.New(svc)

	addr := ":" + cfg.Port
	log.Printf("notifications: слушаю %s", addr)
	if err := http.ListenAndServe(addr, srv.Routes()); err != nil {
		log.Fatal(err)
	}
}
