package config

import "os"

// Config — окружение сервиса catalog.
type Config struct {
	Port string
	// DatabaseURL пуст → сокращённый справочник в памяти (dev без базы).
	// Задан → Postgres с накатом миграций и полным сидом.
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
