package config

import (
	"os"
	"strconv"
	"time"
)

// Config — окружение шлюза. Апстримы и JWKS берутся из env (в проде —
// внутренние адреса Cloud Run / Secret Manager).
type Config struct {
	Port        string
	JWKSURL     string
	IdentityURL string
	RateLimit   int
	RateWindow  time.Duration
	AllowOrigin string
}

func Load() *Config {
	return &Config{
		Port:        getenv("PORT", "8080"),
		JWKSURL:     getenv("JWKS_URL", "http://localhost:8081/.well-known/jwks.json"),
		IdentityURL: getenv("IDENTITY_URL", "http://localhost:8081"),
		RateLimit:   getenvInt("RATE_LIMIT", 100),
		RateWindow:  time.Duration(getenvInt("RATE_WINDOW_SEC", 60)) * time.Second,
		AllowOrigin: getenv("ALLOW_ORIGIN", "*"),
	}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func getenvInt(k string, def int) int {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
