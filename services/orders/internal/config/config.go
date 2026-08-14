package config

import "os"

// Config — окружение сервиса orders.
type Config struct {
	Port string
	// DatabaseURL пуст → хранилище в памяти (dev без базы).
	// Задан → Postgres + PostGIS с накатом миграций.
	DatabaseURL string
}

func Load() *Config {
	return &Config{
		Port:        getenv("PORT", "8080"),
		DatabaseURL: os.Getenv("DATABASE_URL"),
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
