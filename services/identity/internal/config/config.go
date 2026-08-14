package config

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"os"
)

// Config — окружение сервиса identity. Секреты — из Secret Manager (env),
// не из файлов в репозитории (правило 15).
type Config struct {
	Port          string
	TestMode      bool // fake SMS, без реальных отправок
	DexatelKey    string
	DexatelSender string
	PrivKey       *ecdsa.PrivateKey
	Kid           string

	// DatabaseURL пуст → сервис поднимается на in-memory хранилище (dev).
	// Задан → pgx + автоматические миграции (прод и локальный Postgres).
	DatabaseURL string
	PhoneEncKey string // ключ шифрования телефонов (pgcrypto)

	// EphemeralKey = true означает, что ключ подписи сгенерирован при старте:
	// после перезапуска все выданные токены станут недействительными.
	EphemeralKey bool
}

func Load() (*Config, error) {
	c := &Config{
		Port:          getenv("PORT", "8080"),
		TestMode:      os.Getenv("TEST_MODE") == "1",
		DexatelKey:    os.Getenv("DEXATEL_API_KEY"),
		DexatelSender: getenv("DEXATEL_SENDER", "Traktor"),
		Kid:           getenv("JWT_KID", "dev"),
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		PhoneEncKey:   os.Getenv("PHONE_ENC_KEY"),
	}

	pemStr := os.Getenv("JWT_EC_PRIVATE_KEY_PEM")
	if pemStr != "" {
		k, err := parseEC(pemStr)
		if err != nil {
			return nil, err
		}
		c.PrivKey = k
	} else {
		// Dev: эфемерный ключ. В проде ОБЯЗАТЕЛЬНО задать JWT_EC_PRIVATE_KEY_PEM.
		k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			return nil, err
		}
		c.PrivKey = k
		c.EphemeralKey = true
	}

	// С реальной базой шифровать телефоны обязательно: без ключа они легли бы
	// в базу открытым текстом, а это прямое нарушение правила 15.
	if c.DatabaseURL != "" && c.PhoneEncKey == "" {
		return nil, errors.New("config: при DATABASE_URL обязателен PHONE_ENC_KEY")
	}
	return c, nil
}

func parseEC(s string) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(s))
	if block == nil {
		return nil, errors.New("config: bad PEM")
	}
	return x509.ParseECPrivateKey(block.Bytes)
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
