package config

import "os"

// Config — окружение сервиса notifications. Секреты/ключи FCM — не в репозитории:
// авторизация FCM идёт через сервисный аккаунт Cloud Run (metadata-сервер),
// поэтому здесь только идентификатор проекта Firebase.
type Config struct {
	Port string
	// FCMProjectID пуст → сервис работает на fake-провайдере (dev/тест до
	// заведения Firebase-проекта). Задан → включается реальный FCM v1.
	FCMProjectID string
}

func Load() *Config {
	return &Config{
		Port:         getenv("PORT", "8080"),
		FCMProjectID: os.Getenv("FCM_PROJECT_ID"),
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
