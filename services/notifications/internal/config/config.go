package config

import "os"

// Config — окружение сервиса notifications. Ключей FCM в репозитории нет:
// Firebase Admin SDK берёт учётные данные из окружения (на Cloud Run — из
// сервисного аккаунта ревизии), здесь только идентификатор проекта.
type Config struct {
	Port string
	// FCMProjectID пуст → сервис работает на fake-провайдере (dev/тест до
	// заведения Firebase-проекта). Задан → включается реальный FCM.
	FCMProjectID string
	// DatabaseURL пуст → in-memory хранилище (dev). Задан → pgx + миграции.
	DatabaseURL string
}

func Load() *Config {
	return &Config{
		Port:         getenv("PORT", "8080"),
		FCMProjectID: os.Getenv("FCM_PROJECT_ID"),
		DatabaseURL:  os.Getenv("DATABASE_URL"),
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
