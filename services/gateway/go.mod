module traktor/gateway

go 1.25.0

// Зависимости добавляются `go mod tidy` (правило 23 — только зрелые библиотеки):
//   github.com/go-chi/chi/v5      — роутер и базовые middleware
//   github.com/go-chi/cors        — CORS
//   github.com/go-chi/httprate    — ограничение частоты запросов
//   github.com/lestrrat-go/jwx/v2 — загрузка и кэш JWKS
//   github.com/golang-jwt/jwt/v5  — проверка access-токенов

require (
	github.com/go-chi/chi/v5 v5.3.1
	github.com/go-chi/cors v1.2.2
	github.com/go-chi/httprate v0.16.0
	github.com/golang-jwt/jwt/v5 v5.3.1
	github.com/lestrrat-go/jwx/v2 v2.1.7
)

require (
	github.com/decred/dcrd/dcrec/secp256k1/v4 v4.4.1 // indirect
	github.com/goccy/go-json v0.10.6 // indirect
	github.com/klauspost/cpuid/v2 v2.2.10 // indirect
	github.com/lestrrat-go/blackmagic v1.0.4 // indirect
	github.com/lestrrat-go/httpcc v1.0.1 // indirect
	github.com/lestrrat-go/httprc v1.0.6 // indirect
	github.com/lestrrat-go/iter v1.0.2 // indirect
	github.com/lestrrat-go/option v1.0.1 // indirect
	github.com/segmentio/asm v1.2.1 // indirect
	github.com/zeebo/xxh3 v1.0.2 // indirect
	golang.org/x/crypto v0.53.0 // indirect
	golang.org/x/sys v0.46.0 // indirect
)
