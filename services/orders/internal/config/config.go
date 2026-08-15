package config

import "os"

// Config — окружение сервиса orders.
type Config struct {
	Port string
	// DatabaseURL пуст → хранилище в памяти (dev без базы).
	// Задан → Postgres + PostGIS с накатом миграций.
	DatabaseURL string
	// NotificationsURL пуст → уведомления не отправляются (dev, тесты).
	// Задан → сервис orders сообщает notifications о новых откликах и решениях.
	NotificationsURL string
	// IdentityURL пуст → в списках останутся обезличенные подписи.
	// Задан → orders подтягивает имена участников из identity.
	IdentityURL string
}

func Load() *Config {
	return &Config{
		Port:             getenv("PORT", "8080"),
		DatabaseURL:      os.Getenv("DATABASE_URL"),
		NotificationsURL: os.Getenv("NOTIFICATIONS_URL"),
		IdentityURL:      os.Getenv("IDENTITY_URL"),
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
