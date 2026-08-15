// Package config — окружение сервиса media.
package config

import "os"

// Config — настройки хранилища фотографий.
//
// Локально это MinIO из docker-compose, в бою — Cloudflare R2: оба
// S3-совместимые, поэтому код один и тот же (ADR-5).
type Config struct {
	Port string

	Endpoint  string // s3-хост без схемы: localhost:19000
	AccessKey string
	SecretKey string
	Bucket    string
	UseSSL    bool

	// PublicBaseURL — по какому адресу файл читается снаружи. Локально это
	// сам MinIO, в бою — домен CDN (media.traktor.am).
	PublicBaseURL string
}

func Load() *Config {
	return &Config{
		Port:          getenv("PORT", "8085"),
		Endpoint:      getenv("S3_ENDPOINT", "127.0.0.1:19000"),
		AccessKey:     getenv("S3_ACCESS_KEY", "traktor"),
		SecretKey:     getenv("S3_SECRET_KEY", "traktor-local-secret"),
		Bucket:        getenv("S3_BUCKET", "traktor-media"),
		UseSSL:        os.Getenv("S3_USE_SSL") == "1",
		PublicBaseURL: getenv("MEDIA_PUBLIC_URL", "http://127.0.0.1:19000/traktor-media"),
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
